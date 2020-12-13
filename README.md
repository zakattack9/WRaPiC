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
  - [Configure iTerm2 Window Arrangement and Profile](https://github.com/zakattack9/WRaPiC#installing-calico-cni)
  - [Installing Calico CNI](https://github.com/zakattack9/WRaPiC#configure-iterm-window-arrangement-and-profiles)
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
  - As an alternative, the [Raspberry Pi OS (64-bit) beta](https://www.raspberrypi.org/forums/viewtopic.php?p=1668160) may be installed instead if you plan to use arm64 Docker images or would like to use Calico as your K8s CNI; it is important to note that the 64-bit beta includes the full Raspberry Pi OS which includes the desktop GUI and therefore may contain unneeded packages/bulk.
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
4) Insert the micro SD card back into the Pi and power it on
5) Connect to the RPi by running `ssh pi@raspberrypi.local`; you can also use `ping raspberrypi.local` to get the RPi's IP address then use `ssh pi@<ip-address>`
6) Use `sudo raspi-config` to access the RPi configuration menu
  - Change the password from its default `raspberry`
  - Change the hostname which can be used for easier ssh 
  - Expand the filesystem, under advanced options, allowing the full use of the SD card for the OS
  - Update the operating system to the latest version
  - Change the locale
7) Reboot the RPi with `sudo reboot`
8) Set up [passwordless SSH access](https://www.raspberrypi.org/documentation/remote-access/ssh/passwordless.md)
  - if you have previously generated RSA public/private keys execute `ssh-copy-id <USERNAME>@<IP-ADDRESS or HOSTNAME>`
9) Update the package repository with `sudo apt-get update -y`
10) Update all installed packages with `sudo apt-get upgrade -y`
11) Disable swap with the following commands—it's recommended to run the commands individually to prevent some errors with `kubectl get` later on
```bash
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo systemctl disable dphys-swapfile
```

#### Side Notes:
- May need to comment out `SendEnv LANG LC_*` in `/etc/ssh/ssh_config` on host SSH client to fix RPi locale problems
- Check if swap is disabled with `free -h` (look for “Swap:”); may also use `sudo swapon —summary` which should return nothing
- If swap is still not disabled after reboot, try editing `/etc/dphys-swapfile` and set `CONF_SWAPSIZE=0`
- Although mentioned frequently, the disable swap command below did not seem to work on RPi Buster OS to fully disable swap (the commands mentioned in step 11 should be used instead)
```
sudo dphys-swapfile swapoff && sudo dphys-swapfile uninstall && sudo update-rc.d dphys-swapfile remove
```

## Setting up the Jump Box and Cluster Network
The following steps will setup the jump box RPi so that it acts as a DHCP server and DNS forwarder. It is assumed that at this point all RPi's have already been setup and are all connected to the switch.

1) Set up a [static IP address](https://www.raspberrypi.org/documentation/configuration/tcpip/) for both ethernet and WiFi interfaces by creating a [dhcpcd.conf](https://manpages.debian.org/testing/dhcpcd5/dhcpcd.conf.5.en.html) in `/etc/`
  - A sample `dhcpcd.conf` is provided [here](./dhcpcd.conf)
  - Note that the static IP address for `wlan0` should be within the DHCP pool range on the router
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
3) Install [dnsmasq](https://www.linux.org/docs/man8/dnsmasq.html) with `sudo apt install dnsmasq` 
4) Backup existing `dnsmasq.conf` with `sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup`
5) Create a new dnsmasq config file with `sudo nano /etc/dnsmasq.conf` and add the following
  - Note that the `listen-address` is the same as the `static ip-address` for `eth0` declared in `dhcpcd.conf`
  - If you have more than three worker nodes, declare more `dhcp-host` as needed with the correct MAC addresses
  - `ifconfig eth0` can be used to find each RPi’s MAC address (look next to “ether”)
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
6) Edit `/etc/default/dnsmasq` and add `DNSMASQ_EXCEPT=lo` at the end of the file
  - This is needed to [prevent dnsmasq from overwriting](https://raspberrypi.stackexchange.com/questions/37439/proper-way-to-prevent-dnsmasq-from-overwriting-dns-server-list-supplied-by-dhcp) `/etc/resolv.conf` on reboot which can crash the coredns pods when later initializing kubeadm
7) To prevent errors with booting up dnsmasq, use `sudo nano /etc/init.d/dnsmasq` and add `sleep 10` to the top of the file
8) Reboot the RPi for dnsmasq changes to take effect: `sudo reboot`
9) ssh back into the RPi jump box and double check that dnsmasq is running with `sudo service dnsmasq status`
10) Edit `/etc/sysctl.conf` and uncomment `net.ipv4.ip_forward=1` to enable IPv4 forwarding
11) Add the following `iptables` rules to enable port forwarding
```bash
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
```
12) Install `sudo apt install iptables-persistent` which will be used to persist our newly added `iptables` rules across reboots
13) Use `sudo dpkg-reconfigure iptables-persistent` persist our rules

#### Side Notes:
- If something goes wrong, I highly recommend checking out [Tim Downey's RPi router guide](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/) as additional information is provided
- Check `iptables` rules with `sudo iptables -L -n -v`
- To check the current leases provided by dnsmasq use `cat /var/lib/misc/dnsmasq.leases`
- Check dnsmasq's status with `sudo service dnsmasq status`
- Restart dnsmasq with `sudo /etc/init.d/dnsmasq restart`
- Stop dnsmasq with `sudo service dnsmasq stop` (will restart on boot)

## Installing Docker and Kubernetes w/Flannel CNI
### Worker Node Setup
These steps should be performed on all RPi's within the cluster *including* the jump box/master node.

- install latest version of Docker 
	- must use this script as specified in Docker docs [Install Docker Engine on Debian | Docker Documentation](https://docs.docker.com/engine/install/debian/#install-using-the-convenience-script)
```bash
curl -sSL get.docker.com | sh && sudo usermod pi -aG docker
```
- install specific version of Docker
```bash
export VERSION=19.03.13 && curl -sSL get.docker.com | sh
sudo usermod pi -aG docker
```
- `sudo nano /boot/cmdline.txt` and added `cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory` to end of line
- install latest version of K8s
```bash
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
  echo “deb http://apt.kubernetes.io/ kubernetes-xenial main” | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
  sudo apt-get update -q && \
  sudo apt-get install -qy kubeadm
```
- install specific version of K8s
```bash
# install specific veresion of k8s
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
  echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
  sudo apt-get update -q && \
  sudo apt-get install -qy kubelet=1.19.5-00 kubectl=1.19.5-00 kubeadm=1.19.5-00
```
- `sudo sysctl net.bridge.bridge-nf-call-iptables=1`

### Master Node Setup
- `sudo kubeadm config images pull -v3`
- ensure that `/etc/resolv.conf` does not have `nameserver 127.0.0.1` 
	- if `nameserver 127.0.0.1` exists, remove and use `nameserver 1.1.1.1`
	- also ensure that `dnsmasq` is not overwriting `/etc/resolv.conf` on startup (see above)
	- if not fixed, will result in coredns pods crashing
- init for flannel `sudo kubeadm init --token-ttl=0 --pod-network-cidr=10.244.0.0/16`
- run following commands after `kubeadm init`
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
- double check status of master node pods `kubectl get pods -n kube-system`
	- all pods should be running
- apply flannel config `kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml`
- run `kubeadm join` command on all worker nodes with command provided at the end of `kubeadm init`
```
kubeadm join 192.168.29.229:6443 --token 2t9e17.m8jbybvnnheqwwjp \
    --discovery-token-ca-cert-hash sha256:4ca2fa33d228075da93f5cb3d8337931b32c8de280a664726fe6fc73fba89563
```

#### Side Notes
- uninstall K8s with
```
kubeadm reset
sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni kube*   
sudo apt-get autoremove  
sudo rm -rf ~/.kube
```
- uninstall Docker with
```
sudo apt-get purge docker-ce docker-ce-cli containerd.io
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
```
- restart coredns pods with `kubectl rollout restart -n kube-system deployment/coredns`
- use `kubectl logs -n kube-system pod/coredns-f9fd979d6-6wg6n` to get logs of coredns pod
- was getting the following error for coredns pods after starting up kubeadm init
	- see [here](https://coredns.io/plugins/loop/#troubleshooting)
	- reccomends adding `resolvConf: /etc/resolv.conf` to `/etc/kubernetes/kubelet.conf`
```
[FATAL] plugin/loop: Loop (127.0.0.1:34536 -> :53) detected for zone ".", see coredns.io/plugins/loop#troubleshooting
```
- run the following if `kubectl get nodes` is not working:
	- see potential solutions [here](https://discuss.kubernetes.io/t/the-connection-to-the-server-host-6443-was-refused-did-you-specify-the-right-host-or-port/552/28)
```
sudo -i
swapoff -a
exit
strace -eopenat kubectl version
```
- use `kubectl logs -n kube-system kube-flannel-ds-XXXXX` to get logs of flannel pod
- ran into some issues with the master node flannel pod:
	- resolved by running `sudo ip link delete flannel.1` on the host whose flannel pod was failing
	- deleted the flannel pod with `kubectl delete pod -n kube-system kube-flannel-ds-XXXXX`
- Label nodes with `kubectl label node <node-name> node-role.kubernetes.io/<role>=<role>`
	- `<role>` should be the same if setting the role for a node currently with role set as `<none>`
- remove label with `kubectl label node <node-name> node-role.kubernetes.io/<role>-`

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

#### Side Notes:
- Calico could be used but it would require installation of an arm64 Raspian image (currently in beta)
	- Calico only supports amd64 and arm64 (as of 12/10)

### Configure iTerm Window Arrangement and Profiles
- `ssh pi@routerPi.local`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode1.local'`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode2Pi.local'`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode3Pi.local'`

## References
- [Disabling swap](https://www.raspberrypi.org/forums/viewtopic.php?p=1488821)
- [Alex Ellis' K8s on Raspian repo](https://github.com/teamserverless/k8s-on-raspbian)
- [Tim Downey's RPi Router guide](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/)
- [Richard Youngkin's K8s cluster guide](https://medium.com/better-programming/how-to-set-up-a-raspberry-pi-cluster-ff484a1c6be9)

## TODO
- setup ansible playbooks:
	- RPi router configuration
	- RPi disable swap and SSH key setup
	- RPi kubernetes setup
- disable SSH password access (keys only)
- install zsh with plugins (zsh-syntax-highlighting, zsh-autosuggest, docker, kubernetes)
- install powerlevel10k
- set up a reverse SSH tunnel to allow for direct SSH into worker nodes in the internal cluster network from MBP without needing to SSH from the Pi router
