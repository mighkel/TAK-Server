# TAK VPS LXD Deployment Guide

> Opinionated, practical guide for deploying a multi-container TAK Server on an Ubuntu 22.04 LTS VPS using LXD containers and HAProxy. Integrates the myTeckNet `installTAK` installer and adds MediaMTX (RTSP) support for ICU / UAS Tool testing.

## 0. Before You Begin - Customize This Guide

This guide uses placeholder values that you MUST customize for your deployment.

### Required Placeholders to Replace:

| Placeholder | Example | Your Value |
|------------|---------|------------|
| `[DOMAIN.TLD]` | `myawesometakserver.com` | _____________ |
| `[ADMIN_USER]` | `admin` | _____________ |
| `[ADMIN_PASSWORD]` | `SecurePass123!` | _____________ |
| `XXX.XXX` (in IPs) | `251.149` | _____________ (from Section 5.2.1) |

### ✅ Pre-Flight Checklist

Before starting Section 5, verify you have:

- [ ] Registered domain name
- [ ] DNS records configured and propagated (test with `nslookup tak.[DOMAIN.TLD]`)
- [ ] VPS provisioned with Ubuntu 22.04
- [ ] SSH access to VPS working
- [ ] TAK Server files downloaded from tak.gov
- [ ] This guide customized with your values (or forked repo ready)

### Two Options for Using This Guide:

**Option 1: Find & Replace in Text Editor (Recommended for first-time users)**
1. Copy this entire guide into a text editor (Notepad++, VS Code, Sublime)
2. Use Find & Replace to customize all placeholders
3. Save your customized version for reference
4. Copy/paste commands from your customized guide

**Option 2: Fork This Repo (Recommended for experienced users)**
1. Fork this repository on GitHub
2. Edit the guide in your fork with your actual values
3. Keep your fork private (contains your domain/config details)
4. Use your customized fork as your deployment reference

⚠️ **DO NOT commit sensitive passwords to GitHub**, even in private repos. Use placeholders in your fork and keep actual passwords in a separate password manager.

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

The basis for this install:
Host: SSDNodes VPS, Standard 32GB RAM 480GB SSD Dallas
OS:   Ubuntu 22.04 LTS
More: LXD containers for isolation and snapshot/rollback convenience.

I use SSDNodes due to the low cost and my user experience & feedback on reliablity I have received from others I know that have used them.

If you find this guide useful and you would like to try it on SSDNodes, please consider using my referral link.  I almost exclusively use my SSDNodes VPS to support my rural volunteer fire department.

https://www.ssdnodes.com/manage/aff.php?aff=1554&register=true

If you already have an SSDNodes account and would still like to support this work and a great cause, please consider donating to Clear Creek Volunteer Fire Department in Boise Idaho.

https://www.clearcreekvfd.com/donate

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
- **Domain name registered** with DNS A records configured:
  - `tak.[DOMAIN.TLD]` → VPS public IP
  - `web.[DOMAIN.TLD]` → VPS public IP  
  - `rtsptak.[DOMAIN.TLD]` → VPS public IP
- LXD installed (snap) and basic knowledge of `lxc` commands
- TAK Server installation files downloaded from tak.gov
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
### SSH Key Authentication Setup

**This guide assumes that you do have SHH access via PuTTY or another Linux machine.
**For detailed SSH key setup instructions specific to your VPS provider:**
- **SSDNodes users:** [SSDNodes Host Setup & SSH Guide](https://github.com/mighkel/TAK-Server/blob/main/ssdnodes_host_setup_and_ssh.md)
- **DigitalOcean users:** Coming soon
- **AWS users:** Coming soon
- **Google Cloud users:** Coming soon


# Update OS and package repositories
sudo apt update && sudo apt upgrade -y

**Note:** You may see messages about:
- "Newer kernel available" - This is informational; reboot at your convenience
- "Daemons using outdated libraries" - Select the services shown (defaults are fine)

# Install basic tools
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
# Check for multiple locations in the file
sudo nano /etc/ssh/sshd_config
# Set: (2 places)
# PermitRootLogin without password
# to
# PermitRootLogin no
# Set:
# PasswordAuthentication yes
# to
# PasswordAuthentication no
sudo systemctl reload sshd

# Alternatively (one-liners):
sudo sed -i "s/^#*PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo systemctl reload sshd

# Test:  Try to login as root
# You should get something like:
# > login as: root
# > Authenticating with public key ""
# > Server refused public-key signature despite accepting key!

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
```

### 5.2.1 Identify Your LXD Bridge Network

Before configuring containers, identify your LXD bridge subnet:
```bash
lxc network list
```

Look for the `lxdbr0` IPv4 address. Example output:
```
| lxdbr0 | bridge | YES | 10.251.149.1/24 | ... |
```

**Record the middle two octets** (the 2nd and 3rd numbers). 

Example: If your bridge is `10.251.149.1/24`, record `251.149`

You'll replace `XXX.XXX` throughout this guide with these two numbers.

💡 **Pro tip:** Copy all commands from sections 5.3.1, 5.3.2, and 5.5 into Notepad (or your text editor). Use Find & Replace:
- Find: `XXX.XXX`
- Replace with: Your middle two octets (e.g., `251.149`)

Then copy/paste the customized commands back into your terminal.

### 5.2.2 Configure UFW firewall and enable fail2ban
```bash
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
-A POSTROUTING -s 10.XXX.XXX.0/24 ! -d 10.XXX.XXX.0/24 -j MASQUERADE
COMMIT

**Note:** Replace `XXX.XXX` with your bridge subnet from Section 5.2.1 (e.g., if your bridge is `10.251.149.1/24`, use `10.251.149.0/24`)

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

### 5.3.1 Configure Static IPs and DNS

**Important:** Replace `XXX.XXX` in all commands below with your bridge subnet from section 5.2.1.

Assign static IP addresses and configure DNS for each container:
```bash
# Assign static IPs and routes
lxc exec haproxy -- ip addr add 10.XXX.XXX.10/24 dev eth0
lxc exec haproxy -- ip route add default via 10.XXX.XXX.1

lxc exec tak -- ip addr add 10.XXX.XXX.11/24 dev eth0
lxc exec tak -- ip route add default via 10.XXX.XXX.1

lxc exec web -- ip addr add 10.XXX.XXX.12/24 dev eth0
lxc exec web -- ip route add default via 10.XXX.XXX.1

lxc exec rtsptak -- ip addr add 10.XXX.XXX.13/24 dev eth0
lxc exec rtsptak -- ip route add default via 10.XXX.XXX.1

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

# Verify all containers have IPs and can ping gateway
for container in haproxy tak web rtsptak; do
  echo "=== $container ==="
  lxc exec $container -- ip addr show eth0 | grep "inet 10"
  lxc exec $container -- ping -c 1 -W 2 10.XXX.XXX.1
done
```

Expected result: All containers show their static IPs and can resolve DNS.

### 5.3.2 Make Static IPs Permanent with Netplan

**Important:** Replace `XXX.XXX` in all commands below with your bridge subnet from section 5.2.1.

Create netplan configuration to persist IPs across reboots:
```bash
# HAProxy (10.XXX.XXX.10)
lxc exec haproxy -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.XXX.XXX.10/24]
      routes:
        - to: default
          via: 10.XXX.XXX.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# TAK (10.XXX.XXX.11)
lxc exec tak -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.XXX.XXX.11/24]
      routes:
        - to: default
          via: 10.XXX.XXX.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# Web (10.XXX.XXX.12)
lxc exec web -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.XXX.XXX.12/24]
      routes:
        - to: default
          via: 10.XXX.XXX.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# RTSPTAK (10.XXX.XXX.13)
lxc exec rtsptak -- bash -c 'cat > /etc/netplan/10-lxc.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.XXX.XXX.13/24]
      routes:
        - to: default
          via: 10.XXX.XXX.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF'

# Apply netplan configurations
for container in haproxy tak web rtsptak; do
  lxc exec $container -- chmod 600 /etc/netplan/10-lxc.yaml
  lxc exec $container -- netplan apply
done

# Verify DNS still works after netplan apply
lxc exec tak -- nslookup google.com
# Should resolve successfully
```

**Note:** You may see "WARNING: Cannot call Open vSwitch" messages - these are harmless.

**Container IP Summary:**
- haproxy: `10.XXX.XXX.10`
- tak: `10.XXX.XXX.11`
- web: `10.XXX.XXX.12`
- rtsptak: `10.XXX.XXX.13`

### 5.4 Prepare containers (common steps)

```bash
# Update all containers
for container in haproxy tak web rtsptak; do
  lxc exec $container -- bash -c "apt update && apt upgrade -y"
  lxc exec $container -- apt install -y vim curl wget unzip
done
```

Optional: Create admin user in containers
**Note:** Most users can skip this section. The `lxc exec` command provides shell access without SSH.
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
# Enable universe repository for certbot
lxc exec haproxy -- apt update
lxc exec haproxy -- apt install -y software-properties-common
lxc exec haproxy -- add-apt-repository universe -y
lxc exec haproxy -- apt update

# Install HAProxy and certbot
lxc exec haproxy -- apt install -y haproxy certbot

# Verify installation
lxc exec haproxy -- haproxy -v
lxc exec haproxy -- certbot --version
```

Now create `/etc/haproxy/haproxy.cfg` inside the `haproxy` container with the contents below. Use `lxc file push` or `lxc exec haproxy -- tee /etc/haproxy/haproxy.cfg <<'EOF'` to write it.

**Full HAProxy config (example)** — adjust domain names and backend IPs to your `lxc list` values.

**Important:** Replace `XXX.XXX` in the backend server lines below with your bridge subnet from section 5.2.1.

**Security Note:** Before running these commands, edit `~/haproxy.cfg` towards the bottom of this section and replace:
- `[ADMIN_USER]` with your desired username (e.g., `admin`)
- `[ADMIN_PASSWORD]` with a strong password

This protects the HAProxy stats page at `http://your-vps-ip:8404/haproxy_stats`

```bash
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
    acl host_web hdr(host) -i web.[DOMAIN.TLD]
    use_backend web-backend if host_web
    default_backend web-backend

backend tak-acme-backend
    mode http
    server tak 10.XXX.XXX.11:80

backend web-backend
    mode http
    server web1 10.XXX.XXX.12:80

# HTTPS SNI passthrough for TAK client (TCP/SSL) on 8089
frontend tak-client
    bind *:8089
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    acl host_tak req.ssl_sni -i tak.[DOMAIN.TLD]
    use_backend tak-client-backend if host_tak

backend tak-client-backend
    mode tcp
    option ssl-hello-chk
    server tak 10.XXX.XXX.11:8089

# TAK server Web UI (HTTPS) on 8443 - passthrough
frontend tak-server
    bind *:8443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    acl host_takreq req.ssl_sni -i tak.[DOMAIN.TLD]
    use_backend tak-server-backend if host_takreq

backend tak-server-backend
    mode tcp
    option ssl-hello-chk
    server takweb 10.XXX.XXX.11:8443

# RTSP frontend (TCP) for MediaMTX on port 8554
frontend rtsp-in
    bind *:8554
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    default_backend rtsptak-backend

backend rtsptak-backend
    mode tcp
    server rtsptak 10.XXX.XXX.13:8554 check

# Stats endpoint
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy_stats
    stats auth [ADMIN_USER]:[ADMIN_PASSWORD]
EOF

# Push the file to the haproxy container
lxc file push ~/haproxy.cfg haproxy/etc/haproxy/haproxy.cfg

# Verify config was pushed correctly
lxc exec haproxy -- wc -l /etc/haproxy/haproxy.cfg
# Should show around 90+ lines

# Verify and restart
lxc exec haproxy -- cat /etc/haproxy/haproxy.cfg
lxc exec haproxy -- haproxy -c -f /etc/haproxy/haproxy.cfg
lxc exec haproxy -- systemctl restart haproxy
lxc exec haproxy -- systemctl enable haproxy
lxc exec haproxy -- systemctl status haproxy
```

Enter `q` to quit the truncated lines if required

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

You should see the ports bound to 0.0.0.0 (all interfaces)

Troubleshooting tip:
```
# If port forwarding fails with "already in use" error:
# Check if something else is listening:
sudo ss -tulpn | grep ':80 '

# If Apache or nginx is running on host, stop it:
sudo systemctl stop apache2  # or nginx
sudo systemctl disable apache2
```

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
* Note the version and release number in the file name and update where noted below.
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
# Note: Script may be named 'installTAK' or 'installTAK.sh' - adjust accordingly
lxc file push installTAK tak/root/        # If no extension
# OR
# lxc file push installTAK.sh tak/root/   # If you renamed it

# (Make sure the tak server file name matches exactly your downloaded version)
# takserver_[#.#]-RELEASE90[##]_all.deb
lxc file push takserver_5.5-RELEASE58_all.deb tak/root/
lxc file push takserver-public-gpg.key tak/root/
lxc file push deb_policy.pol tak/root/

# Make the installer executable (adjust filename if needed)
lxc exec tak -- chmod +x /root/installTAK

# Verify files are in place
lxc exec tak -- ls -lh /root/
```

#### Run the installer from inside the container to avoid path issues
```
# Enter the tak container
lxc exec tak -- bash

# Now you're inside the container - run these commands:
cd /root
./installTAK takserver_5.5-RELEASE58_all.deb
# (Make sure the tak server file name matches exactly your downloaded version)
# takserver_[#.#]-RELEASE90[##]_all.deb

# The installer will ask questions - answer them interactively
```

The installer will prompt you for:

1. **Platform selection** - Choose Ubuntu/Debian
2. **Certificate details**:
   - Country
   - State
   - City
   - Organization 
   - Organizational Unit 
   - Change default Cert password from atakatak?
   - Name for Root CA 
   - Intermediate CA 
4. **Server FQDN** - Enter `tak.[DOMAIN.TLD]`
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

Cert files are located at `/opt/tak/certs/files/` inside the tak container. Enrollment is at root.  Pull them to the host, then download via WinSCP:
```bash
# Pull enrollment package from tak container to host
lxc file pull tak/opt/tak/certs/files/webadmin.p12
lxc file pull tak/enrollmentDP.zip /home/takadmin/

# Now use WinSCP to download enrollmentDP.zip from /home/takadmin/ to your Windows machine
```

You'll distribute this ZIP file to ATAK users for easy connection to your TAK Server.

**Important notes:**
- The installer validates system requirements (8GB+ RAM, disk space)
- Let's Encrypt requires ports 80/443 to be accessible for certificate validation
- If Let's Encrypt fails, the installer will create a local CA instead
- Save the admin certificate password shown during installation

#### Important: Secure Admin Certificate Handling

**Do NOT host `webadmin.p12` on a public web server!**

The `webadmin.p12` certificate provides full administrative access to TAK Server. Store it securely:
```bash
# Pull webadmin.p12 to host (already done)
lxc file pull tak/root/webadmin.p12 ~/
sudo chown takadmin:takadmin ~/webadmin.p12

# Download via WinSCP to your local Windows machine
# Store in a secure location (encrypted drive, password manager)
```

**Distribution to other admins:**
- ✅ Encrypted messaging (Signal, ProtonMail)
- ✅ Password-protected USB drive (in person)
- ✅ Secure file share with encryption (Nextcloud)
- ❌ NEVER via public web server
- ❌ NEVER via unencrypted email
- ❌ NEVER in public GitHub repos

### 5.8 Mission-package generation & onboarding

`installTAK` will create enrollment ZIPs (`enrollmentDP.zip`) that contain `config.pref` and `caCert.p12` which users import into ATAK/WinTAK. Store these in the `web` container for secure download, or hand them out via secure transfer.

**Security note:** Treat `.p12` truststores carefully; they contain CA/private material if misconfigured. Use enrollment flow that supplies only the client truststore (trust anchor) and not private CA keys.

### 5.9 Web container (optional)

Install a simple web server for hosting documentation and enrollment packages.

#### Security Note on Public Enrollment Downloads

**For Testing/Lab Environments:**
Hosting enrollment packages on a public web server is acceptable because:
- TAK Server enforces strong password requirements (16+ characters, mixed case, numbers, special characters)
- Packages are encrypted with user-specific passwords
- Attackers would need the package AND crack a complex password AND have ATAK client

**For Production/High-Security Environments:**
Consider these additional security measures:
- **HTTP Basic Auth** - Add password protection to the `/enroll` directory
- **Private Distribution** - Email packages directly via encrypted channels
- **VPN Requirement** - Require VPN connection to access enrollment downloads
- **One-Time Links** - Generate expiring download URLs per user

**For streamlined user enrollment**, see Section 12 (Future: Automated Enrollment System)

---

#### Install Apache Web Server
```bash
lxc exec web -- apt install -y apache2

# Create directory for enrollment packages
lxc exec web -- mkdir -p /var/www/html/enroll

# Place enrollment packages
lxc file push ~/enrollmentDP.zip web/var/www/html/enroll/

# Set permissions
lxc exec web -- chown -R www-data:www-data /var/www/html/enroll
```

#### Create Landing Page
```bash
lxc exec web -- bash -c 'cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>TAK Server - [DOMAIN.TLD]</title></head>
<body>
<h1>TAK Server Resources</h1>
<ul>
  <li><a href="/enroll/enrollmentDP.zip">Download Default ATAK Enrollment Package</a></li>
  <li><a href="/enroll/webadmin.p12">Download Web Admin Certificate</a></li>
  <li><a href="https://tak.[DOMAIN.TLD]:8443">TAK Server Web UI</a></li>
</ul>
<p><strong>Note:</strong> Enrollment packages are password-protected. Contact your TAK administrator for credentials.</p>
</body>
</html>
EOF'
```

#### Optional: Add HTTP Basic Auth

If you want an additional layer of security:
```bash
# Install auth tools
lxc exec web -- apt install -y apache2-utils

# Create password file
lxc exec web -- htpasswd -c /etc/apache2/.htpasswd [ADMIN_USER]
# Enter password when prompted

# Protect enrollment directory
lxc exec web -- bash -c 'cat > /etc/apache2/conf-available/enroll-auth.conf <<EOF
<Directory /var/www/html/enroll>
    AuthType Basic
    AuthName "TAK Enrollment - Authentication Required"
    AuthUserFile /etc/apache2/.htpasswd
    Require valid-user
</Directory>
EOF'

# Enable and restart
lxc exec web -- a2enconf enroll-auth
lxc exec web -- systemctl restart apache2
```

Now accessing `/enroll/` requires HTTP Basic Auth username/password before downloading files.

#### Verify Web Server
```bash
# Test from host
curl http://10.XXX.XXX.12/

# Test from internet (if DNS configured)
curl http://web.[DOMAIN.TLD]/
```

You should see your landing page HTML.

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
4. Test RTSP pull from MediaMTX using VLC: `rtsp://rtsptak.[DOMAIN.TLD]/camera1`.

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

## 12. Future Enhancements

### 12.1 Automated User Enrollment System

**Goal:** Streamline ATAK client onboarding with self-service enrollment

**Planned Features:**
- Web form for users to request enrollment
- Automated certificate generation
- Email delivery of enrollment packages
- SMS notification option
- User approval workflow for admins
- One-time download links with expiration

**Implementation:** TBD - Will add detailed guide when developed

---

### 12.2 Monitoring & Alerting Stack

**Goal:** Proactive monitoring of TAK Server health

**Planned Components:**
- Prometheus + Grafana dashboards
- Alert on service failures
- Certificate expiration warnings
- Disk space monitoring

**Implementation:** TBD

---

### 12.3 High Availability Setup

**Goal:** Redundant TAK Servers for 24/7 uptime

**Planned Architecture:**
- Multiple TAK server containers
- Database replication
- HAProxy load balancing
- Automatic failover

**Implementation:** TBD

---

*End of TAK-VPS-LXD-DEPLOYMENT-GUIDE.md*

