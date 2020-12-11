# WRaPiC Documentation
#code/projects/wrapic #code/raspberrypi

## Initial RPi Setup (w/SSH and WiFi)
- install Raspberry Pi OS Lite (32-bit) w/Raspberry Pi Imager 
- create `ssh` file in root directory of micro sd card
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

## Setting up RPi Router and Cluster Network
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
static domain_name_servers=1.1.1.1
```

- install `dnsmasq` with `sudo apt install dnsmasq` 
- backup existing `/etc/dnsmasq.conf`
- add to `/etc/dnsmasq.conf`
```bash
# Provide a DHCP service over our eth0 adapter (ethernet port)
interface=eth0

# We will listen on the static IP address of the RPi router declared earlier
listen-address=10.0.0.1

# Declare DHCP range with an IP address lease time of 12 hours
# 97 host addresses total (128 - 32 + 1)
dhcp-range=10.0.0.32,10.0.0.128,12h

# Assign static IPs to the kube cluster members (RPi K8s worker nodes 1 to 3)
# This would make it easier for tunneling, certs, etc.
# RPi MAC address: b8:27:eb:00:00:0X
dhcp-host=dc:a6:32:c6:9e:33,10.0.0.50
dhcp-host=dc:a6:32:c6:9e:6f,10.0.0.51
dhcp-host=dc:a6:32:c6:9e:75,10.0.0.52

# This is where you declare any name-servers (using Cloudflare's)
server=1.1.1.1
server=1.0.0.1

# Bind dnsmasq to the interfaces it is listening on (eth0)
bind-interfaces

# Never forward plain names (without a dot or domain part)
domain-needed

# Never forward addresses in the non-routed address spaces.
bogus-priv

# Use the hosts file on this machine allows SSH to other machines on network
expand-hosts

# Useful for debugging issues
# log-queries
# log-dhcp
```

- use `sudo dpkg-reconfigure iptables-persistent` to re-save iptables and persist them 

#### Side Notes:
- can disable dnsmasq by editing `/etc/default/dnsmasq` and changing `ENABLED=1` to `ENABLED=0` (doesn’t work)
- check iptables rules with `sudo iptables -L -n -v`
- check dnsmasq status with `sudo service dnsmasq status`
- stop dnsmasq with `sudo service dnsmasq stop` (will restart on boot)
- `ifconfig eth0` can be used to find each RPi’s MAC address (look next to “ether”)

## Configure iTerm Window Arrangement and Profiles
- `ssh pi@routerPi.local`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode1.local'`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode2Pi.local'`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode3Pi.local'`

## Installing Docker & Kubernetes
#### Done for all RPis
- did not run `sudo sysctl net.bridge.bridge-nf-call-iptables=1`
- install latest version of Docker 
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

#### Done only for Master Node RPi
- `sudo kubeadm config images pull -v3`
- `sudo kubeadm init --token-ttl=0 --pod-network-cidr=10.244.0.0/16`
```bash
[init] Using Kubernetes version: v1.20.0
[preflight] Running pre-flight checks
	[WARNING IsDockerSystemdCheck]: detected "cgroupfs" as the Docker cgroup driver. The recommended driver is "systemd". Please follow the guide at https://kubernetes.io/docs/setup/cri/
	[WARNING SystemVerification]: this Docker version is not on the list of validated versions: 20.10.0. Latest validated version: 19.03
	[WARNING SystemVerification]: missing optional cgroups: hugetlb
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local wrapic0] and IPs [10.96.0.1 192.168.29.228]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [localhost wrapic0] and IPs [192.168.29.228 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [localhost wrapic0] and IPs [192.168.29.228 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests". This can take up to 4m0s
[kubelet-check] Initial timeout of 40s passed.
[apiclient] All control plane components are healthy after 54.012608 seconds
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config-1.20" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node wrapic0 as control-plane by adding the labels "node-role.kubernetes.io/master=''" and "node-role.kubernetes.io/control-plane='' (deprecated)"
[mark-control-plane] Marking the node wrapic0 as control-plane by adding the taints [node-role.kubernetes.io/master:NoSchedule]
[bootstrap-token] Using token: finohx.iubhit4chg8yjgxe
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.29.229:6443 --token 6m5r1q.z5dfe04hvsaexne3 \
    --discovery-token-ca-cert-hash sha256:9f9534ffb069c080be1eff9dec7146af5858a14a7f800e6ef55a8d17926e0533
```

- run following commands after `kubeadm init`
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

- double check status of master node pods `kubectl get pods --namespace=kube-system`
- run `kubeadm join` command on all worker nodes
```
kubeadm join 192.168.29.228:6443 --token pmyetu.h26kacjcmg7yoymp \
  --discovery-token-ca-cert-hash sha256:04a977d58183abe5c25ac7fcba72192b5e9557b0f7b75028be1c5f4e1f1fd059
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

## Attempted to install Calico
- did not work (see side notes)
- get calico yaml `curl https://docs.projectcalico.org/manifests/calico.yaml -O`
- open `calico.yaml` in nano and search for `192.168.0.0/16` 
	- uncomment and replace with:
```
- name: CALICO_IPV4POOL_CIDR
  value: "10.244.0.0/16"
```
- run the following:
```
sudo -i
swapoff -a
exit
strace -eopenat kubectl version
```
	- `sudo -I`
	- `swapoff -a`
	- `exit`
	- `strace -eopenat kubectl version`

- `kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml`
- `curl https://docs.projectcalico.org/manifests/custom-resources.yaml -O`
- modify default IP pool CIDR to match pod network CIDR (10.244.0.0/16)
	- `nano custom-resources`

#### Side Notes:
- Calico could be used but it would require installation of an arm64 Raspian image (currently in beta)
	- Calico only supports amd64 and arm64 (as of 12/10)

## TODO
- setup ansible playbooks:
	- RPi router configuration
	- RPi disable swap and SSH key setup
	- RPi kubernetes setup
- disable SSH password access (keys only)
- set up a reverse SSH tunnel to allow for direct SSH into worker nodes in the internal cluster network from MBP without needing to SSH from the Pi router
