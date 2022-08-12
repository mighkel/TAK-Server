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
  
Side Note:  I have a couple of cheat sheets with groups of commands.  One of them is LXC commands.  
One important command, and one of the main reasons that containers are so awesome, is:  
  
$ `lxc snapshot [container] [snapshot name]`  
  
Use snapshot often, at least at every successful install step or configuration change, on every container.  

  
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
  
Here's a sanitized version of my configuration file, the way it sits now.  
It may be wonky, but it actually is working.
  
```
#frontends

#http in, This is for the web (Apache) server on the "web" container.  It has been working. Yay!

frontend http-in
        mode http
        bind 0.0.0.0:80
        bind 0.0.0.0:8000
        bind 0.0.0.0:8080
        bind 0.0.0.0:8087

        acl DOMAIN-TLD-acl hdr(host) -i DOMAIN.TLD
        acl DOMAIN-TLD-acl hdr(host) -i web.DOMAIN.TLD
        acl tak-DOMAIN-TLD-acl hdr(host) -i tak.DOMAIN.TLD

        use_backend DOMAIN-server-1 if DOMAIN-TLD-acl
        use_backend DOMAIN-server-2 if tak-DOMAIN-TLD-acl

        default_backend DOMAIN-server-1
        
#https in, Also for the web server.  I have not generated or plugged-in any certs yet.  Not really my priority rn.  This is just here for later.

frontend https-in
        mode tcp
        bind 0.0.0.0:443
        tcp-request inspect-delay 5s
        tcp-request content accept if { req.ssl_hello_type 1 }

        acl DOMAIN-TLD-ssl-acl req.ssl_sni -i DOMAIN.TLD
        acl DOMAIN-TLD-ssl-acl req.ssl_sni -i web.DOMAIN.TLD

        use_backend DOMAIN-ssl-server-1 if DOMAIN-TLD-ssl-acl

        default_backend DOMAIN-ssl-server-1

#Here's the whole point of this exercise.  Connect to the tak server via TLS/SSL.  Subdomain is setup as tak.DOMAIN.TLD

frontend tak-server
        mode tcp
        bind 0.0.0.0:8443
        tcp-request inspect-delay 5s
        tcp-request content accept if { req.ssl_hello_type 1 }

        acl tak-DOMAIN-TLD-ssl-acl req.ssl_sni -i tak.DOMAIN.TLD

        use_backend tak-DOMAIN-TLD-ssl-server-1 if tak-DOMAIN-TLD-ssl-acl

        default_backend tak-DOMAIN-TLD-ssl-server-1
        
frontend tak-client
        mode tcp
        bind 0.0.0.0:8089
        tcp-request inspect-delay 5s
        tcp-request content accept if { req.ssl_hello_type 1 }

        acl tak-DOMAIN-TLD-ssl-acl req.ssl_sni -i tak.DOMAIN.TLD

        use_backend takc-DOMAIN-TLD-ssl-server-1 if tak-DOMAIN-TLD-ssl-acl

        default_backend takc-DOMAIN-TLD-ssl-server-1

# Backends
backend DOMAIN-server-1
        mode http
        server web-DOMAIN-TLD 10.13.240.56:80

backend DOMAIN-server-2
        mode http
        server tak-DOMAIN-TLD 10.13.240.149:8080

backend DOMAIN-ssl-server-1
        mode tcp
        option ssl-hello-chk
        server web-DOMAIN-TLD 10.13.240.56:443

backend tak-DOMAIN-TLD-ssl-server-1
        mode tcp
        option ssl-hello-chk
        server tak-DOMAIN-TLD 10.13.240.149:8443

backend takc-DOMAIN-TLD-ssl-server-1
        mode tcp
        option ssl-hello-chk
        server takc-DOMAIN-TLD 10.13.240.149:8089
```    
  
**15 INSTALL WEB SERVER ON WEB CONTAINER**   
++++++++++++++++++++  
  
I went with LAMP (Apache) stack on my web server.  More info to come.  
  
**16 INSTALL TAK SERVER ON TAK CONTAINER**   
++++++++++++++++++++    
  
I might just link to another doc here.  We'll see.  It's well-covered elswhere, and I don't recall anything unique to containers tha isn't already covered above, but I'm sure there is, especially when getting into certs.
  
**17 ADD TAK CERTS TO HAPROXY**   
++++++++++++++++++++    
  
I haven't had to so far, but I'm only using the self-signed certs, and they're working.  I'll leave this here for when I go down the LetsEncrypt path.  
That's just something I haven't dug into yet.
