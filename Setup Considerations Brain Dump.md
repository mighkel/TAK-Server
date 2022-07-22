These are just notes for now.  As I started writing, I got too far into the weeds right off, so this is becoming the brain-dump.

Split this into multiple docs.

"So, you want to run a TAK Server?"

Use case.

  Personal?
  
  Public safety?
  
  Non-profits?
  
Budget.

Experience.

Pain tolerance.



Doing away with the question of on-metal vs VPS.  Just going to cover VPS here.

VPS setup notes based on SSD Nodes instance, but it should work on other providers with minor mods.

I'm no Linux guru, and nor am I a virtual private servers (VPS) guru by any means.  I have setup and torn-down many FreeTAK Servers and a few TAK Servers on Digital Ocean droplets, so I have some experience - many fails and some successes.  It is now time to take it to the next level.  Containers!

Why containers?
Why not?  It's EASY!  Yeah, right, well... let's see about that as I try this and document it the whole way.
Really though, containers allow you to start from a particular operating system, and run apps or services that may or may not be optimal for running on that particular OS.  At least that's why I'm going for it.  I want to run TAK Server, rtsp server, and some kind of cloud services like Nextcloud. 


First, let's flesh out the order of operations.

Access to TAK Server software on tak.gov

Purchase a VPS

Setup VPS

  Choose OS
  
  Secure it
  
  Setup SSH
  
  Setup firewall
  
  Setup containers (LXC/LXD)
  
  Container routing (HAProxy)
  
Install TAK Server

Connect users

Administer TAK Server



So.... I got questions!


Where in this order do certs go?











BASIC CHOICES

Choose a provider.  I'm going with SSD Nodes, based on a recommendation in the TAK community.

Choose a plan.      I went with a deal on a G6 Performance+ Plan 64GB RAM 1200GB NVMe.

Choose your OS.     Ubuntu Server 20.04 LTS



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
