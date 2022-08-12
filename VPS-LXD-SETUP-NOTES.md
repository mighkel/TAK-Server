These are just some notes I'm taking along the way as I learn more about networking and installing TAK Servers.  
Specifically, this doc outlines setting up a VPS with LXC/LXD containers with HAProxy for reverse proxy routing.  
**To skip all of my yammering, head on down to Section 01**  
  
Purpose of publishing this here:
* Keep notes for myself so I can refer back as needed
* Help others with a similar lack of skills as my own to shorten their learning curves
* Provide a way for those more experienced and willing to help others to pick apart and help refine or expand this process as needed
  
If you're anything like me, you have the interest and some very basic linux, webdev, and networking experience; and your interest in the TAK ecosystem has sparked an urgency to accellerate taking that learning to the next level.  
  
In my case, I'm an officer on a small rural (read: non-taxing, *very* low budget) fire department, with a full-time job outside of public safety, who wants to learn the TAK ecosystem, and be able to set it up and teach it to other public safety orgs around our county.  

Is there an easier way to get a TAK Server going on a VPS?  
You bet!  
Get a Digital Ocean account and you can spin up and tear-down (destroy) server instances (droplets) to your hearts content.  
It's a fairly cheap and easy way to learn without having to be afraid of breaking something that is difficult or impossible to fix.  
If you're actually reading this, you've probably already been down that path, and now you want to make better use of your funding and increase your flexibilty.  
I found that purchasing a three-year term of VPS on SSD Nodes got me a lot more machine for a lot less money if you account for the monthly cost.  
I hate their 'urgency marketing', but they do have a lot of sales that make their already inexpensive VPS plans much cheaper.  Hold out for the 40% + sales.  They come around often.  
I do have a referral code.  Feel free to use it, or don't.  Thanks if you do!  https://www.ssdnodes.com/manage/aff.php?aff=1554  
Oh yeah, I'm just a customer.  No more, no less.  
  
  
Ok, with that crap out of the way, let's get to the good stuff...  
  

**01 PURCHASE VPS**  
++++++++++++++++++++
  
I went with SSD Nodes, *G6 Performance+ 64GB RAM [B92]*  
Server type:  Virtual Machine  
Platform:  Ubuntu20.04  
vCPUs:  12  
Memory:  64 GB  
Disk:  1200 GB  
  
This is seriously overkill for a TAK Server that doesn't serve thousands of heavy users.  
I just have plans for running apps that will consume a bit more.  If you're curious, a couple of those apps are Nextcloud and OpenDroneMap (WebODM).   
  
**02 MANAGE DNS (OPTIONAL)**  
++++++++++++++++++++  
  
Create DNS records for any subdomains that need routing.  
SSD Nodes Dashboard  
     Domains  
          Manage DNS  
Find your domain and edit it.  
Add Record  
  
Fill out the form for your subdomain to create a new A record (or multiple).  
  
Name:	[SUB.MYDOMAIN.COM]  
Type:	A  
TTL:	14400 (default)  
RDATA:	[MY PUBLIC IP ADDRESS] (of the host)  
  
  
**03 BASICS**  
++++++++++++++++++++  
  
Update the distro and packages.  
  
$ `apt update && apt upgrade -y`  
  
$ `apt autoremove`  
  
  
**04 SECURITY/SSH**  
++++++++++++++++++++  
  
Create a new user with root privileges.  
Make sure that the new user can log in over SSH using a public-private key pair.  
  
$ `adduser [USER]`  
$ `usermod -aG sudo [USER]`  
  
Test new user  
  
$ `login [USER]`  
  
$ `sudo apt update`  
  
  
**05 OPTIONAL RUN SUDO WITHOUT PASSWORD EVERY TIME**  
++++++++++++++++++++  
  
$ `visudo`  
  
Add the following to the end:  
  
`[USER] ALL=(ALL) NOPASSWD:ALL`  
  
  
**06 ADD SSH KEYS**  
++++++++++++++++++++  
  
(https://blog.ssdnodes.com/blog/connecting-vps-ssh-security/)  
  
Add public SSH key by editing:  
  
$ `~/.ssh/authorized_keys`  
  
  
**07 DISABLE ROOT LOGIN**  
++++++++++++++++++++  
  
Only after confirming your new user can login via SSH and perform sudo actions.  
  
Edit:  `/etc/ssh/sshd_config`  
  
```
PermitRootLogin no  
PasswordAuthentication no  
PermitEmptyPasswords no  
```
  
  
**08 ENABLE FIREWALL**  
++++++++++++++++++++  
  
$ `sudo ufw allow ssh`  
$ `sudo ufw allow http https`  
$ `sudo ufw allow 8089`  
$ `sudo ufw allow 8443`  
$ `sudo ufw enable`  
  
* add port for rtsp when determined  
  
  
**09 INSTALL/INIT LXC/LXD**  
++++++++++++++++++++  
  
https://blog.ssdnodes.com/blog/linux-containers-lxc-haproxy/  
  
$ `sudo install zfsutils-linux`  
$ `sudo lxd init`  
  
**10 ADD USER TO LXD GROUP**  
++++++++++++++++++++  
  
$ `usermod -aG lxd [USER]`  
  
  
**11 CREATE CONTAINERS**  
++++++++++++++++++++  
  
$ `lxc launch images:ubuntu/20.04 [HAProxy]`  
$ `lxc launch images:ubuntu/20.04 [web]`  
$ `lxc launch images:centos/7 [tak]`  
  
  
**12 GET IP ADDRESSES FOR ROUTING**  
++++++++++++++++++++  
  
$ `ifconfig`  
  
$ `lxc list`  
  
Example:
```  
+---------+---------+------------------------------+------+-----------+-----------+  
|  NAME   |  STATE  |             IPV4             | IPV6 |   TYPE    | SNAPSHOTS |  
+---------+---------+------------------------------+------+-----------+-----------+  
| HAProxy | RUNNING | 10.13.240.200 (eth0)         |      | CONTAINER | 1         |  
+---------+---------+------------------------------+------+-----------+-----------+  
| tak     | RUNNING | 10.13.240.149 (eth0)         |      | CONTAINER | 1         |  
+---------+---------+------------------------------+------+-----------+-----------+  
| web     | RUNNING | 10.13.240.56 (eth0)          |      | CONTAINER | 1         |  
+---------+---------+------------------------------+------+-----------+-----------+  
```  
  
**13 SETUP ROUTING**  
++++++++++++++++++++  
  
Forward traffic to the HAProxy container.   
  
$ `sudo iptables -t nat -I PREROUTING -i enp3s0 -p TCP -d [MY-PUBLIC-IP]/32 --dport 80 -j DNAT --to-destination 10.13.240.200:80`  
  
$ `sudo iptables -t nat -I PREROUTING -i enp3s0 -p TCP -d [MY-PUBLIC-IP]/32 --dport 443 -j DNAT --to-destination 10.13.240.200:443`  
  
$ `sudo iptables -t nat -I PREROUTING -i enp3s0 -p TCP -d [MY-PUBLIC-IP]/32 --dport 8089 -j DNAT --to-destination 10.13.240.200:8089`  
  
$ `sudo iptables -t nat -I PREROUTING -i enp3s0 -p TCP -d [MY-PUBLIC-IP]/32 --dport 8443 -j DNAT --to-destination 10.13.240.200:8443`  
  
$ `sudo apt-get install iptables-persistent`  
  
  
**14 CONFIGURE HAPROXY CONTAINER**   
++++++++++++++++++++  
  
Login to container  
  
$ `lxc exec HAProxy -- bash`  
  
(Ctrl+D or Cmd+D to exit)  
  
$ `apt update && apt upgrade -y`  
  
$ `apt install haproxy`  
  
$ `sudo nano /etc/haproxy/haproxy.cfg`  
  
  
  
 **More to come soon, including sample HAProxy config.  I just need to sanitize my working copy.
  
**15 INSTALL WEB SERVER ON WEB CONTAINER**   
++++++++++++++++++++    
  
**16 INSTALL TAK SERVER ON TAK CONTAINER**   
++++++++++++++++++++    
  
**17 ADD TAK CERTS TO HAPROXY**   
++++++++++++++++++++    
  
