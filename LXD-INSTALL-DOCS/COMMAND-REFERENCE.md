# TAK Server Quick Install - Command Reference
### Copy/paste commands only. No explanations. For experienced users.
---
## Prerequisites
  - Ubuntu 22.04 VPS
  - DNS: tak.pinenut.tech, web.pinenut.tech, rtsptak.pinenut.tech → VPS IP
  - TAK files downloaded from tak.gov

---

## 5.1 Host Provisioning
```# Update and install tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip snapd ufw fail2ban
sudo snap install lxd

# Add user to lxd group (optional)
sudo usermod -aG lxd $USER
newgrp lxd

# Initialize LXD
sudo lxd init --auto

# Create admin user
sudo adduser takadmin
sudo usermod -aG sudo takadmin
sudo mkdir -p /home/takadmin/.ssh
sudo chmod 700 /home/takadmin/.ssh
sudo chown takadmin:takadmin /home/takadmin/.ssh

# Add SSH key (paste your public key, then Ctrl+O, Ctrl+X)
sudo nano /home/takadmin/.ssh/authorized_keys
sudo chmod 600 /home/takadmin/.ssh/authorized_keys
sudo chown takadmin:takadmin /home/takadmin/.ssh/authorized_keys

# Disable root SSH
sudo sed -i "s/^#*PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo systemctl reload sshd

# Configure firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw allow 8089/tcp
sudo ufw allow 8443/tcp
sudo ufw allow 8554/tcp
echo "y" | sudo ufw enable

# Enable fail2ban
sudo systemctl enable --now fail2ban
```

---

## 5.2 LXD Init

```# Already done in 5.1
# If needed separately:
sudo snap install lxd
sudo lxd init --auto
```

---

## 5.3 Create Containers

```lxc launch ubuntu:22.04 haproxy
lxc launch ubuntu:22.04 tak
lxc launch ubuntu:22.04 web
lxc launch ubuntu:22.04 rtsptak

# Check IPs (likely only IPv6 at this point)
lxc list
```
---

## 5.3b Fix Container Networking

```# Assign static IPs
lxc exec haproxy -- ip addr add 10.206.248.10/24 dev eth0
lxc exec haproxy -- ip route add default via 10.206.248.1

lxc exec tak -- ip addr add 10.206.248.11/24 dev eth0
lxc exec tak -- ip route add default via 10.206.248.1

lxc exec web -- ip addr add 10.206.248.12/24 dev eth0
lxc exec web -- ip route add default via 10.206.248.1

lxc exec rtsptak -- ip addr add 10.206.248.13/24 dev eth0
lxc exec rtsptak -- ip route add default via 10.206.248.1

# Add DNS servers
for container in haproxy tak web rtsptak; do
  lxc exec $container -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
  lxc exec $container -- bash -c "echo 'nameserver 8.8.4.4' >> /etc/resolv.conf"
done

# Fix host firewall
sudo iptables -I FORWARD -i lxdbr0 -p udp --dport 53 -j ACCEPT
sudo iptables -I FORWARD -i lxdbr0 -p tcp --dport 53 -j ACCEPT
sudo iptables -I FORWARD -i lxdbr0 -j ACCEPT
sudo iptables -I FORWARD -o lxdbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo apt install -y iptables-persistent
sudo netfilter-persistent save

# Make IPs permanent with netplan
lxc exec haproxy -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.206.248.10/24]
      routes:
        - to: default
          via: 10.206.248.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

lxc exec tak -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.206.248.11/24]
      routes:
        - to: default
          via: 10.206.248.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

lxc exec web -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.206.248.12/24]
      routes:
        - to: default
          via: 10.206.248.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

lxc exec rtsptak -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.206.248.13/24]
      routes:
        - to: default
          via: 10.206.248.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# Apply netplan and fix permissions
for container in haproxy tak web rtsptak; do
  lxc exec $container -- chmod 600 /etc/netplan/10-lxc.yaml
  lxc exec $container -- netplan apply
done

# Verify
lxc list
```

---

## 5.4 Prepare Containers

```# Update and install basics (all containers)
for container in haproxy tak web rtsptak; do
  lxc exec $container -- apt update
  lxc exec $container -- apt install -y vim curl wget unzip ufw
done
```

---

## 5.5 HAProxy Install & Config

```# Install HAProxy
lxc exec haproxy -- apt install -y haproxy certbot

# Create HAProxy config on host
cat > ~/haproxy.cfg <<'EOF'
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  dontlognull
    timeout connect 5s
    timeout client  1m
    timeout server  1m

frontend http-in
    bind *:80
    mode http
    acl is_acme_challenge path_beg /.well-known/acme-challenge/
    use_backend tak-acme-backend if is_acme_challenge
    acl host_web hdr(host) -i web.pinenut.tech
    use_backend web-backend if host_web
    default_backend web-backend

backend tak-acme-backend
    mode http
    server tak 10.206.248.11:80

backend web-backend
    mode http
    server web1 10.206.248.12:80

frontend tak-client
    bind *:8089
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    acl host_tak req.ssl_sni -i tak.pinenut.tech
    use_backend tak-client-backend if host_tak

backend tak-client-backend
    mode tcp
    option ssl-hello-chk
    server tak 10.206.248.11:8089

frontend tak-server
    bind *:8443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    acl host_takreq req.ssl_sni -i tak.pinenut.tech
    use_backend tak-server-backend if host_takreq

backend tak-server-backend
    mode tcp
    option ssl-hello-chk
    server takweb 10.206.248.11:8443

frontend rtsp-in
    bind *:8554
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    default_backend rtsptak-backend

backend rtsptak-backend
    mode tcp
    server rtsptak 10.206.248.13:8554 check

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy_stats
    stats auth admin:YourStrongPassword
EOF

# Push config and restart
sudo lxc file push ~/haproxy.cfg haproxy/etc/haproxy/haproxy.cfg
lxc exec haproxy -- systemctl restart haproxy
lxc exec haproxy -- systemctl enable haproxy
```

---

## 5.5b Port Forwarding

```# Forward ports from host to haproxy container
lxc config device add haproxy http proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80
lxc config device add haproxy https proxy listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443
lxc config device add haproxy tak8089 proxy listen=tcp:0.0.0.0:8089 connect=tcp:127.0.0.1:8089
lxc config device add haproxy tak8443 proxy listen=tcp:0.0.0.0:8443 connect=tcp:127.0.0.1:8443
lxc config device add haproxy rtsp8554 proxy listen=tcp:0.0.0.0:8554 connect=tcp:127.0.0.1:8554
lxc config device add haproxy stats proxy listen=tcp:0.0.0.0:8404 connect=tcp:127.0.0.1:8404

# Verify
sudo ss -tulpn | grep -E ':(80|443|8089|8443|8554|8404)'
```

---

## 5.7 Install TAK Server

```# On Windows: Download from tak.gov and your GitHub fork
# Upload via WinSCP to /home/takadmin/:
#   - installTAK (from your fork)
#   - takserver_5.5-RELEASE58_all.deb
#   - takserver-public-gpg.key
#   - deb_policy.pol

# Push files to tak container
sudo lxc file push /home/takadmin/installTAK tak/root/
sudo lxc file push /home/takadmin/takserver_5.5-RELEASE58_all.deb tak/root/
sudo lxc file push /home/takadmin/takserver-public-gpg.key tak/root/
sudo lxc file push /home/takadmin/deb_policy.pol tak/root/

# Make executable
sudo lxc exec tak -- chmod +x /root/installTAK

# Enter container and run installer
sudo lxc exec tak -- bash
cd /root
./installTAK takserver_5.5-RELEASE58_all.deb false true

# Answer prompts:
# Country: US
# State: Idaho  
# City: Boise
# Organization: BoiseCounty
# Org Unit: CCVFD
# Change password: Yes
# New password: [YOUR_PASSWORD]
# Root CA: boisecountyroot
# Intermediate CA: intermediateBC
# FQDN: tak.pinenut.tech
# Let's Encrypt: Yes
# Email: admin@pinenut.tech
# Connector: SSL
# Federation: Yes
# Admin cert: Yes
# Data packages: Yes

# Wait for completion, then exit container
exit
```

---

## 5.7b Retrieve Certificates

```# Pull certificates to host
sudo lxc file pull tak/root/webadmin.p12 ~/
sudo lxc file pull tak/root/enrollment-default.zip ~/

# Change ownership for WinSCP
sudo chown takadmin:takadmin ~/webadmin.p12
sudo chown takadmin:takadmin ~/enrollment-default.zip

# Download via WinSCP from /home/takadmin/
```

---

## 5.8 Access Web UI

```# On Windows:
# 1. Double-click webadmin.p12
# 2. Import wizard: Select "Automatically select certificate store"
# 3. Enter password (from installation)
# 4. Complete import
# 5. Restart browser
# 6. Navigate to: https://tak.pinenut.tech:8443
```

---

## 5.9 Create Additional User Enrollments

```# Enter tak container
sudo lxc exec tak -- bash

# Create user certificate
cd /opt/tak/certs
./makeCert.sh client username

# Create enrollment package
cd files
zip /root/enrollment-username.zip username.p12 truststore-root.p12

# Exit and pull
exit
sudo lxc file pull tak/root/enrollment-username.zip ~/
sudo chown takadmin:takadmin ~/enrollment-username.zip
```

---

## 5.10 MediaMTX (Optional)

```# Install MediaMTX
lxc exec rtsptak -- apt update
lxc exec rtsptak -- apt install -y curl vim
lxc exec rtsptak -- mkdir -p /opt/mediamtx
lxc exec rtsptak -- bash -c "cd /opt/mediamtx && curl -L -o mediamtx.tar.gz 'https://github.com/bluenviron/mediamtx/releases/download/v1.15.2/mediamtx_v1.15.2_linux_amd64.tar.gz' && tar xzf mediamtx.tar.gz"

# Create systemd service
lxc exec rtsptak -- bash <<'EOF'
cat >/etc/systemd/system/mediamtx.service <<'SYSTEMD'
[Unit]
Description=MediaMTX
After=network.target

[Service]
User=root
ExecStart=/opt/mediamtx/mediamtx
Restart=on-failure

[Install]
WantedBy=multi-user.target
SYSTEMD
EOF

# Start service
lxc exec rtsptak -- systemctl daemon-reload
lxc exec rtsptak -- systemctl enable --now mediamtx
```

---

## Snapshots (Recommended)

```# Take snapshots after each major step
lxc snapshot haproxy post-config-$(date +%F)
lxc snapshot tak post-install-$(date +%F)
lxc snapshot web initial-$(date +%F)
lxc snapshot rtsptak post-mediamtx-$(date +%F)

lxc restore {container} {snapshot−name}
```

---

## Quick Verification Commands

```# Container IPs
lxc list

# TAK Server status
sudo lxc exec tak -- systemctl status takserver

# TAK Server logs
sudo lxc exec tak -- tail -f /opt/tak/logs/takserver-messaging.log

# HAProxy status
lxc exec haproxy -- systemctl status haproxy

# Check listening ports on host
sudo ss -tulpn | grep -E ':(80|443|8089|8443|8554)'

# Test external access
curl -v https://tak.pinenut.tech:8443 2>&1 | grep Connected
```
