VPS Setup Notes

++++++++++++++++++++
PURCHASE VPS

Locate and remember your public IP address.
Can generally get it from your VPS dashboard.

++++++++++++++++++++
BASICS

Update the distro and packages.

$ apt update && apt upgrade -y

$ apt autoremove

++++++++++++++++++++
SECURITY
Create a new user with root privileges.
Make sure that the new user can log in over SSH using a public-private key pair.
Make sure that root user can’t login over SSH.
Block unnecessary ports.

$ adduser USER
$ usermod -aG sudo USER

Test new user

$ login USER

$ sudo apt update

++++++++++++++++++++
OPTIONAL RUN SUDO WITHOUT PASSWORD EVERY TIME

$ visudo

Add the following to the end:

USER ALL=(ALL) NOPASSWD:ALL

++++++++++++++++++++
ADD SSH KEYS

(https://blog.ssdnodes.com/blog/connecting-vps-ssh-security/)

Add public SSH key by editing:

~/.ssh/authorized_keys

++++++++++++++++++++
DISABLE ROOT LOGIN

Only after confirming your new user can login via SSH and perform sudo actions.

Edit:  /etc/ssh/sshd_config

PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no

++++++++++++++++++++
ENABLE FIREWALL

$ sudo ufw allow ssh
$ sudo ufw allow http https
$ sudo ufw allow 8089 8443
$ sudo ufw enable

* add port for rtsp

++++++++++++++++++++
INSTALL ESSENTIALS

Docker
Git
LXC
