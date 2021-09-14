# Wrapic (Wireless Raspberry Pi Cluster)
![Wrapic](./images/wrapic_image.png)
Wrapic is a Wireless Raspberry Pi Cluster that can run various containerized applications on top of full Kubernetes. What makes the cluster "wireless" is that it doesn't need to be physically connected to a router via ethernet, instead it bridges off WiFi to receive internet—this is great for situations where the router is inaccessible.

In my setup, a single 5-port PoE switch provides power to four RPi 4B's all of which are equipped with PoE hats. One Raspberry Pi acts as a jump box connecting to an external network through WiFi and forwarding traffic through its ethernet port; this provides the other 3 RPi's with an internet connection and separates the cluster onto its own private network. The jump box also acts as the Kubernetes master node and all other RPi's are considered worker nodes in the cluster. The following setup documentation assumes this described setup where the master node doubles as a jump box—if a cluster without a jump box is desired, Alex Ellis' [Kubernetes on Raspian](https://github.com/teamserverless/k8s-on-raspbian) guide may be a better fit.

### Contents
Most sections include a *Side Notes* subsection that includes extra information for that specific section ranging from helpful commands to potential issues/solutions I encountered during my setup.
- [Parts List](https://github.com/zakattack9/WRaPiC#parts-list)
- [Initial Headless Raspberry Pi Setup](https://github.com/zakattack9/WRaPiC#initial-headless-raspberry-pi-setup)
  - [Side Notes](https://github.com/zakattack9/WRaPiC#side-notes)
- [Setting up the Jump Box and Cluster Network](https://github.com/zakattack9/WRaPiC#setting-up-the-jump-box-and-cluster-network)
  - [Side Notes](https://github.com/zakattack9/WRaPiC#side-notes-1)
- [Install Docker and Kubernetes w/Flannel CNI](https://github.com/zakattack9/WRaPiC#install-docker-and-kubernetes-wflannel-cni)
  - [Worker Node Setup](https://github.com/zakattack9/WRaPiC#worker-node-setup)
  - [Master Node Setup](https://github.com/zakattack9/WRaPiC#master-node-setup)
  - [Side Notes](https://github.com/zakattack9/WRaPiC#side-notes-2)
- [Install MetalLB and ingress-nginx](https://github.com/zakattack9/WRaPiC#install-metallb-and-ingress-nginx)
  - [Side Notes](https://github.com/zakattack9/WRaPiC#side-notes-3)
- [Extra Configurations](https://github.com/zakattack9/WRaPiC#extra-configurations)
  - [Install zsh w/Oh-my-zsh and Configure Plugins](https://github.com/zakattack9/WRaPiC#install-zsh-woh-my-zsh-and-configure-plugins)
    - [Side Notes](https://github.com/zakattack9/WRaPiC#side-notes-4)
  - [Kubernetes Dashboard Setup](https://github.com/zakattack9/WRaPiC#kubernetes-dashboard-setup)
  - [Install Calico CNI](https://github.com/zakattack9/WRaPiC#install-calico-cni)
    - [Side Notes](https://github.com/zakattack9/WRaPiC#side-notes-5)
  - [Configure iTerm2 Window Arrangement and Profile](https://github.com/zakattack9/WRaPiC#configure-iterm-window-arrangement-and-profiles)
  - [Install Prometheus and Grafana](https://github.com/zakattack9/WRaPiC#install-prometheus-and-grafana)
    - [Side Notes](https://github.com/zakattack9/WRaPiC#side-notes-6)
  - [Install EFK Stack (Elasticsearch, Fluent Bit, Kibana)](https://github.com/zakattack9/WRaPiC#install-efk-stack-elasticsearch-fluent-bit-kibana)
    - [Side Notes](https://github.com/zakattack9/WRaPiC#side-notes-7)
- [References](https://github.com/zakattack9/WRaPiC#references)

*As a disclaimer, most of these steps have been adapted from multiple articles, guides, and documentations found online which have been compiled into this README for easy access and a more straightforward cluster setup. Much credit goes to Alex Ellis' [Kubernetes on Raspian](https://github.com/teamserverless/k8s-on-raspbian) repository and Tim Downey's [Baking a Pi Router](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/) guide.*

## Parts List
My cluster only includes 4 RPi 4B's though there is no limit to the amount of RPi's that can be used. If you choose to not go the PoE route, additional micro USB cables and a USB power hub will be needed to power the Pi's.
- *4x* Raspberry Pi 4B 2GB RAM
  - the 3B and 3B+ models will also suffice
  - it is recommended to get at least 2GB of RAM for running full K8s
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

1. Install **Raspberry Pi OS Lite (32-bit)** with [Raspberry Pi Imager](https://www.raspberrypi.org/software/)
    - As an alternative, the [Raspberry Pi OS (64-bit) beta](https://www.raspberrypi.org/forums/viewtopic.php?p=1668160) may be installed instead if you plan to use arm64 Docker images or would like to use Calico as your K8s CNI; it is important to note that the 64-bit beta is the full Raspberry Pi OS which includes the desktop GUI and therefore may contain unneeded packages/bulk
    - Another great option if an arm64 architecture is desired, is to install the officially supported 64-bit Ubuntu Server OS using the Raspberry Pi Imager
2. Create an empty `ssh` file (no extension) in the root directory of the micro sd card 
3. Create a `wpa_supplicant.conf` in the `boot` folder to [set up a WiFi connection](https://www.raspberrypi.org/documentation/configuration/wireless/headless.md)
    
    ```bash
    # /boot/wpa_supplicant.conf
    ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
    update_config=1
    country=US

    network={
      ssid="<WiFi-SSID>"
      psk="<WiFi-password>"
    }
    ```
    - The remote machine which will be used to configure and ssh into all the RPi's should be on the same network as declared in the above `wpa_supplicant.conf`

4. Insert the micro SD card back into the RPi and power it on
5. `ssh pi@raspberrypi.local` to connect to the RPi; `ping raspberrypi.local` may also be used to get the RPi's IP address to run `ssh pi@<ip-address>`
6. `sudo raspi-config` to access the RPi configuration menu for making the following recommended changes:
    - Change the password from its default `raspberry`
    - Change the hostname which can be used for easier ssh 
    - Expand the filesystem, under advanced options, allowing full use of the SD card for the OS
    - Update the operating system to the latest version
    - Change the locale
7. Reboot the RPi with `sudo reboot`
8. Set up [passwordless SSH access](https://www.raspberrypi.org/documentation/remote-access/ssh/passwordless.md)
    - if you already have previously generated RSA public/private keys simply execute 
    
    ```bash
    ssh-copy-id <USERNAME>@<IP-ADDRESS or HOSTNAME>
    ```
9. `sudo apt-get update -y` to update the package repository
10. `sudo apt-get upgrade -y` to update all installed packages
11. Disable swap with the following commands—it's recommended to run the commands individually to prevent some errors with `kubectl get` later on
    
    ```bash
    sudo dphys-swapfile swapoff
    sudo dphys-swapfile uninstall
    sudo systemctl disable dphys-swapfile
    ```
12. At this point, if you want to use zsh as the default shell for your RPi check out the *[Install zsh w/Oh-my-zsh and Configure Plugins](https://github.com/zakattack9/WRaPiC#install-zsh-woh-my-zsh-and-configure-plugins)* section, otherwise move on to the next section which sets up the jump box

#### Side Notes
- May need to comment out `SendEnv LANG LC_*` in `/etc/ssh/ssh_config` on host SSH client to fix RPi locale problems
- Check if swap is disabled with `free -h` (look for “Swap:”); may also use `sudo swapon —summary` which should return nothing
- If swap is still not disabled after reboot, try editing `/etc/dphys-swapfile` and set `CONF_SWAPSIZE=0`
- Although mentioned frequently, the disable swap command below did not seem to work on RPi Buster OS to fully disable swap (the commands mentioned in step 11 should be used instead)
    
    ```bash
    sudo dphys-swapfile swapoff && sudo dphys-swapfile uninstall && sudo update-rc.d dphys-swapfile remove
    ```

## Setting up the Jump Box and Cluster Network
The following steps will set up the RPi jump box such that it acts as a DHCP server and DNS forwarder. It is assumed that at this point all RPi's have already been configured and are connected to the switch.

### Preparation
Before the jump box is set up, it's important to delete the `wpa_supplicant.conf` files on all RPi's **except** the jump box itself; this is because we want to force the RPi's onto our private cluster network thats separated via our switch and jump box. The jump box will maintain its WiFi connection forwarding internet out its ethernet port and into the switch who then feeds it to the other connected RPi's.

1. `sudo rm /etc/wpa_supplicant/wpa_supplicant.conf` to delete the `wpa_supplicant.conf`
2. `sudo reboot` for changes to take effect
3. Prior to steps 1 and 2, you could ssh into the RPi's directly from your remote machine since they were on the same WiFi network

### Jump Box Setup
1. Set up a [static IP address](https://www.raspberrypi.org/documentation/configuration/tcpip/) for both ethernet and WiFi interfaces by creating a [dhcpcd.conf](https://manpages.debian.org/testing/dhcpcd5/dhcpcd.conf.5.en.html) in `/etc/`
    
    ```bash
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
2. `sudo apt install dnsmasq` to install [dnsmasq](https://www.linux.org/docs/man8/dnsmasq.html) 
3. `sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup` to backup the existing `dnsmasq.conf`
4. Create a new dnsmasq config file with `sudo nano /etc/dnsmasq.conf` and add the following

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
5. `sudo nano /etc/default/dnsmasq` and add `DNSMASQ_EXCEPT=lo` at the end of the file
    - This is needed to [prevent dnsmasq from overwriting](https://raspberrypi.stackexchange.com/questions/37439/proper-way-to-prevent-dnsmasq-from-overwriting-dns-server-list-supplied-by-dhcp) `/etc/resolv.conf` on reboot which can crash the coredns pods when later initializing kubeadm
6. `sudo nano /etc/init.d/dnsmasq` and add `sleep 10` to the top of the file to prevent errors with booting up dnsmasq
7. `sudo reboot` to reboot the RPi for dnsmasq changes to take effect
8. ssh back into the RPi jump box and ensure that dnsmasq is running with `sudo service dnsmasq status`
9. `sudo nano /etc/sysctl.conf` and uncomment `net.ipv4.ip_forward=1` to enable NAT rules with iptables
10. Add the following `iptables` rules to enable port forwarding
    
    ```bash
    sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
    sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
    ```
11. `sudo apt install iptables-persistent` to install iptables-persistent
12. `sudo dpkg-reconfigure iptables-persistent` to re-save and persist our `iptables` rules across reboots

#### Side Notes
- If something goes wrong, I highly recommend checking out [Tim Downey's RPi router guide](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/) as additional information is provided there
- `sudo iptables -L -n -v` to check the current `iptables` rules
- `cat /var/lib/misc/dnsmasq.leases` to check the current leases provided by dnsmasq
- `sudo service dnsmasq restart` to restart dnsmasq
- `sudo service dnsmasq stop` to stop dnsmasq (will restart on boot)

## Install Docker and Kubernetes w/Flannel CNI
The following steps will install and configure Docker and Kubernetes on all RPi's. This setup uses Flannel as the Kubernetes CNI although Weave Net may also be used as an alternative. Calico CNI may be swapped out for Flannel/Weave Net providing that an OS with an `arm64` architecture has been installed on all RPi's.

### Worker Node Setup
These steps should be performed on all RPi's within the cluster *including* the jump box/master node.

1. Install Docker
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
2. `sudo nano /boot/cmdline.txt` and add the following to the end of the line—do not make a new line and ensure that there's a space in front of `cgroup_enable=cpuset`
    ```bash
    cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
    ```
3. `sudo reboot` to reboot the RPi for boot changes to take effect (do not skip this step)
4. Install Kubernetes

##### Install the latest version of K8s
    ```bash
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
    echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
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
5. `sudo sysctl net.bridge.bridge-nf-call-iptables=1`

### Master Node Setup
The following steps should be performed only on one RPi (I used the RPi jump box). This section assumes that you're running an `armhf` architecture on your RPi's and therefore will use either [Flannel](https://github.com/coreos/flannel) or [Weave Net](https://github.com/weaveworks/weave) as your cluster's CNI.

1. `sudo kubeadm config images pull -v3` to pull down the images required for the K8s master node
2. `sudo nano /etc/resolv.conf` and ensure that it does not have `nameserver 127.0.0.1` 
    - If `nameserver 127.0.0.1` exists, remove it and replace it with another DNS IP address that isn't the loopback address, then double check that `DNSMASQ_EXCEPT=lo` has been added in `/etc/default/dnsmasq` to prevent dnsmasq from overwriting/adding `nameserver 127.0.0.1` to `/etc/resolv.conf` upon reboot
    - This step is crucial to prevent coredns pods from crashing upon running `kubeadm init`

3. Initialize the master node and save the `kubeadm join` command provided after the `kubeadm init` finishes—note that the init command will depend on the CNI of your choosing

##### Flannel
    ```bash
    sudo kubeadm init --token-ttl=0 --pod-network-cidr=10.244.0.0/16
    ```

##### Weave Net
    ```bash
    sudo kubeadm init --token-ttl=0
    ```
4. Run following commands after `kubeadm init` finishes
    ```bash
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    ```
5. `kubectl get pods -n kube-system` to double check the status of all master node pods (each should have a status of "Running")
    - If the coredns pods are failing, see the *Side Notes* for this section
6. Apply the appropriate CNI config to your cluster

##### Flannel
    ```bash
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    ```

##### Weave Net
    ```bash
    kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
    ```
7. Run the `kubeadm join` command saved in step 3, on all worker nodes, an example join command is provided below
    ```bash
    kubeadm join 192.168.29.229:6443 --token 2t9e17.m8jbybvnnheqwwjp \
        --discovery-token-ca-cert-hash sha256:4ca2fa33d228075da93f5cb3d8337931b32c8de280a664726fe6fc73fba89563
    ```
8. `kubectl get nodes` to check that all nodes were joined successfully
9. At this point, all RPi's should be set up and ready to run almost anything on top of K8s; however, if you'd like to expose services within your cluster for external access, follow the next section which will install a load balancer and ingress controller

*Optionally, you can now follow the [Kubernetes Dashboard Setup](https://github.com/zakattack9/WRaPiC#kubernetes-dashboard-setup) section to configure the Web UI for cluster monitoring*

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
- If the coredns pods are stuck in `CrashLoopBackOff` and its logs are showing the error below, the [referenced coredns docs](https://coredns.io/plugins/loop/#troubleshooting) recommends adding `resolvConf: /etc/resolv.conf` to `/etc/kubernetes/kubelet.conf`; however, the following steps resolved the issue since dnsmasq on the RPi jump box was overwriting `resolv.conf`
    ```console
    [FATAL] plugin/loop: Loop (127.0.0.1:34536 -> :53) detected for zone ".", see coredns.io/plugins/loop#troubleshooting
    ```
    ```bash
    # reset kubeadm which will undo any joined nodes
    sudo kubeadm reset
    # edit resolv.conf which coredns references on startup
    # delete "nameserver 127.0.0.1" if it exists
    # add "nameserver 1.1.1.1" or any DNS resolver
    sudo nano /etc/resolv.conf
    # initialize k8s cluster again with the correct init command from step 3
    sudo kubeadm init
    # it is important at this point to make sure that
    # DNSMASQ_EXCEPT=lo was added to the end of /etc/default/dnsmasq
    # this prevents the loopback address from being added back to resolv.conf on reboot
    ```
- If `kubectl get` is throwing the error below, run the following commands to fix the issue without needing to reboot; additionally, [this thread](https://discuss.kubernetes.io/t/the-connection-to-the-server-host-6443-was-refused-did-you-specify-the-right-host-or-port/552/28) provides some guidance to help resolve this issue—running the disable swap commands individually seemed to do the trick
    ```console
    The connection to the server <ip-address>:6443 was refused - did you specify the right host or port?
    ```
    ```bash
    sudo -i
    swapoff -a
    exit
    strace -eopenat kubectl version
    ```
- If the Flannel pods are continuously crashing and its logs are showing the error below, [this thread](https://github.com/coreos/flannel/issues/1060) helped resolve the issue by running the following commands
    ```console
    Error registering network: failed to configure interface flannel.1: failed to ensure address of interface flannel.1: link has incompatible addresses. Remove additional addresses and try again
    ```
    ```bash
    # check which node the failing flannel pod is on (check the IP)
    kubectl get pods -n kube-system -o wide
    # delete the flannel network interface (run on node found in above command)
    sudo ip link delete flannel.1
    # delete the flannel pod
    kubectl delete pod -n kube-system kube-flannel-ds-<pod-id>
    # watch the status of the pods to ensure the flannel pod is running
    kubectl get pods -n kube-system -w
    ```
- `kubectl rollout restart -n kube-system deployment/coredns` to restart coredns pods
- `kubectl logs -n kube-system pod/coredns-<pod-id>` to get the logs of a specific coredns pod
- `kubectl logs -n kube-system kube-flannel-ds-<pod-id>` to get logs of a specific Flannel pod
- `kubectl label node <node-name> node-role.kubernetes.io/<role>=<role>` to label nodes
    - `<role>` should be the same if you're setting the role for a node currently with a role set as `<none>`
- `kubectl label node <node-name> node-role.kubernetes.io/<role>-` to remove a label

## Install MetalLB and ingress-nginx
The following steps have been taken directly from [MetalLB's Installation Documentation](https://metallb.universe.tf/installation/) and the [nginx-ingres Bare-metal Installation Documentation](https://kubernetes.github.io/ingress-nginx/deploy/#bare-metal).

1) Create the `metallb-system` namespace with the following
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/namespace.yaml
```
2) Create the MetalLB deployment with the following
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/metallb.yaml
```
3) Create a `memberlist` secret containing the `secretkey` to [encrypt communication between speakers](https://metallb.universe.tf/installation/#installation-by-manifest)
```bash
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
```
4) `sudo nano metallb-config.yaml` to create a MetalLB config map with layer 2 mode configuration and paste the folllowing, where addresses is an address range of your choice—this address range should not conflict with the pod network CIDR defined during `kubeadm init`
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      # sample address range 
      - 192.168.1.240-192.168.1.250 
```
5) `kubectl apply -f metallb-config.yaml` to apply the configuration and start MetalLB
6) `kubectl get pods -n metallb-system` to ensure that all pods are running
7) Install [ingress-nginx](https://github.com/kubernetes/ingress-nginx) with the command below
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/baremetal/deploy.yaml
```
8) Edit the `ingress-nginx-controller` and change `spec.type` from `NodePort` to `LoadBalancer`
```bash
kubectl edit service ingress-nginx-controller -n ingress-nginx
```
9) `kubectl get all -n ingress-nginx` to ensure that all ingress-nginx pods are running and all jobs (create/patch) completed successfully
10) Verify that the ingress controller is working properly by doing the following
```bash
kubectl get service -n ingress-nginx
# two services should be displayed: LoadBalancer and ClusterIP
# copy the external-ip of your LoadBalancer
# the external-ip should be within the address range of assigned in metallb-config.yaml

curl http://<lb-external-ip>
# curl should return html displaying "404 Not Found"
# this indicates that the ingress-nginx-controller received the request and attempted to direct it to the correct pod
# we have confirmed that our nginx ingress controller is working
```
```html
<!-- sample response after curling the ingress-nginx LoadBalancer -->
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```
11) Add the following urls to `iptables` to forward http/https traffic from wlan0 to the LoadBalancer's external-ip
```bash
sudo iptables -t nat -I PREROUTING -i wlan0 -p tcp --dport 80 -j DNAT --to <lb-external-ip>:80
sudo iptables -t nat -I PREROUTING -i wlan0 -p tcp --dport 443 -j DNAT --to <lb-external-ip>:443
# persis the iptables rules across reboots
sudo dpkg-reconfigure iptables-persistent
```

#### Side Notes
- If the `ingress-nginx-admission-patch` fails and does not show 1/1 completions when doing `kubectl get all -n ingress-nginx` it may help to delete and reinstall `ingress-nginx` by doing the following
```bash
# remove all resources related to ingress-nginx
kubectl delete namespace ingress-nginx

# verify that no resources from the ingress-nginx namespace exists
kubectl get all -A

# follow steps 8 and 9 again to reapply and configure ingress-nginx
```

## Extra Configurations
This section includes instructions for various installations and configurations that are optional, but may be useful for your cluster needs.

### Install zsh w/Oh-my-zsh and Configure Plugins
1) `sudo apt-get install zsh` to install [Z shell (zsh)](http://zsh.sourceforge.net/)
2) `chsh -s $(which zsh)` to install default shell to zsh
3) `sudo apt-get install git wget` to install git and wget packages
  - make sure to install `git` and **not** `git-all` because git-all will replace `systemd` with `sysv` consequently stopping both Docker and K8s processes; if you did accidentally install `git-all` see *Side Notes* below
4) Install [Oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh) framework
```bash
wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh
cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
source .zshrc
```
5) Install [zsh syntax highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) plugin
```bash
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git
mv zsh-syntax-highlighting ~/.oh-my-zsh/plugins
echo "source ~/.oh-my-zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ~/.zshrc
```
6) Install [zsh auto-suggestions](https://github.com/zsh-users/zsh-autosuggestions) plugin
```bash
git clone https://github.com/zsh-users/zsh-autosuggestions
mv zsh-autosuggestions ~/.oh-my-zsh/custom/plugins
```
7) `sudo nano ~/.zshrc` and modify the plugin list to include the following
```bash
plugins=(git docker kubectl zsh-autosuggestions)
```
8) `source .zshrc` to refresh shell
9) Install [Powerlevel10k](https://github.com/romkatv/powerlevel10k) theme
```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```
10) `sudo nano ~/.zshrc` and set theme to powerlevel10k
```bash
ZSH_THEME="powerlevel10k/powerlevel10k"
```
11) `source .zshrc` and go through the p10k setup process

#### Side Notes
- If `git-all` was accidentally installed, it is more than likely that PID 1 was configured to use sysv instead of systemd; check this by running `ps -p 1`, if it shows "systemd" then you should be fine (reboot first and double check again to make sure), otherwise if "init" is displayed then follow the commands below
```bash
# checks PID 1 which should display "init" (sysv)
ps -p 1

# systemd-sysv will uninstall sysv and revert back to systemd
sudo apt-get install systemd-sysv

# reboot RPi for changes to take effect after sysv has been removed
sudo reboot

# after rebooting, double check that PID 1 is "systemd"
ps -p 1

# K8s and Docker should both be running again if PID 1 is systemd
# you do not need to repeat any K8s related setup again
```
- If some commands can no longer be found while using zsh, it likely means your `$PATH` variable got screwed up; to fix this do the following
```bash
# temporarily switch the default shell back to bash
chsh -s $(which bash)

# after typing in your password, close the terminal and log back into the RPi
# once logged back into the RPi, your terminal should be back to using bash as the default shell

# copy the output of the echo command below
echo $PATH

# update .zshrc to export the correct PATH variable on start up
nano ~/.zshrc
# uncomment and replace...
export PATH=$HOME/bin:/usr/local/bin:$PATH
# with...
export PATH=<output-from-echo-$PATH>
# exit nano

# switch the default shell back to zsh
chsh -s $(which zsh)
# close the shell and ssh back into the RPi
```
- The `docker` and `kubectl` [Oh-my-zsh plugins](https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins) adds tab completion for both commands; as a bonus, the kubectl plugin also adds [aliases](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/kubectl#aliases) for common kubectl commands such as `k` for `kubectl`
- If pasting to the terminal is slow add `DISABLE_MAGIC_FUNCTIONS="true"` to the top of `~/.zshrc` and restart zsh with `exec zsh`

### Kubernetes Dashboard Setup
This is a quick way to set up, run, and access the Kubernetes Dashboard remotely from another host outside the cluster network such as the computer used to ssh into the RPi cluster. These steps have been adapted from the official [Kubernetes Dashabord documentation](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/) and Oracle's [Access the Kubernetes Dashboard](https://docs.oracle.com/en/operating-systems/olcne/orchestration/dashboard.html#dashboard-start) guide.

1) Deploy the K8s dashboard from the master node with the following command
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml
```
2) `kubectl proxy` to start the proxy forwarding traffic to the internal pod where the dashboard is running
3) Use the command below to get the Bearer token needed to log in to the dashboard; alternatively, a sample user with a corresponding Bearer token can be created by following [this guide](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md)
```bash
kubectl -n kube-system describe $(kubectl -n kube-system \
get secret -n kube-system -o name | grep namespace) | grep token:
``` 
4) Run the following command from the remote device where the dashboard will be accessed; replace `<username>` with username of the master node (the default is `pi`) and `ip-address` with the ip address of the master node's ip (may use `ifconfig wlan0` if the master node is the jump box)
```bash
ssh -L 8001:127.0.0.1:8001 <username>@<ip-address>
```
5) Navigate to the following address on the remote device to access the dashboard UI
```
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/ 
```
6) Select the "Token" login option, paste the value of the token received in step 3, and click "Sign in"

### Install Calico CNI
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

### Install Prometheus and Grafana
This section deploys Prometheus and Grafana to your cluster and exposes them externally through an [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/). While there are many ways to deploy Prometheus and Grafana to K8s the [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) project makes this significantly easier without needing Helm or writing any yamls; unfortunately, kube-prometheus does not currently use Docker images that have support for armhf and will therefore fail to properly deploy on an armhf RPi cluster. Fortunately, Carlos Eduardo's [cluster-monitoring](https://github.com/carlosedp/cluster-monitoring) project has ported the kube-prometheus project to armhf which is what will be used in the following steps to deploy Prometheus and Grafana.

1) `git clone https://github.com/carlosedp/cluster-monitoring && cd cluster-monitoring`
2) `sudo apt-get update -y && sudo apt-get install -y golang` to install go which is needed for some of the make commands
  - `sudo apt-get install -y build-essential` if make is not installed
3) `ifconfig wlan0` **on the RPi jump box** to get the cluster's external ip address (used in the next step)
4) Configure the yaml files that will deploy Prometheus and Grafana to your cluster; follow the appropriate section if you'd like to record and display temperature metrics 
##### With Temperature Metrics
```bash
# edit vars.jsonnet to enable temp metrics and configure the ingress ip address
nano vars.jsonnet
# set "enabled" to true for "armExporter" under "modules"
# set "suffixDomain" to the ip address found in step 3 and append ".nip.io" to the end of it
# e.g. 192.168.0.1 => 192.168.0.1.nip.io
make vendor
make
make deploy
```
##### Without Temperature Metrics
```bash
# replace <ip-address> with the ip address found in step 3
make change_suffix suffix=<ip-address>.nip.io
make deploy
``` 
  - If an error occurs will applying the manifests rerun `make deploy` or `kubectl apply -f manifests/`
5) If you haven't already, add the following urls to `iptables` to forward http and https traffic from wlan0 to the LoadBalancer's external-ip which can be found by running `kubectl get ingress -n ingress-nginx`
```bash
sudo iptables -t nat -I PREROUTING -i wlan0 -p tcp --dport 80 -j DNAT --to <lb-external-ip>:80
sudo iptables -t nat -I PREROUTING -i wlan0 -p tcp --dport 443 -j DNAT --to <lb-external-ip>:443
sudo dpkg-reconfigure iptables-persistent
```
6) `kubectl get ingress -n monitoring` to get the external URLs (the ".nip.io" addresses) to access Prometheus, Alertmanager, and Grafana from outside the cluster
7) `kubectl get pods -n monitoring` to ensure that all pods are running properly
8) Check out Jeff Geerling's [RPi Cluster Episode 4](https://youtu.be/IafVCHkJbtI) video as he walks through a very similar setup proccess on camera and shows how to configure the custom Grafana dashboard that comes with the cluster-monitoring project (around [17:19](https://youtu.be/IafVCHkJbtI?t=1039) minute mark)

#### Side Notes
- If the prometheus-adapter pod is constantly crashing and throwing the error below, it may help to delete the entire monitoring namespace that was created by the cluster-monitoring project and redeploy kube-prometheus again with `make deploy`; I'd also reccomend deleting all the kube-proxy pods in the `kube-system` namespace to manually restart them before redploying kube-prometheus again
```console
communicating with server failed: Get \"https://10.96.0.1:443/version?timeout=32s\": dial tcp 10.96.0.1:443: i/o timeout
```
- If the kube-state-metrics pod is constantly crashing, I found that deleting the kube-flannel-ds pod on the same node seemed to resolve the issue; `sudo ip link delete flannel.1` should be run first before deleting the flannel pod off the same node

### Install EFK Stack (Elasticsearch, Fluent Bit, Kibana)
This section deploys Fluent Bit to the RPi K8s cluster and installs Elasticsearch and Kibana on a reachable host *outside* the cluster. Unfortunately, the ELK stack currently has Docker images that supports only `arm64` and `amd64` architectures (theoretically, the full ELK stack could be run on an RPi K8s cluster providing that each node runs on an arm64 architecture); while custom `armhf` Docker images could be built for the ELK stack, it's a lot easier to just run ELK on another host outside the cluster network that has a 64 bit architecture. One major benefit to running both Elasticsearch and Kibana outside of the cluster is that it will not add extra CPU/memory load to the cluster—this is especially important if you have plans to run other resource intensive services.

Fluent Bit was choosen over Fluentd because it was a more lightweight solution over Fluentd that required less resources to run optimally within the cluster; it is important to note that while Fluentd has Docker images that support `armhf`, the [Fluentd Kubernetes DaemonSet](https://hub.docker.com/r/fluent/fluentd-kubernetes-daemonset) images [needed](https://docs.fluentd.org/v/0.12/articles/kubernetes-fluentd) for Fluentd to push logs to Elasticsearch does not have `armhf` support. Richard Youngkin talks about this in his guide, [K8s Application Monitoring on a RPi Cluster](https://medium.com/better-programming/kubernetes-application-monitoring-on-a-raspberry-pi-cluster-fa8f2762b00c) and has already created a Docker image that can be used to run Fluentd on `armhf` with Elasticsearch. The following steps have been adapted from [Fluent Bit's Kubernetes Guide](https://fluentbit.io/documentation/0.14/installation/kubernetes.html) and installation documentation on MacOS with `brew` for [Elasticsearch](https://www.elastic.co/guide/en/elasticsearch/reference/7.10/brew.html) and [Kibana](https://www.elastic.co/guide/en/kibana/current/brew.html).

1) On an external host *outside* the cluster that is on the same LAN as the RPi jump box (e.g. the laptop used to ssh into the cluster), execute the following commands to install Elasticsearch and Kibana (for MacOS only); for Linux and Windows, follow [Installing Elasticsearch](https://www.elastic.co/guide/en/elasticsearch/reference/current/install-elasticsearch.html) and [Installing Kibana](https://www.elastic.co/guide/en/kibana/current/install.html) to download both packages as a zip
```bash
# MacOS only
# add the elastic repository to brew
brew tap elastic/tap
# install elasticsearch
brew install elastic/tap/elasticsearch-full
# install kibana
brew install elastic/tap/kibana-full
```
2) Get the ip address of the external host which Elasticsearch and Kibana will be run on (use `ifconfig`); this is important so that we can bind `localhost` to an actual ip address which Fluent Bit can access from within the cluster in later steps
3) Execute the `configure.sh` script (pass in the ip address found in the previous step) located in this repository to configure Elasticsearch and Kibana if they were installed via `brew` for MacOS; for Linux and Windows navigate to the `config/` folder in the unzipped Elasticsearch and Kibana packages to make the following changes
##### Using configure.sh
```bash
# use this script if Elasticsearch and Kibana were installed via brew
./configure.sh <ip-address>
# for Linux/Windows, use the manual method below
```
##### Elasticsearch
```bash
# in config/elasticsearch.yml, add the following under the "Network" section
# replace <ip-address> with the ip found in step 2
network.bind_host: <ip-address>
http.port: 9200

transport.host: localhost
transport.tcp.port: 9300
```
##### Kibana
```bash
# in config/kibana.yml, uncomment and modify the following 
# replace <ip-address> with the ip found in step 2
elasticsearch.hosts: ["http://<ip-address>:9200"]
```
4) In two separate terminal windows run `elasticsearch` and `kibana` using the following commands
```bash
# for MacOS (installed by brew)
# in first window run
elasticsearch
# in second window run
kibana

# for Linux
# navigate to the unzipped elasticsearch package
# in first window run
./bin/elasticsearch
# navigate to the unzipped kibana package
# in second window run
./bin/kibana

# for Windows
# naviate to the unzipped elasticsearch package
# in first window run
.\bin\elasticsearch.bat
# naviate to the unzipped kibana package
# in second window run
.\bin\kibana.bat
```
5) `curl http://<ip-address>:9200` where `<ip-address>` is the ip found in step 2, to check if Elasticsearch is running properly
6) Navigate to `<ip-address>:5601/status` to check if Kibana is running properly
7) Run the following commands to create a `logging` namespace and configure the cluster for Fluent Bit
```bash
kubectl create namespace logging
kubectl apply -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-service-account.yaml
kubectl apply -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role.yaml
kubectl apply -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role-binding.yaml
kubectl apply -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/output/elasticsearch/fluent-bit-configmap.yaml
```
8) Configure the Fluent Bit DaemonSet then apply it to all nodes within the cluster
```bash
# retrieve the Fluent Bit DaemonSet yaml and save it to a file
curl https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/output/elasticsearch/fluent-bit-ds.yaml -o fluent-bit-ds.yaml
# edit the Fluent Bit DaemonSet yaml and make the following changes as described above
nano fluent-bit-ds.yaml
# apply the edited DaemonSet to the cluster
kubectl apply -f fluent-bit-ds.yaml
```
9) `kubectl get pods -n logging` to ensure that all Fluent Bit pods are running properly and are forwarding logs to Elasticsearch
10) You should now start to see logs in Kibana after an index is created under the "Discover" page

#### Side Notes
- `brew services start elastic/tap/elasticsearch-full` to run Elasticsearch as a service on boot (MacOS only)
- `brew services start elastic/tap/kibana-full` to run Kibana as a service on boot (MacOS only)

## References
- [Disabling Swap](https://www.raspberrypi.org/forums/viewtopic.php?p=1488821)
- [Alex Ellis' K8s On Raspian Repo](https://github.com/teamserverless/k8s-on-raspbian)
- [Tim Downey's RPi Router Guide](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/)
- [Richard Youngkin's RPi K8s Cluster Guide](https://medium.com/better-programming/how-to-set-up-a-raspberry-pi-cluster-ff484a1c6be9)
- [Sean Duffy's RPi K8s Cluster Guide](https://www.shogan.co.uk/kubernetes/building-a-raspberry-pi-kubernetes-cluster-part-1-routing/)
- [Install zsh On Linux](https://linoxide.com/tools/install-zsh-on-linux/)
- [Remote Kubernetes Dashboard](https://docs.oracle.com/en/operating-systems/olcne/orchestration/dashboard.html#dashboard-remote)
- [How To Expose Your Services With Kubernetes](https://medium.com/better-programming/how-to-expose-your-services-with-kubernetes-ingress-7f34eb6c9b5a)
- [Carlos Eduardo's Cluster Monitoring Repo](https://github.com/carlosedp/cluster-monitoring) 
- [Jeff Geerling's RPi Cluster Episode 4](https://www.youtube.com/watch?v=IafVCHkJbtI)

## TODO
- need to fix headless RPi setup section such that only the master node/jump box has a wpa_supplicant created for it; all other nodes should be accessed via sshing into the master node first and then into the respective worker node
- simplify steps for fixing PATH var
- review if any steps can be simplified by using another package (e.g. sed, awk, etc.)
- ~add Weave Net instructions to docs~
- add iTerm2 profile config instructions
- set up ansible playbooks:
	- RPi router configuration
	- RPi disable swap and SSH key setup
	- RPi kubernetes setup
- disable SSH password access (keys only)
- set up a reverse SSH tunnel to allow for direct SSH into worker nodes in the internal cluster network from MBP without needing to SSH from the Pi router
- add check to configure script to see if the configuration has been already to either the elasticsearch or kibana config files; if the config has already been added, simply modify the ip currently in the file