# Wrapic Documentation
Wrapic is a wireless Raspberry Pi cluster running various containerized applications on top of full Kubernetes. In my setup, a single 5-port PoE switch provides power to four RPi's all of which are equipped with PoE hats. One Raspberry Pi acts as a jump box connecting to an external network through WiFi and forwarding traffic through its ethernet port; this provides the other 3 RPi's with an internet connection and separates the cluster onto its own private network. The jump box also acts as the Kubernetes master node and all other RPi's are considered worker nodes in the cluster.

### Contents
- [Parts List](https://github.com/zakattack9/WRaPiC#parts-list)
- [Initial Headless RPi Setup](https://github.com/zakattack9/WRaPiC#initial-headless-rpi-setup)
- [Setting up the Jump Box and Cluster Network](https://github.com/zakattack9/WRaPiC#setting-up-the-jump-box-and-cluster-network)
- [Installing Docker and Kubernetes w/Flannel CNI](https://github.com/zakattack9/WRaPiC#installing-docker-and-kubernetes-wflannel-cni)
  - [Worker Node Setup](https://github.com/zakattack9/WRaPiC#worker-node-setup)
  - [Master Node Setup](https://github.com/zakattack9/WRaPiC#master-node-setup)
- [Extra Configurations]
  - Configure iTerm2 Window Arrangement and Profile
  - Installing Calico CNI

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
- *4x* 32GB MicroSD cards
  - I'd recommend sticking to a reputable brand
- Raspberry Pi Cluster Case
  - one with good ventilation and heat dissipation is recommended 

## Initial Headless RPi Setup
In headless setup, only WiFi and ssh are used to configure the RPi's without the need for an external monitor and keyboard.

1) Install Raspberry Pi OS Lite (32-bit) with [Raspberry Pi Imager](https://www.raspberrypi.org/software/)
  - As an alternative, the [Raspberry Pi OS (64-bit) beta](https://www.raspberrypi.org/forums/viewtopic.php?p=1668160) may be installed instead if you plan to use arm64 Docker images or would like to use Calico as your K8s CNI; it is important to note that the 64-bit beta includes the full Raspberry Pi OS which includes the desktop GUI and therefore may contain unneeded packages/bulk.
  - Another great option if an arm64 architecture is desired, is to install the officially supported 64-bit Ubuntu Server OS using the Raspberry Pi Imager.
2) Create `ssh` file in root directory of micro sd card
- [set up WiFi connection](https://www.raspberrypi.org/documentation/configuration/wireless/headless.md)
- `wpa_supplicant.conf` 
```
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
  ssid="<insert WiFi SSID>"
  psk="<insert WiFi password>"
}
```
- connect to RPi:
	- with `ssh pi@raspberrypi.local`
	- use `ping raspberrypi.local` to get RPi IP address
- once SSHed can double check RPi IP address with `ip addr show` (look for wlan0 IP)
- optionally [set up a static IP address if needed](https://www.raspberrypi.org/documentation/configuration/tcpip/)
- `sudo raspi-config` to access RPi setup config menu
	- change raspberry pi password
	- change network hostname for ssh
	- expand the filesystem, under advanced options, allowing use of full SD card for OS
	- update raspberry pi operating system
	- change locale
- reboot pi with `sudo reboot`
- set up [passwordless SSH access](https://www.raspberrypi.org/documentation/remote-access/ssh/passwordless.md)
	- if RSA pub/private keys are generated just need to run:
	`ssh-copy-id <USERNAME>@<IP-ADDRESS>`
- `sudo apt-get update -y` to update the package repository that apt-get uses
- `sudo apt-get upgrade -y` to update all installed packages
- [disable swap](https://www.raspberrypi.org/forums/viewtopic.php?p=1488821) with the command (run individually):
	- run individually to prevent errors with `kubectl get`
```
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo systemctl disable dphys-swapfile
```
- `sudo nano /etc/dphys-swapfile` and set `CONF_SWAPSIZE=0`

#### Side Notes:
- may need to comment out `SendEnv LANG LC_*` in `/etc/ssh/ssh_config` on host SSH client (Mac) to fix RPi locale problem
- check if swap is disabled with `free -h` look for “Swap:”
	- may also use `sudo swapon —summary` (should return nothing)
- this disable swap command did not seem to work on RPi Buster (the one above should be used)
```
sudo dphys-swapfile swapoff && sudo dphys-swapfile uninstall && sudo update-rc.d dphys-swapfile remove
```
- should backup SSH keys

## Setting up the Jump Box and Cluster Network
- [followed this guide to router configuration](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/)
- [referenced this guide for other setup tips](https://medium.com/better-programming/how-to-set-up-a-raspberry-pi-cluster-ff484a1c6be9)
- set up wrapic0 (router) `/etc/dhcpcd.conf` see [dhcpcd.conf](https://manpages.debian.org/testing/dhcpcd5/dhcpcd.conf.5.en.html)
	- declares static IP for ethernet port and WiFi
	- note that the static IP address for wlan0 should be within the range of the DHCP pool on the router
```
interface eth0
static ip_address=10.0.0.1/8
static domain_name_servers=1.1.1.1,1.0.0.1
nolink

interface wlan0
static ip_address=192.168.29.229/24
static routers=192.168.29.1
static domain_name_servers=1.1.1.1,1.0.0.1
```

- install `dnsmasq` with `sudo apt install dnsmasq` 
- backup existing `/etc/dnsmasq.conf`
- add to `/etc/dnsmasq.conf`
```bash
# Provide a DHCP service over our eth0 adapter (ethernet port)
interface=eth0

# Listen on the static IP address of the RPi router
listen-address=10.0.0.1

# Declare DHCP range with an IP address lease time of 12 hours
# 97 host addresses total (128 - 32 + 1)
dhcp-range=10.0.0.32,10.0.0.128,12h

# Assign static IPs to the kube cluster members (RPi K8s worker nodes 1 to 3)
# This would make it easier for tunneling, certs, etc.
# RPi MAC address: b8:27:eb:00:00:0X
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

- `DNSMASQ_EXCEPT=lo` to the end of `/etc/default/dnsmasq` see [here](https://raspberrypi.stackexchange.com/questions/37439/proper-way-to-prevent-dnsmasq-from-overwriting-dns-server-list-supplied-by-dhcp)
	- needed to prevent overwriting `/etc/resolv.conf` which can break the coredns pods in later kubeadm init
- use `sudo dpkg-reconfigure iptables-persistent` to re-save iptables and persist them 

#### Side Notes:
- can disable dnsmasq by editing `/etc/default/dnsmasq` and changing `ENABLED=1` to `ENABLED=0` (doesn’t work)
- check iptables rules with `sudo iptables -L -n -v`
- check dnsmasq status with `sudo service dnsmasq status`
- restart dnsmasq with `sudo /etc/init.d/dnsmasq restart`
- stop dnsmasq with `sudo service dnsmasq stop` (will restart on boot)
- `ifconfig eth0` can be used to find each RPi’s MAC address (look next to “ether”)
- label nodes with `kubectl label node <node-name> node-role.kubernetes.io/<role>=<role>`
	- `<role>` should be the same if setting the role for a node currently with role set as `<none>`
- remove label with `kubectl label node <node-name> node-role.kubernetes.io/<role>-`

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

## TODO
- setup ansible playbooks:
	- RPi router configuration
	- RPi disable swap and SSH key setup
	- RPi kubernetes setup
- disable SSH password access (keys only)
- install zsh with plugins (zsh-syntax-highlighting, zsh-autosuggest, docker, kubernetes)
- install powerlevel10k
- set up a reverse SSH tunnel to allow for direct SSH into worker nodes in the internal cluster network from MBP without needing to SSH from the Pi router
