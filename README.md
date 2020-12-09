# WRaPiC Documentation
#code/projects/wrapic #code/raspberrypi

## Initial RPi Setup (w/SSH and WiFi)
- install Raspberry Pi OS Lite (32-bit) w/Raspberry Pi Imager 
- create `ssh` file in root directory of micro sd card
- use `wpa_supplicant.conf` to [set up WiFi connection](https://www.raspberrypi.org/documentation/configuration/wireless/headless.md)

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
- disable swap with the command:
`sudo dphys-swapfile swapoff && sudo dphys-swapfile uninstall && sudo systemctl disable dphys-swapfile`
- `sudo nano /etc/dphys-swapfile` and set `CONF_SWAPSIZE=0`

#### Side Notes:
- may need to comment out `SendEnv LANG LC_*` in `/etc/ssh/ssh_config` on host SSH client (Mac) to fix RPi locale problem
- check if swap is disabled with `free -h` look for “Swap:”
- should backup SSH keys

## Setting up RPi Router
- [followed this guide to router configuration](https://downey.io/blog/create-raspberry-pi-3-router-dhcp-server/)
- [referenced this guide for other setup tips](https://medium.com/better-programming/how-to-set-up-a-raspberry-pi-cluster-ff484a1c6be9)
- set up wrapic0 (router) in `/etc/dhcpcd.conf`
- install `dnsmasq` with `sudo apt install dnsmasq` 
- back up existing `/etc/dnsmasq.conf`
- modify `/etc/dnsmasq.conf`
- disable swap on SD card
```
sudo dphys-swapfile swapoff && sudo dphys-swapfile uninstall && sudo update-rc.d dphys-swapfile remove
```

- use `sudo dpkg-reconfigure iptables-persistent` to re-save iptables and persist them 
- disable SSH password access (keys only)

#### Side Notes:
- can disable dnsmasq by editing `/etc/default/dnsmasq` and changing `ENABLED=1` to `ENABLED=0` (doesn’t work)
- check iptables rules with `sudo iptables -L -n -v`
- check dnsmasq status with `sudo service dnsmasq status`
- stop dnsmasq with `sudo service dnsmasq stop` (will restart on boot)
- `ifconfig eth0` can be used to find each RPi’s MAC address (look next to “ether”)

## Configure iTerm Window Arrangement and Profiles
- `ssh pi@routerPi.local`
- `ssh -t pi@routerPi.local 'ssh pi@masterNodePi.local'`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode1Pi.local'`
- `ssh -t pi@routerPi.local 'ssh pi@workerNode2Pi.local'`

## TODO
- setup ansible playbooks:
	- RPi router configuration
	- RPi disable swap and SSH key setup
	- RPi k8s setup
