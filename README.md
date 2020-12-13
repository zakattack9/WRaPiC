# Wrapic Documentation
Wrapic is a wireless Raspberry Pi cluster running various containerized applications on top of full Kubernetes. In my setup, a single 5-port PoE switch provides power to four RPi's all of which are equipped with PoE hats. One Raspberry Pi acts as a jump box connecting to an external network through WiFi and forwarding traffic through its ethernet port; this provides the other 3 RPi's with an internet connection and separates the cluster onto its own private network. The jump box also acts as the Kubernetes master node and all other RPi's are considered worker nodes in the cluster.

### Contents
- [Parts List](https://github.com/zakattack9/WRaPiC#parts-list)
- [Initial Headless Raspberry Pi Setup](https://github.com/zakattack9/WRaPiC#initial-headless-raspberry-pi-setup)
- [Setting up the Jump Box and Cluster Network](https://github.com/zakattack9/WRaPiC#setting-up-the-jump-box-and-cluster-network)
- [Installing Docker and Kubernetes w/Flannel CNI](https://github.com/zakattack9/WRaPiC#installing-docker-and-kubernetes-wflannel-cni)
  - [Worker Node Setup](https://github.com/zakattack9/WRaPiC#worker-node-setup)
  - [Master Node Setup](https://github.com/zakattack9/WRaPiC#master-node-setup)
- [Extra Configurations](https://github.com/zakattack9/WRaPiC#extra-configurations)
  - [Configure iTerm2 Window Arrangement and Profile](https://github.com/zakattack9/WRaPiC#configure-iterm-window-arrangement-and-profiles)
  - [Installing Calico CNI](https://github.com/zakattack9/WRaPiC#installing-calico-cni)
  - [Install zsh w/Oh-my-zsh and Configure Plugins](https://github.com/zakattack9/WRaPiC#install-zsh-wohmyzsh-and-configure-plugins)
- [References](https://github.com/zakattack9/WRaPiC#references)

As a disclaimer, most of these steps have been adapted from multiple articles, guides, and documentations found online. Much credit goes to Alex Ellis' [Kubernetes on Raspian](https://github.com/teamserverless/k8s-on-raspbian) repository and Tim Downey's [Baking a Pi Router](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/) guide.

## Parts List
My cluster only includes 4 RPi 4B's though there is no limit to the amount of RPi's that can be used. If you choose to not go the PoE route, additional micro USB cables and a USB power hub will be needed to power the Pi's.
- *4x* Raspberry Pi 4B 2GB RAM
  - the 3B and 3B+ models will also suffice
  - it is recommended to get at least 2GB of RAM if running full K8s
- *4x* Official Raspberry Pi PoE Hats
- 5 Port PoE Gigabit Ethernet Switch
  - does not need to support PoE if you are not planning to purchase PoE hats
  - does not need to support gigabit ethernet though the Pi 4's do support it
- *4x* 0.5ft Ethernet Cables
  - I went with 0.5ft cables to keep my setup compact
  - at the very least, a Cat 5e cable is needed to support gigabit ethernet
- *4x* 32GB Micro SD cards
  - I'd recommend sticking to a reputable brand
- Raspberry Pi Cluster Case
  - one with good ventilation and heat dissipation is recommended 

## Initial Headless Raspberry Pi Setup
In headless setup, only WiFi and ssh are used to configure the RPi's without the need for an external monitor and keyboard. This will likely be the most tedious and time consuming part of the set up. These steps should be repeated individually for each RPi with only one RPi being connected to the network at a given time; this makes it easier to find and distinguish the RPi's in step 5.

1) Install Raspberry Pi OS Lite (32-bit) with [Raspberry Pi Imager](https://www.raspberrypi.org/software/)
  - As an alternative, the [Raspberry Pi OS (64-bit) beta](https://www.raspberrypi.org/forums/viewtopic.php?p=1668160) may be installed instead if you plan to use arm64 Docker images or would like to use Calico as your K8s CNI; it is important to note that the 64-bit beta is the full Raspberry Pi OS which includes the desktop GUI and therefore may contain unneeded packages/bulk.
  - Another great option if an arm64 architecture is desired, is to install the officially supported 64-bit Ubuntu Server OS using the Raspberry Pi Imager.
2) Create an empty `ssh` file (no extension) in the root directory of the micro sd card 
3) Create a `wpa_supplicant.conf` in the `boot` folder to [set up a WiFi connection](https://www.raspberrypi.org/documentation/configuration/wireless/headless.md)
```
# /boot/wpa_supplicant.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
  ssid="<WiFi-SSID>"
  psk="<WiFi-password>"
}
```
4) Insert the micro SD card back into the RPi and power it on
5) `ssh pi@raspberrypi.local` to connect to the RPi; `ping raspberrypi.local` may also be used to get the RPi's IP address to run `ssh pi@<ip-address>`
6) `sudo raspi-config` to access the RPi configuration menu for making the following changes
  - Change the password from its default `raspberry`
  - Change the hostname which can be used for easier ssh 
  - Expand the filesystem, under advanced options, allowing the full use of the SD card for the OS
  - Update the operating system to the latest version
  - Change the locale
7) Reboot the RPi with `sudo reboot`
8) Set up [passwordless SSH access](https://www.raspberrypi.org/documentation/remote-access/ssh/passwordless.md)
  - if you already have previously generated RSA public/private keys simply execute 
```ssh-copy-id <USERNAME>@<IP-ADDRESS or HOSTNAME>```
9) `sudo apt-get update -y` to update the package repository
10) `sudo apt-get upgrade -y` to update all installed packages
11) Disable swap with the following commands—it's recommended to run the commands individually to prevent some errors with `kubectl get` later on
```bash
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo systemctl disable dphys-swapfile
```

#### Side Notes
- May need to comment out `SendEnv LANG LC_*` in `/etc/ssh/ssh_config` on host SSH client to fix RPi locale problems
- Check if swap is disabled with `free -h` (look for “Swap:”); may also use `sudo swapon —summary` which should return nothing
- If swap is still not disabled after reboot, try editing `/etc/dphys-swapfile` and set `CONF_SWAPSIZE=0`
- Although mentioned frequently, the disable swap command below did not seem to work on RPi Buster OS to fully disable swap (the commands mentioned in step 11 should be used instead)
```
sudo dphys-swapfile swapoff && sudo dphys-swapfile uninstall && sudo update-rc.d dphys-swapfile remove
```

## Setting up the Jump Box and Cluster Network
The following steps will setup the RPi jump box such that it acts as a DHCP server and DNS forwarder. It is assumed that at this point all RPi's have already been setup and are connected to the switch.

1) Set up a [static IP address](https://www.raspberrypi.org/documentation/configuration/tcpip/) for both ethernet and WiFi interfaces by creating a [dhcpcd.conf](https://manpages.debian.org/testing/dhcpcd5/dhcpcd.conf.5.en.html) in `/etc/`
```
# /etc/dhcpcd.conf
interface eth0
static ip_address=10.0.0.1
static domain_name_servers=<dns-ip-address>
nolink

interface wlan0
static ip_address=<static-ip-address>
static routers=<router-ip-address>
static domain_name_servers=<dns-ip-address>
```
  - A sample `dhcpcd.conf` is provided [here](./dhcpcd.conf)
  - Note that the static IP address for `wlan0` should be within the DHCP pool range on the router
2) `sudo apt install dnsmasq` to install [dnsmasq](https://www.linux.org/docs/man8/dnsmasq.html) 
3) `sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup` to backup the existing `dnsmasq.conf`
4) Create a new dnsmasq config file with `sudo nano /etc/dnsmasq.conf` and add the following
```bash
# Provide a DHCP service over our eth0 adapter (ethernet port)
interface=eth0

# Listen on the static IP address of the RPi router
listen-address=10.0.0.1

# Declare DHCP range with an IP address lease time of 12 hours
# 97 host addresses total (128 - 32 + 1)
dhcp-range=10.0.0.32,10.0.0.128,12h

# Assign static IPs to the kube cluster members (RPi K8s worker nodes 1 to 3)
# This will make it easier for tunneling, certs, etc.
# Replace b8:27:eb:00:00:0X with the Raspberry Pi's actual MAC address
dhcp-host=b8:27:eb:00:00:01,10.0.0.50
dhcp-host=b8:27:eb:00:00:02,10.0.0.51
dhcp-host=b8:27:eb:00:00:03,10.0.0.52

# Declare name-servers (using Cloudflare's)
server=1.1.1.1
server=1.0.0.1

# Bind dnsmasq to the interfaces it is listening on (eth0)
# Commented out for now to help dnsmasq server start up
bind-interfaces

# Never forward plain names (without a dot or domain part)
domain-needed

# Never forward addresses in the non-routed address spaces.
bogus-priv

# Use the hosts file on this machine
expand-hosts

# Limits name services to dnsmasq only and will not use /etc/resolv.conf
no-resolv

# Uncomment to debug issues
# log-queries
# log-dhcp
```
  - Note that the `listen-address` is the same as the `static ip-address` for `eth0` declared in `dhcpcd.conf`
  - If you have more or less than three worker nodes, declare or delete `dhcp-host` as needed ensuring that the correct MAC addresses are used
  - `ifconfig eth0` can be used to find each RPi’s MAC address (look next to “ether”)
5) `sudo nano /etc/default/dnsmasq` and add `DNSMASQ_EXCEPT=lo` at the end of the file
  - This is needed to [prevent dnsmasq from overwriting](https://raspberrypi.stackexchange.com/questions/37439/proper-way-to-prevent-dnsmasq-from-overwriting-dns-server-list-supplied-by-dhcp) `/etc/resolv.conf` on reboot which can crash the coredns pods when later initializing kubeadm
6) `sudo nano /etc/init.d/dnsmasq` and add `sleep 10` to the top of the file to prevent errors with booting up dnsmasq
7) `sudo reboot` to reboot the RPi for dnsmasq changes to take effect
8) ssh back into the RPi jump box and ensure that dnsmasq is running with `sudo service dnsmasq status`
9) `sudo nano /etc/sysctl.conf` and uncomment `net.ipv4.ip_forward=1` to enable IPv4 forwarding
10) Add the following `iptables` rules to enable port forwarding
```bash
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
```
11) `sudo apt install iptables-persistent` to install iptables-persistent
12) `sudo dpkg-reconfigure iptables-persistent` to re-save and persist our `iptables` rules across reboots

#### Side Notes
- If something goes wrong, I highly recommend checking out [Tim Downey's RPi router guide](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/) as additional information is provided there
- `sudo iptables -L -n -v` to check the current `iptables` rules
- `cat /var/lib/misc/dnsmasq.leases` to check the current leases provided by dnsmasq
- `sudo service dnsmasq restart` to restart dnsmasq
- `sudo service dnsmasq stop` to stop dnsmasq (will restart on boot)

## Installing Docker and Kubernetes w/Flannel CNI
The following steps will install and configure Docker and Kubernetes on all RPi's. This setup uses Flannel as the Kubernetes CNI although Weave Net may also be used as an alternative. Calico CNI may be swapped out for Flannel/Weave Net providing that an OS with an `arm64` architecture has been installed on all RPi's.

### Worker Node Setup
These steps should be performed on all RPi's within the cluster *including* the jump box/master node.

1) Install Docker
##### Install the latest version of Docker
```bash
curl -sSL get.docker.com | sh && sudo usermod pi -aG docker
```
  - Note this specific script must be used as specified in the [Docker documentation](https://docs.docker.com/engine/install/debian/#install-using-the-convenience-script)
##### Install a specific version of Docker
```bash
export VERSION=<version> && curl -sSL get.docker.com | sh
sudo usermod pi -aG docker
```
  - Where `<version>` is replaced with a specific Docker Engine version 
2) `sudo nano /boot/cmdline.txt` and add `cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory` to end of the line—do not make a new line and ensure that there's a space in front of `cgroup_enable=cpuset`
3) `sudo reboot` to reboot the RPi for boot changes to take effect (do not skip this step)
4) Install Kubernetes
##### Install the latest version of K8s
```bash
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
  echo “deb http://apt.kubernetes.io/ kubernetes-xenial main” | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
  sudo apt-get update -q && \
  sudo apt-get install -qy kubeadm
```
##### Install a specific version of K8s
```bash
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
  echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
  sudo apt-get update -q && \
  sudo apt-get install -qy kubelet=<version> kubectl=<version> kubeadm=<version>
```
  - Where `<version>` is replaced with a specific K8s version; append `-00` to the end of the version if it's not already added (e.g. 1.19.5 => 1.19.5-00)
5) `sudo sysctl net.bridge.bridge-nf-call-iptables=1`

### Master Node Setup
These steps should be performed only on one RPi (I used the RPi jump box).

1) `sudo kubeadm config images pull -v3`
2) `sudo nano /etc/resolv.conf` and ensure that it does not have `nameserver 127.0.0.1` 
  - If `nameserver 127.0.0.1` exists, remove it and replace it with another DNS IP address that isn't the loopback address, then double check that `DNSMASQ_EXCEPT=lo` has been added in `/etc/default/dnsmasq` to prevent dnsmasq from overwriting/adding `nameserver 127.0.0.1` to `/etc/resolv.conf` upon reboot
  - This step is crucial to prevent coredns pods from crashing upon running `kubeadm init`
3) `sudo kubeadm init --token-ttl=0 --pod-network-cidr=10.244.0.0/16` to initialize kubeadm with the Flannel cidr default
  - When this command finishes, save the `kubeadm join` command provided by `kubeadm init` for later
4) Run following commands after `kubeadm init` finishes
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
5) `kubectl get pods -n kube-system` to double check the status of all master node pods (each should have a status of "Running")
  - If the coredns pods are failing, see the *Side Notes* for this section
6) Apply [Flannel](https://github.com/coreos/flannel) config
```bash
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```
7) Run the `kubeadm join` command saved in step 3, on all worker nodes, an example join command is provided below
```bash
kubeadm join 192.168.29.229:6443 --token 2t9e17.m8jbybvnnheqwwjp \
    --discovery-token-ca-cert-hash sha256:4ca2fa33d228075da93f5cb3d8337931b32c8de280a664726fe6fc73fba89563
```

#### Side Notes
- To uninstall K8s use the following commands
```bash
kubeadm reset
sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni kube*   
sudo apt-get autoremove  
sudo rm -rf ~/.kube
```
- To uninstall Docker use the following commands
```bash
sudo apt-get purge docker-ce docker-ce-cli containerd.io
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
```
- `kubectl rollout restart -n kube-system deployment/coredns` to restart coredns pods
- `kubectl logs -n kube-system pod/coredns-<pod-id>` to get the logs of a specific coredns pod
- I was getting the following error in the coredns logs for the coredns pods after starting up kubeadm in which the [linked coredns docs](https://coredns.io/plugins/loop/#troubleshooting) recommends adding `resolvConf: /etc/resolv.conf` to `/etc/kubernetes/kubelet.conf`; however, the solution for me was removing `nameserver 127.0.0.1` from `/etc/resolv.conf` before running `kubeadm init`
```
[FATAL] plugin/loop: Loop (127.0.0.1:34536 -> :53) detected for zone ".", see coredns.io/plugins/loop#troubleshooting
```
- Run the following if `kubectl get nodes` is not working; [this thread](https://discuss.kubernetes.io/t/the-connection-to-the-server-host-6443-was-refused-did-you-specify-the-right-host-or-port/552/28) discusses why `kubectl get nodes` may not be working and some potential solutions to prevent having to always run the below commands
```bash
sudo -i
swapoff -a
exit
strace -eopenat kubectl version
```
- `kubectl logs -n kube-system kube-flannel-ds-<pod-id>` to get logs of a specific Flannel pod
- I also ran into [some issues](https://github.com/coreos/flannel/issues/1060) with the master node Flannel pod; this problem was resolved by running the following in order
  - `sudo ip link delete flannel.1` on the master node (RPi jump box)
  - `kubectl delete pod -n kube-system kube-flannel-ds-<pod-id>` to delete the Flannel pod
  - Wait for K8s to automatically recreate the pod, then profit
- `kubectl label node <node-name> node-role.kubernetes.io/<role>=<role>` to label nodes
	- `<role>` should be the same if you're setting the role for a node currently with a role set as `<none>`
- `kubectl label node <node-name> node-role.kubernetes.io/<role>-` to remove a label

## Extra Configurations
### Installing Calico CNI
- did not work (see side notes)
- get calico yaml `curl https://docs.projectcalico.org/manifests/calico.yaml -O`
- open `calico.yaml` in nano and search for `192.168.0.0/16` 
	- uncomment and replace with:
```
- name: CALICO_IPV4POOL_CIDR
  value: "10.244.0.0/16"
```
- `kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml`
- `curl https://docs.projectcalico.org/manifests/custom-resources.yaml -O`
- modify default IP pool CIDR to match pod network CIDR (10.244.0.0/16)
	- `nano custom-resources`

#### Side Notes
- Calico could be used but it would require installation of an arm64 Raspian image (currently in beta)
	- Calico only supports amd64 and arm64 (as of 12/10)

### Configure iTerm Window Arrangement and Profiles
- `ssh pi@routerPi.local`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode1.local'`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode2Pi.local'`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode3Pi.local'`

### Install zsh w/Oh-my-zsh and Configure Plugins
1) `sudo apt-get install zsh`
2) `chsh -s $(which zsh)` to install default shell to zsh
3) `sudo apt-get install git wget` to install `git` and `wget` packages
4) Install Oh-my-zsh framework
```bash
wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh
cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
source .zshrc
```
5) Install zsh syntax highlighting plugin
```bash
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git
mv zsh-syntax-highlighting ~/.oh-my-zsh/plugins
echo "source ~/.oh-my-zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ~/.zshrc
```
6) Install zsh auto-suggestions plugin
```bash
git clone https://github.com/zsh-users/zsh-autosuggestions
mv zsh-autosuggestions ~/.oh-my-zsh/custom/plugins
```
7) `sudo nano ~/.zshrc` and modify the plugin list to include the following
```bash
plugins=(git docker docker zsh-autosuggestions)
```
8) `source .zshrc` to refresh shell

## References
- [Disabling swap](https://www.raspberrypi.org/forums/viewtopic.php?p=1488821)
- [Alex Ellis' K8s on Raspian repo](https://github.com/teamserverless/k8s-on-raspbian)
- [Tim Downey's RPi Router guide](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/)
- [Richard Youngkin's K8s cluster guide](https://medium.com/better-programming/how-to-set-up-a-raspberry-pi-cluster-ff484a1c6be9)
- [Install zsh on Linux](https://linoxide.com/tools/install-zsh-on-linux/)

## TODO
- setup ansible playbooks:
	- RPi router configuration
	- RPi disable swap and SSH key setup
	- RPi kubernetes setup
- disable SSH password access (keys only)
- install zsh with plugins (zsh-syntax-highlighting, zsh-autosuggest, docker, kubernetes)
- install powerlevel10k
- set up a reverse SSH tunnel to allow for direct SSH into worker nodes in the internal cluster network from MBP without needing to SSH from the Pi router
