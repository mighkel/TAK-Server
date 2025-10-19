# TAK VPS LXD Deployment Guide

> Opinionated, practical guide for deploying a multi-container TAK Server on an Ubuntu 22.04 LTS VPS using LXD containers and HAProxy. Integrates the myTeckNet `installTAK` installer and adds MediaMTX (RTSP) support for ICU / UAS Tool testing.

---

## Table of contents

1. Introduction & goals
2. Target architecture
3. Prerequisites (host & LXD)
4. High-level deployment steps
5. Detailed step-by-step (commands you can copy/paste)
   - Host provisioning & hardening
   - LXD init and networking
   - Create containers: haproxy, tak, web, rtsptak
   - HAProxy config (full, with Let’s Encrypt + TAK passthru + RTSP)
   - Install TAK Server using myTeckNet installer (how to copy files, run it)
   - MediaMTX container setup and HAProxy RTSP forwarding
6. Security hardening checklist
7. Backups & snapshots automation
8. Monitoring, logging, and testing
9. Disaster recovery & restore checklist
10. GitHub repo plan (private & public) and recommended repo contents
11. Appendix: useful scripts & sample files

---

## 1. Introduction & goals

This guide is targeted at a small public-safety sandbox deployment (county / volunteer fire department). Goals:

- Multi-container LXD layout: `haproxy`, `tak`, `web`, `rtsptak`.
- Keep onboarding simple for users (mission-package auto-config, client certs).
- Reasonable security hardening while preserving easy onboarding (avoid VPN requirement).
- Provide repeatable steps so you can later publish a public repo with templates.

Host: SSDNodes VPS (Ubuntu 22.04 LTS). LXD containers for isolation and snapshot/rollback convenience.

---

## 2. Target architecture

```
Internet
   |
   +--> Host (Ubuntu 22.04 Lts, LXD)
          |
          +--> LXD bridge (lxdbr0) -> containers
                 |
                 +--- haproxy (reverse-proxy, TLS termination, SNI/tcp pass-through)
                 +--- tak (TAK Server installed via myTeckNet installer)
                 +--- web (Apache/Nginx for documentation / landing page)
                 +--- rtsptak (MediaMTX for RTSP/SRT feeds)
```

Ports published on the host are NAT'd or forwarded to haproxy — haproxy routes connections to appropriate containers (TCP passthrough for TAK ports, HTTP for web, RTSP TCP/UDP to media).

---

## 3. Prerequisites (host & LXD)

- SSDNodes VPS running Ubuntu 22.04 LTS (minimal install). Make sure you can SSH in.
- Domain name with DNS A records for `tak.pinenut.tech`, `web.pinenut.tech`, `rtsptak.pinenut.tech` pointing to the VPS public IP.
- LXD installed (snap) and basic knowledge of `lxc` commands. This guide uses `lxd`/`lxc` commands.
- You already have `installTAK` (myTeckNet) files; place them where the guide indicates (we show commands to copy into the tak container).

---

## 4. High-level deployment steps

1. Provision host, create admin user, add SSH key, disable root password auth.
2. Install and initialize LXD; create an LXD bridge or use `lxdbr0`.
3. Launch containers: `haproxy`, `tak`, `web`, `rtsptak`.
4. Configure container networking and firewall rules (host ufw and container ufw where applicable).
5. Configure HAProxy and Certbot for TLS (or let `installTAK` manage LetsEncrypt inside TAK container as preferred).
6. Install TAK Server inside `tak` container using myTeckNet `installTAK` script.
7. Configure MediaMTX inside `rtsptak` container and add HAProxy routing for RTSP.
8. Snapshot containers and configure backup cron jobs.

---

## 5. Detailed step-by-step

> All commands assume you are root on the host or using `sudo`.

### 5.1 Host provisioning & hardening (Ubuntu 22.04)

```bash
### 📝 PuTTY Connection Setup

**Option 1: Modify existing root connection**
1. Load your existing root session in PuTTY
2. Change "Host Name" from `root@your-vps-ip` to just `your-vps-ip`
3. Connection → Data → Auto-login username: `takadmin`
4. Connection → SSH → Auth → Private key file: Browse to your `.ppk` file
5. Session → Save (give it a new name like "VPS-takadmin")

**Option 2: Login prompt method (simpler)**
1. Use your existing root connection settings
2. When PuTTY prompts "login as:", type `takadmin`
3. Should login without password

⚠️ **Common mistake:** Creating a new PuTTY session from scratch without setting the private key path under Connection → SSH → Auth → Private key file

# Update & basic tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip snapd ufw fail2ban

# Create admin user (if not already created), add to sudo
sudo adduser takadmin
sudo usermod -aG sudo takadmin

# Add your public SSH key to /home/takadmin/.ssh/authorized_keys
sudo mkdir -p /home/takadmin/.ssh
sudo chmod 700 /home/takadmin/.ssh
sudo chown takadmin:takadmin /home/takadmin/.ssh

# ⚠️ IMPORTANT: Get the correct SSH key format
# Open PuTTYgen on your Windows machine
# Load your private key (.ppk file)
# In the menu: Conversions → Export OpenSSH key
# Save as: id_rsa (no extension) - THIS IS YOUR PRIVATE KEY FOR REFERENCE
# 
# Now get the PUBLIC key in the correct format:
# In PuTTYgen, at the top, you'll see "Public key for pasting into OpenSSH authorized_keys file:"
# COPY THE ENTIRE TEXT from that box - it will be ONE LONG LINE starting with "ssh-rsa"

# Create or edit the authorized_keys file using nano
sudo nano /home/takadmin/.ssh/authorized_keys

# Paste your SSH public key
# It should look like ONE line:
# ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... (very long)... rsa-key-20250101
#
# ⚠️ CRITICAL: Must be ONE continuous line with NO line breaks
# If it wraps in nano, that's OK - just make sure there are no actual newline characters
# The entire key should be on a single line

# Press Ctrl+O, Enter to save
# Press Ctrl+X to exit

# Set correct permissions:
sudo chmod 600 /home/takadmin/.ssh/authorized_keys
sudo chown takadmin:takadmin /home/takadmin/.ssh/authorized_keys

# ⚠️ VERIFY the key is correct
cat /home/takadmin/.ssh/authorized_keys
# Should show ONE line starting with "ssh-rsa"
# Should be approximately 400-800 characters long
# Should NOT have any line breaks in the middle

# Optional Quick Test — Verify SSH access before disabling root

# ⚠️ Do not close your current root session yet.
# Open a new PuTTY session for this test.
ssh takadmin@<your_vps_ip>
# Should login WITHOUT asking for password

# If you log in without being prompted for a password, your SSH key authentication works.
# Next, verify sudo rights:
sudo whoami

# Expected output:
root

# If both commands succeed, you can safely disable root SSH login.
# If login fails or asks for a password, double-check:
sudo chmod 700 /home/takadmin/.ssh
sudo chmod 600 /home/takadmin/.ssh/authorized_keys

# Ensure your public key is one continuous line with no line breaks.

# Disable root SSH and password authentication
sudo nano /etc/ssh/sshd_config
# Set:
# PermitRootLogin no
# PasswordAuthentication no
sudo systemctl reload sshd

# Alternatively (one-liners):
sudo sed -i "s/^#*PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo systemctl reload sshd

# Configure UFW firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw allow 8089/tcp
sudo ufw allow 8443/tcp
sudo ufw allow 8554/tcp
echo "y" | sudo ufw enable

# Configure UFW to allow container traffic
sudo nano /etc/default/ufw
# Change: DEFAULT_FORWARD_POLICY="ACCEPT"

# Edit UFW before rules
sudo nano /etc/ufw/before.rules
# Add NAT rules at the TOP (before *filter):

# NAT table rules for LXD containers
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.86.10.0/24 ! -d 10.86.10.0/24 -j MASQUERADE
COMMIT

# Then find the "# ok icmp codes for INPUT" section and add BEFORE it:

# Allow all traffic from LXD containers
-A ufw-before-forward -i lxdbr0 -j ACCEPT
-A ufw-before-forward -o lxdbr0 -j ACCEPT

# Reload UFW
sudo ufw disable
sudo ufw enable

# Enable Fail2ban for basic SSH protection
sudo systemctl enable --now fail2ban
# Default jail protects SSH only; configuration file: /etc/fail2ban/jail.local
```

Notes:
- If you lock yourself out, use VPS console from SSDNodes to recover. Consider limiting SSH to your office/home IP.
- You can further harden by creating an SSH bastion, but you're intentionally keeping onboarding friendly.

### 5.2 Install and initialize LXD

```bash
# Install LXD via snap (should already be installed)
sudo snap install lxd

# Add current user to lxd group
sudo usermod -aG lxd $USER
newgrp lxd

# Initialize LXD (use --auto for defaults)
sudo lxd init --auto
# Note: If lxdbr0 already exists, this is fine - it will use the existing bridge

# Verify LXD is ready
lxc network list
# Should show lxdbr0
```

If you prefer bridged networking (bridge to host interface for public IPs), re-run `sudo lxd init` interactively and choose a bridged profile.

### 5.3 Create containers (Ubuntu 22.04 images)

We'll create 4 containers. Adjust names to your naming standard.
```bash
lxc launch ubuntu:22.04 haproxy
lxc launch ubuntu:22.04 tak
lxc launch ubuntu:22.04 web
lxc launch ubuntu:22.04 rtsptak

# Wait for containers to start
sleep 10

# Check they're running (will only show IPv6 initially)
lxc list
```

### 5.3.1 Fix Container DNS (Required with UFW)

When UFW is enabled, containers need DNS configured properly:
```bash
# Assign static IPs and routes
lxc exec haproxy -- ip addr add 10.86.10.10/24 dev eth0
lxc exec haproxy -- ip route add default via 10.86.10.1

lxc exec tak -- ip addr add 10.86.10.11/24 dev eth0
lxc exec tak -- ip route add default via 10.86.10.1

lxc exec web -- ip addr add 10.86.10.12/24 dev eth0
lxc exec web -- ip route add default via 10.86.10.1

lxc exec rtsptak -- ip addr add 10.86.10.13/24 dev eth0
lxc exec rtsptak -- ip route add default via 10.86.10.1

# Disable systemd-resolved and set static DNS
for container in haproxy tak web rtsptak; do
  lxc exec $container -- systemctl disable systemd-resolved
  lxc exec $container -- systemctl stop systemd-resolved
  lxc exec $container -- rm /etc/resolv.conf
  lxc exec $container -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
  lxc exec $container -- bash -c "echo 'nameserver 8.8.4.4' >> /etc/resolv.conf"
done

# Verify networking
lxc list
lxc exec haproxy -- ping -c 2 8.8.8.8
lxc exec tak -- nslookup archive.ubuntu.com
```

### 5.3.2 Make Static IPs Permanent with Netplan

Create netplan configuration to persist IPs across reboots:
```
# HAProxy (10.86.10.10)
lxc exec haproxy -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.86.10.10/24]
      routes:
        - to: default
          via: 10.86.10.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# TAK (10.86.10.11)
lxc exec tak -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.86.10.11/24]
      routes:
        - to: default
          via: 10.86.10.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# Web (10.86.10.12)
lxc exec web -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.86.10.12/24]
      routes:
        - to: default
          via: 10.86.10.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# RTSPTAK (10.86.10.13)
lxc exec rtsptak -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.86.10.13/24]
      routes:
        - to: default
          via: 10.86.10.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# Apply netplan configurations
for container in haproxy tak web rtsptak; do
  lxc exec $container -- chmod 600 /etc/netplan/10-lxc.yaml
  lxc exec $container -- netplan apply
done
```
Note: You may see "WARNING: Cannot call Open vSwitch" messages - these are harmless.
Container IP Summary:

- `haproxy: 10.86.10.10`
- `tak: 10.86.10.11`
- `web: 10.86.10.12`
- `rtsptak: 10.86.10.13`



### 5.4 Prepare containers (common steps)

```bash
# Update all containers
for container in haproxy tak web rtsptak; do
  lxc exec $container -- bash -c "apt update && apt upgrade -y"
  lxc exec $container -- apt install -y vim curl wget unzip
done
```

Optional: Create admin user in containers
If you want to SSH directly into containers (not required):

```bash
# Create takadmin user in each container
for container in haproxy tak web rtsptak; do
  lxc exec $container -- useradd -m -s /bin/bash takadmin || true
  lxc exec $container -- bash -c "mkdir -p /home/takadmin/.ssh && chown takadmin:takadmin /home/takadmin/.ssh"
done

# Note: Copying SSH keys requires the key to exist on the host
# Skip this step if you don't need direct SSH access to containers
```

Note: For most deployments, you don't need SSH access inside containers since you can use `lxc exec`.

### 5.5 HAProxy container: install & full config

`haproxy` is the single public-facing reverse proxy that handles all incoming traffic to your VPS. We'll install HAProxy and configure SNI/TCP passthrough for TAK ports and RTSP, allowing SSL/TLS connections to pass through directly to the TAK container.

**What HAProxy does:**
- Routes port 80 traffic to the web container
- Forwards Let's Encrypt challenges to TAK for certificate validation
- Passes through encrypted TAK traffic (ports 8089 and 8443) without decryption
- Routes RTSP traffic (port 8554) to the MediaMTX container

Install HAProxy in the haproxy container:
```bash
lxc exec haproxy -- apt install -y haproxy certbot
```

Now create `/etc/haproxy/haproxy.cfg` inside the `haproxy` container with the contents below. Use `lxc file push` or `lxc exec haproxy -- tee /etc/haproxy/haproxy.cfg <<'EOF'` to write it.

**Full HAProxy config (example)** — adjust domain names and backend IPs to your `lxc list` values.

```
# Create the config file on the host first
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

# HTTP frontend for web UI and ACME challenges
frontend http-in
    bind *:80
    mode http
    
    # Forward Let's Encrypt challenges to tak container
    acl is_acme_challenge path_beg /.well-known/acme-challenge/
    use_backend tak-acme-backend if is_acme_challenge
    
    # Normal web traffic
    acl host_web hdr(host) -i web.pinenut.tech
    use_backend web-backend if host_web
    default_backend web-backend

backend tak-acme-backend
    mode http
    server tak 10.86.10.11:80

backend web-backend
    mode http
    server web1 10.86.10.12:80

# HTTPS SNI passthrough for TAK client (TCP/SSL) on 8089
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
    server tak 10.86.10.11:8089

# TAK server Web UI (HTTPS) on 8443 - passthrough
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
    server takweb 10.86.10.11:8443

# RTSP frontend (TCP) for MediaMTX on port 8554
frontend rtsp-in
    bind *:8554
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    default_backend rtsptak-backend

backend rtsptak-backend
    mode tcp
    server rtsptak 10.86.10.13:8554 check

# Stats endpoint
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy_stats
    stats auth admin:YourStrongPassword
EOF

# Push the file to the haproxy container
lxc file push ~/haproxy.cfg haproxy/etc/haproxy/haproxy.cfg

# Verify the config
lxc exec haproxy -- cat /etc/haproxy/haproxy.cfg

# Test the config syntax
lxc exec haproxy -- haproxy -c -f /etc/haproxy/haproxy.cfg

# Restart HAProxy
lxc exec haproxy -- systemctl restart haproxy
lxc exec haproxy -- systemctl enable haproxy

# Check status
lxc exec haproxy -- systemctl status haproxy
```

Notes:
- HAProxy is configured for TCP passthrough for TAK and RTSP. This lets TLS be terminated inside the TAK and Media containers (or you can terminate TLS in HAProxy; choose one).
- If you prefer HAProxy to terminate TLS (recommended for central cert management), change `mode tcp` to `mode http` for HTTP frontends and add `bind *:443 ssl crt /etc/letsencrypt/live/domain/fullchain.pem` lines.

After you write the config, verify and restart HAProxy:

```
# Verify the config
lxc exec haproxy -- cat /etc/haproxy/haproxy.cfg

# Test the config syntax
lxc exec haproxy -- haproxy -c -f /etc/haproxy/haproxy.cfg

# Restart HAProxy
lxc exec haproxy -- systemctl restart haproxy
lxc exec haproxy -- systemctl enable haproxy

# Check status
lxc exec haproxy -- systemctl status haproxy
```

### 5.5b Port forwarding from host to HAProxy container

Now that HAProxy is configured and running inside its container, we need to forward ports from the VPS public IP to the HAProxy container. This makes HAProxy accessible from the internet.
```
# Forward HTTP (port 80)
lxc config device add haproxy http proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80

# Forward HTTPS (port 443) - for future use
lxc config device add haproxy https proxy listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443

# Forward TAK client port (8089)
lxc config device add haproxy tak8089 proxy listen=tcp:0.0.0.0:8089 connect=tcp:127.0.0.1:8089

# Forward TAK web UI port (8443)
lxc config device add haproxy tak8443 proxy listen=tcp:0.0.0.0:8443 connect=tcp:127.0.0.1:8443

# Forward RTSP port (8554)
lxc config device add haproxy rtsp8554 proxy listen=tcp:0.0.0.0:8554 connect=tcp:127.0.0.1:8554

# Optional: Forward HAProxy stats page (8404)
lxc config device add haproxy stats proxy listen=tcp:0.0.0.0:8404 connect=tcp:127.0.0.1:8404
```

Verify the proxy devices are active:
```
bash
lxc config show haproxy | grep -A3 "devices:"
```

Test that HAProxy is now listening on the host:
```
bash
# On the host, check that ports are listening
sudo ss -tulpn | grep -E ':(80|443|8554|8089|8443|8404)'
```

You should see the ports bound to 0.0.0.0 (all interfaces).

### 5.6 TLS / Let’s Encrypt strategy

Two valid strategies:

A. **Certbot inside the TAK container (myTeckNet installer supports this)** — `installTAK` will request certs, convert them to JKS and hook them into TAK. This is handy if you want the TAK container to manage its own certs.

B. **Central TLS at HAProxy** — HAProxy handles Let's Encrypt certs and terminates TLS. TAK is then behind HAProxy using HTTP/TCP without needing Let's Encrypt inside the tak container.

**Recommendation:** Start with option A (let `installTAK` manage certs) since you already have the script set up and it auto-creates mission-packages. Later move TLS termination into HAProxy if you want a single point of cert management.

If using HAProxy termination, install certbot on the `haproxy` container and configure a renewal hook that reloads HAProxy after cert renewal.

### 5.7 Install TAK Server inside `tak` container (myTeckNet installTAK)

The myTeckNet `installTAK` script automates TAK Server installation, certificate generation, and creates enrollment packages for easy ATAK client onboarding.

**Note for Windows users:** The script has no extension but is a bash script. 
If you renamed it to `installTAK.sh` during transfer, that's fine - it works either way.
Just remember to use `chmod +x` to make it executable.

#### Prerequisites

Download these files from https://tak.gov to your local Windows machine:
- `takserver_5.5-RELEASE58_all.deb` (or latest version)
- `takserver-public-gpg.key`
- `deb_policy.pol`

Download `installTAK.sh` from https://github.com/myTeckNet/installTAK to your local machine.

Place all files in a folder like `C:\TAK\` on your Windows desktop.

#### Transfer files to VPS

Using WinSCP, connect to your VPS as `takadmin` and upload all files to `/home/takadmin/tak-install/`:

1. Open WinSCP and connect to your VPS IP
2. Activate directory `/home/takadmin/`
3. Upload all 4 files to this directory

#### Push files into tak container

From your SSH session on the VPS host:
```bash
# Push all TAK files into the tak container
lxc file push installTAK.sh tak/root/
lxc file push takserver_5.5-RELEASE58_all.deb tak/root/
lxc file push takserver-public-gpg.key tak/root/
lxc file push deb_policy.pol tak/root/

# Make the installer executable
lxc exec tak -- chmod +x /root/installTAK.sh

# Verify files are in place
lxc exec tak -- ls -lh /root/
```

#### Run the installer from inside the container to avoid path issues
```
sudo lxc exec tak -- bash
# Start the interactive installer
cd /root
./installTAK.sh takserver_5.5-RELEASE58_all.deb
```

The installer will prompt you for:

1. **Platform selection** - Choose Ubuntu/Debian
2. **Certificate details**:
   - Country (US)
   - State (Idaho)
   - City (Boise)
   - Organization (BoiseCounty)
   - Organizational Unit (CCVFD)
   - Change default Cert password from atakatak? (Yes) (hwy21hwy21)
   - Name for Root CA (boisecountyroot)
   - Intermediate CA (intermediateBC)
4. **Server FQDN** - Enter `tak.pinenut.tech`
5. **Let's Encrypt** - Choose YES to automatically get SSL certificates
   - Provide email for cert notifications
6. **Connector type** - Choose SSL (not QUIC unless you need it)
7. **Federation** - Choose NO unless you're connecting to other TAK servers (Yes)
8. **Admin certificate** - YES, create an admin cert for WebTAK access
9. **Data packages** - YES, create enrollment packages for ATAK clients

The installer will:
- Install Java, PostgreSQL, PostGIS
- Configure TAK Server
- Request Let's Encrypt certificates
- Create enrollment packages (`enrollmentDP.zip`)
- Start the TAK Server service

#### Verify installation
```bash
# Check TAK Server status
lxc exec tak -- systemctl status takserver

# View recent logs
lxc exec tak -- tail -n 50 /opt/tak/logs/takserver-messaging.log

# Check that TAK is listening on ports 8089 and 8443
lxc exec tak -- ss -tulpn | grep java
```

Expected output should show Java processes listening on ports 8089 and 8443.

#### Retrieve enrollment packages

The enrollment packages are located at `/opt/tak/certs/files/` inside the tak container. Pull them to the host, then download via WinSCP:
```bash
# Pull enrollment package from tak container to host
lxc file pull tak/opt/tak/certs/files/enrollmentDP.zip /home/takadmin/

# Now use WinSCP to download enrollmentDP.zip from /home/takadmin/ to your Windows machine
```

You'll distribute this ZIP file to ATAK users for easy connection to your TAK Server.

**Important notes:**
- The installer validates system requirements (8GB+ RAM, disk space)
- Let's Encrypt requires ports 80/443 to be accessible for certificate validation
- If Let's Encrypt fails, the installer will create a local CA instead
- Save the admin certificate password shown during installation

### 5.8 Mission-package generation & onboarding

`installTAK` will create enrollment ZIPs (`enrollmentDP.zip`) that contain `config.pref` and `caCert.p12` which users import into ATAK/WinTAK. Store these in the `web` container for secure download, or hand them out via secure transfer.

**Security note:** Treat `.p12` truststores carefully; they contain CA/private material if misconfigured. Use enrollment flow that supplies only the client truststore (trust anchor) and not private CA keys.

### 5.9 Web container (optional)

Install a simple web server for hosting documentation and mission packages:

```bash
lxc exec web -- apt install -y apache2
# Place enrollment packages into /var/www/html/enroll
lxc file push enrollmentDP.zip web/var/www/html/enroll/enrollmentDP.zip
lxc exec web -- chown www-data:www-data /var/www/html/enroll/enrollmentDP.zip
```

Add an index page with instructions for testers.

### 5.10 Media container: MediaMTX (RTSP)

MediaMTX is an actively maintained RTSP server that serves RTSP/RTMP/SRT feeds. We'll set it up in `rtsptak` container.

```bash
# On host, download latest MediaMTX release or use package in container
lxc exec rtsptak -- bash -lc "apt update && apt install -y curl vim"
# Create a directory and download binary
lxc exec rtsptak -- mkdir -p /opt/mediamtx
# If you have the binary locally: lxc file push mediamtx binary path
# Example to download inside container (replace URL with latest):
lxc exec rtsptak -- bash -lc "cd /opt/mediamtx && curl -L -o mediamtx.tar.gz 'https://github.com/bluenviron/mediamtx/releases/download/v1.15.2/mediamtx_v1.15.2_linux_amd64.tar.gz' && tar xzf mediamtx.tar.gz"

# Create systemd service file for MediaMTX
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

# Enable and start the service
lxc exec rtsptak -- systemctl daemon-reload
lxc exec rtsptak -- systemctl enable --now mediamtx
```

MediaMTX default listens on TCP 8554 for RTSP. We mapped haproxy backend to container port `8554` (or `8554` → `8554` mapping). Configure MediaMTX via its `mediamtx.yml` for stream auth or specific mount points.

**Static RTSP example config** (`/opt/mediamtx/config.yml`):

```yaml
paths:
  camera1:
    source: rtsp://
    sourceOnDemand: yes
    readTimeout: 10s
```

Restart mediamtx after config changes.

### 5.11 HAProxy RTSP forwarding (if not terminating TLS)

We included a TCP frontend on port 554 in the HAProxy config. If you need SRT or other transports later, map those ports similarly and adjust MediaMTX to listen on SRT ports.

---

## 6. Security hardening checklist (practical)

- Host:
  - Non-root admin user; SSH keys only; disable password auth.
  - UFW default deny incoming; open only required ports.
  - Fail2ban for SSH brute force protection.
  - Regular OS updates (apt upgrade) and review package updates.
- Containers:
  - Minimal packages; do not install GUI.
  - Limit container privileges — keep default LXD profiles (avoid privileged containers).
  - Per-container UFW if desired for defense-in-depth.
- TAK specifics:
  - Use certs (client cert truststore) + enrollment packages for ATAK onboarding.
  - Limit WebTAK admin accounts; create strong passwords and restrict admin UI to specific IPs if possible.
  - Audit `tak` logs for suspicious auth attempts.

---

## 7. Backups & snapshots automation

**Snapshots (recommended) — quick rollbacks**

Create snapshots before major changes:

```bash
lxc snapshot tak pre-install-YYYYMMDD
lxc snapshot haproxy pre-config-YYYYMMDD
```

Automate nightly snapshots for containers:

`/usr/local/bin/lxd-nightly-snapshots.sh`

```bash
#!/bin/bash
TODAY=$(date +%F)
for CT in tak haproxy web rtsptak; do
  /snap/bin/lxc snapshot ${CT} auto-${TODAY}
  # Optional: delete snapshots older than 14 days
  /snap/bin/lxc info ${CT} | grep "Snapshots:" -A20
done
```

Cronjob (host):

```cron
0 3 * * * root /usr/local/bin/lxd-nightly-snapshots.sh >/var/log/lxd-snapshots.log 2>&1
```

**Data backups (TAK DB + certs)**

Inside `tak` container, back up PostgreSQL and `/opt/tak` keystore/certs.

Example backup script placed on host that uses `lxc exec` to perform dumps:

```bash
#!/bin/bash
DATE=$(date +%F-%H%M)
mkdir -p /var/backups/tak/$DATE
# Dump Postgres (replace with container specifics)
lxc exec tak -- bash -lc "pg_dump -U tak -F c takdb" > /var/backups/tak/$DATE/takdb.dump
# Copy keystore and certs
lxc file pull tak/opt/tak/certs/files/fed-truststore.jks /var/backups/tak/$DATE/
# Tar and move offsite
cd /var/backups/tak && tar czf tak-backup-$DATE.tgz $DATE
# Upload to remote (rsync / rclone to offsite storage)
```

Schedule weekly and after any major changes. Test restores.

---

## 8. Monitoring, logging, and testing

- Monitor container health and HAProxy stats page.
- Log rotation: `logrotate` for HAProxy logs and take `tak` logs (rotate /opt/tak/logs).
- Basic uptime checks: UptimeRobot or a small Prometheus node_exporter (host) + alerting.

Testing steps after install:

1. Confirm HAProxy frontends are listening: `lxc exec haproxy -- ss -ltnp`.
2. From external client, test HTTP (web) and HTTPS endpoints.
3. Test importing `enrollmentDP.zip` into ATAK on an Android device.
4. Test RTSP pull from MediaMTX using VLC: `rtsp://rtsptak.pinenut.tech/camera1`.

---

## 9. Disaster recovery & restore checklist

1. If container broken: `lxc launch images:ubuntu/22.04 --clone <snapshot>` or `lxc restore <container> <snapshot>`.
2. If DB corrupted: restore from `pg_dump` and reapply keystore files.
3. If certs expired: re-run `certbot` (or re-invoke `installTAK` renewal helper) and restart services.
4. If host fails: spin a new SSDNodes instance, `snap install lxd`, push your public repo with preconfigured files and restore snapshots/backups.

---

## 10. GitHub repo plan (private & public)

When you create your repos, here’s recommended layout.

**Private repo (preconfigured for your environment)** — contents:

- `host-setup/` — host init scripts (user creation, ufw rules, fail2ban config)
- `lxd-profiles/` — exported LXD profiles (network/storage) and `lxc` commands to import
- `containers/` — `haproxy/`, `tak/`, `web/`, `rtsptak/` subfolders with `Dockerfile`-like configs or `cloud-init` userdata for containers
- `installTAK/` — your copy of `installTAK` and local `answers.txt` for unattended install
- `secrets.example` (NOT actual secrets) — template for where to place CA password, domain names
- `backup/` — backup & restore scripts

**Public repo (helpful for others)** — contents:

- `README.md` — high-level guide (sanitized)
- `lxd-commands.md` — step-by-step LXD commands (no secrets)
- `haproxy/` — example haproxy.cfg (with placeholders)
- `rtsptak/` — MediaMTX example config
- `install-scripts/` — convenience scripts to create containers and initial snapshots
- `CONTRIBUTING.md` — how to adapt to local domains/IPs

**Important**: Never commit private keys, real passwords, or `.p12` files to public repo. Use `.gitignore` and keep secrets in private repo or a secrets manager.

---

## 11. Appendix: useful scripts & sample files

### 11.1 lxd-nightly-snapshots.sh (sample)

(Provided earlier — copy to `/usr/local/bin/lxd-nightly-snapshots.sh` and `chmod +x`.)

### 11.2 sample haproxy renewal hook (if HAProxy terminates TLS)

```bash
#!/bin/bash
# /etc/letsencrypt/renewal-hooks/post/reload-haproxy.sh
systemctl reload haproxy
```

### 11.3 sample tak backup (host-run)

(Provided earlier in Backups section.)

---

## Quick checklist before going live

- [ ] Get DNS set for `tak`,`web`,`rtsptak` subdomains
- [ ] Create containers and verify IPs
- [ ] Install HAProxy and push config with correct backend IPs
- [ ] Copy `installTAK` to tak container and run the installer
- [ ] Generate and test `enrollmentDP.zip` on ATAK client
- [ ] Configure MediaMTX and test RTSP stream
- [ ] Snapshot all containers and run test restores
- [ ] Create private GitHub repo for auto-deploy tooling

---

If you want, I can now:

- Produce a ready-to-run **host bootstrap script** to perform the host hardening commands, LXD install, and create the 4 containers with initial snapshots (I’ll annotate it heavily for safety), **or**
- Produce a **full haproxy.cfg** file (already included) tailored to the container IPs you have right now if you paste `lxc list` output.

Tell me which next artifact you want and I will add it into the repo doc or produce it as a separate file.

---

*End of TAK-VPS-LXD-DEPLOYMENT-GUIDE.md*

