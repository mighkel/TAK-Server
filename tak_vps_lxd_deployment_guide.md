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
   - Create containers: haproxy, tak, web, media
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

- Multi-container LXD layout: `haproxy`, `tak`, `web`, `media`.
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
                 +--- media (MediaMTX for RTSP/SRT feeds)
```

Ports published on the host are NAT'd or forwarded to haproxy — haproxy routes connections to appropriate containers (TCP passthrough for TAK ports, HTTP for web, RTSP TCP/UDP to media).

---

## 3. Prerequisites (host & LXD)

- SSDNodes VPS running Ubuntu 22.04 LTS (minimal install). Make sure you can SSH in.
- Domain name with DNS A records for `tak.example.tld`, `web.example.tld`, `rtsp.example.tld` pointing to the VPS public IP.
- LXD installed (snap) and basic knowledge of `lxc` commands. This guide uses `lxd`/`lxc` commands.
- You already have `installTAK` (myTeckNet) files; place them where the guide indicates (we show commands to copy into the tak container).

---

## 4. High-level deployment steps

1. Provision host, create admin user, add SSH key, disable root password auth.
2. Install and initialize LXD; create an LXD bridge or use `lxdbr0`.
3. Launch containers: `haproxy`, `tak`, `web`, `media`.
4. Configure container networking and firewall rules (host ufw and container ufw where applicable).
5. Configure HAProxy and Certbot for TLS (or let `installTAK` manage LetsEncrypt inside TAK container as preferred).
6. Install TAK Server inside `tak` container using myTeckNet `installTAK` script.
7. Configure MediaMTX inside `media` container and add HAProxy routing for RTSP.
8. Snapshot containers and configure backup cron jobs.

---

## 5. Detailed step-by-step

> All commands assume you are root on the host or using `sudo`.

### 5.1 Host provisioning & hardening (Ubuntu 22.04)

```bash
# Update & basic tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip lxd snapd ufw fail2ban

# Create admin user (if not already created), add to sudo
sudo adduser adminuser
sudo usermod -aG sudo adminuser
# Add your public SSH key to /home/adminuser/.ssh/authorized_keys

# Disable root SSH and password auth (edit /etc/ssh/sshd_config)
sudo sed -i "s/^#*PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo systemctl reload sshd

# UFW: basic host firewall (allow SSH from your IP only ideally)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
# Allow HTTP/HTTPS for cert issuance & public pages
sudo ufw allow http
sudo ufw allow https
# Allow TAK client ports if you want haproxy to receive them
sudo ufw allow 8089/tcp
sudo ufw allow 8443/tcp
# Allow RTSP (if you plan to proxy TCP) - we'll proxy via haproxy
sudo ufw allow 554/tcp

sudo ufw enable

# Fail2ban: basic install
sudo systemctl enable --now fail2ban
```

Notes:
- If you lock yourself out, use VPS console from SSDNodes to recover. Consider limiting SSH to your office/home IP.
- You can further harden by creating an SSH bastion, but you're intentionally keeping onboarding friendly.

### 5.2 Install and initialize LXD

```bash
# Install LXD via snap
sudo snap install lxd
sudo lxd init --auto
# The --auto initialises with defaults (lxdbr0). You can re-run `sudo lxd init` to customize storage/backing.
```

If you prefer bridged networking (bridge to host interface for public IPs), re-run `sudo lxd init` interactively and choose a bridged profile.

### 5.3 Create containers (Ubuntu 22.04 images)

We'll create 4 containers. Adjust names to your naming standard.

```bash
lxc launch images:ubuntu/22.04 haproxy
lxc launch images:ubuntu/22.04 tak
lxc launch images:ubuntu/22.04 web
lxc launch images:ubuntu/22.04 media
```

Check IPs:

```bash
lxc list
```

Record the containers' internal IPs (e.g. 10.13.x.x) — we'll use them in HAProxy config.

### 5.4 Prepare containers (common steps)

Run these for each container (`haproxy`, `tak`, `web`, `media`). Replace `CONTAINER` with the container name.

```bash
lxc exec CONTAINER -- bash -c "apt update && apt upgrade -y"
# create admin user inside container to match host sudo user (optional)
lxc exec CONTAINER -- useradd -m -s /bin/bash adminuser || true
lxc exec CONTAINER -- bash -c "mkdir -p /home/adminuser/.ssh && chown adminuser:adminuser /home/adminuser/.ssh"
# copy your public key from host
lxc file push ~/.ssh/id_rsa.pub CONTAINER/home/adminuser/.ssh/authorized_keys --mode=0600
lxc exec CONTAINER -- chown adminuser:adminuser /home/adminuser/.ssh/authorized_keys

# Install basic utilities in container
lxc exec CONTAINER -- apt install -y vim curl wget unzip ufw
# Enable UFW inside container if you want per-container firewalling
lxc exec CONTAINER -- ufw allow ssh && lxc exec CONTAINER -- ufw enable
```

### 5.5 HAProxy container: install & full config

`haproxy` is the single public-facing reverse proxy. We'll install HAProxy and configure SNI/TCP passthrough for TAK and RTSP.

```bash
lxc exec haproxy -- apt install -y haproxy certbot
```

Now create `/etc/haproxy/haproxy.cfg` inside the `haproxy` container with the contents below. Use `lxc file push` or `lxc exec haproxy -- tee /etc/haproxy/haproxy.cfg <<'EOF'` to write it.

**Full HAProxy config (example)** — adjust domain names and backend IPs to your `lxc list` values.

```
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

# HTTP frontend for web UI (optional)
frontend http-in
    bind *:80
    mode http
    acl host_web hdr(host) -i web.example.tld
    use_backend web-backend if host_web
    default_backend web-backend

backend web-backend
    mode http
    server web1 10.13.240.56:80

# HTTPS SNI passthrough for TAK client (TCP/SSL) on 8089
frontend tak-client
    bind *:8089
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    acl host_tak req.ssl_sni -i tak.example.tld
    use_backend tak-client-backend if host_tak

backend tak-client-backend
    mode tcp
    option ssl-hello-chk
    server tak 10.13.240.149:8089

# TAK server Web UI (HTTPS) on 8443 - passthrough
frontend tak-server
    bind *:8443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    acl host_takreq req.ssl_sni -i tak.example.tld
    use_backend tak-server-backend if host_takreq

backend tak-server-backend
    mode tcp
    option ssl-hello-chk
    server takweb 10.13.240.149:8443

# RTSP frontend (TCP) for MediaMTX, example on port 554
frontend rtsp-in
    bind *:554
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    acl host_rtsp req.ssl_sni -m found # SNI not used by RTSP; we match on IP/port here
    default_backend media-backend

backend media-backend
    mode tcp
    option tcplog
    server media 10.13.240.178:8554 check

# Optionally add a stats endpoint
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy_stats
    stats auth admin:YourStrongPassword
```

Notes:
- HAProxy is configured for TCP passthrough for TAK and RTSP. This lets TLS be terminated inside the TAK and Media containers (or you can terminate TLS in HAProxy; choose one).
- If you prefer HAProxy to terminate TLS (recommended for central cert management), change `mode tcp` to `mode http` for HTTP frontends and add `bind *:443 ssl crt /etc/letsencrypt/live/domain/fullchain.pem` lines.

After you write the config, restart HAProxy:

```bash
lxc exec haproxy -- systemctl restart haproxy
lxc exec haproxy -- systemctl enable haproxy
```

### 5.6 TLS / Let’s Encrypt strategy

Two valid strategies:

A. **Certbot inside the TAK container (myTeckNet installer supports this)** — `installTAK` will request certs, convert them to JKS and hook them into TAK. This is handy if you want the TAK container to manage its own certs.

B. **Central TLS at HAProxy** — HAProxy handles Let's Encrypt certs and terminates TLS. TAK is then behind HAProxy using HTTP/TCP without needing Let's Encrypt inside the tak container.

**Recommendation:** Start with option A (let `installTAK` manage certs) since you already have the script set up and it auto-creates mission-packages. Later move TLS termination into HAProxy if you want a single point of cert management.

If using HAProxy termination, install certbot on the `haproxy` container and configure a renewal hook that reloads HAProxy after cert renewal.

### 5.7 Install TAK Server inside `tak` container (myTeckNet installTAK)

#### Copy installTAK files into the tak container

On host, assuming you downloaded/unzipped `installTAK` into `~/installTAK`:

```bash
# Push the repository to tak container
lxc file push -r ~/installTAK tak/root/installTAK
# or push the single installer script
lxc file push ~/installTAK/installTAK.sh tak/root/installTAK.sh

# Exec into container and run installer
lxc exec tak -- bash -lc "cd /root/installTAK && chmod +x installTAK && ./installTAK ."
# If it is the .txt you uploaded as installTAK.txt, rename to executable
lxc exec tak -- bash -lc "cd /root && mv installTAK.txt installTAK && chmod +x installTAK && ./installTAK ./TAKServer-*.deb"
```

A few important notes about `installTAK` (myTeckNet):
- It validates prerequisites (Java, PostgreSQL/PostGIS, etc.) and will abort if minimal RAM < 8GB.
- It supports generating a CA, intermediate CA, server JKS, and client certs; it can also request Let's Encrypt certs and create JKS keystore for TAK.
- The script creates mission-package enrollment ZIP files (`enrollmentDP.zip`) for easy ATAK onboarding.

Follow the interactive prompts. Typical flow:
1. Choose platform (Ubuntu/Debian)
2. Provide certificate properties, choose Let’s Encrypt or local CA.
3. Select SSL vs QUIC connectors
4. Choose to enable federation or not
5. Create admin cert, enrollment packages

After install, ensure TAK service is running:

```bash
lxc exec tak -- systemctl status takserver.service
# check logs
lxc exec tak -- tail -n 200 /opt/tak/logs/takserver-messaging.log
```

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

MediaMTX is an actively maintained RTSP server that serves RTSP/RTMP/SRT feeds. We'll set it up in `media` container.

```bash
# On host, download latest MediaMTX release or use package in container
lxc exec media -- bash -lc "apt update && apt install -y curl vim"
# Create a directory and download binary
lxc exec media -- mkdir -p /opt/mediamtx
# If you have the binary locally: lxc file push mediamtx binary path
# Example to download inside container (replace URL with latest):
lxc exec media -- bash -lc "cd /opt/mediamtx && curl -L -o mediamtx.tar.gz 'https://github.com/aler9/mediamtx/releases/download/v0.XX.X/mediamtx_v0.XX.X_linux_amd64.tar.gz' && tar xzf mediamtx.tar.gz"

# create systemd service
lxc exec media -- bash -lc "cat >/etc/systemd/system/mediamtx.service <<'EOF'\n[Unit]\nDescription=MediaMTX\nAfter=network.target\n\n[Service]\nUser=root\nExecStart=/opt/mediamtx/mediamtx\nRestart=on-failure\n\n[Install]\nWantedBy=multi-user.target\nEOF"
lxc exec media -- systemctl daemon-reload && systemctl enable --now mediamtx
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
for CT in tak haproxy web media; do
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
4. Test RTSP pull from MediaMTX using VLC: `rtsp://rtsp.example.tld/camera1`.

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
- `containers/` — `haproxy/`, `tak/`, `web/`, `media/` subfolders with `Dockerfile`-like configs or `cloud-init` userdata for containers
- `installTAK/` — your copy of `installTAK` and local `answers.txt` for unattended install
- `secrets.example` (NOT actual secrets) — template for where to place CA password, domain names
- `backup/` — backup & restore scripts

**Public repo (helpful for others)** — contents:

- `README.md` — high-level guide (sanitized)
- `lxd-commands.md` — step-by-step LXD commands (no secrets)
- `haproxy/` — example haproxy.cfg (with placeholders)
- `media/` — MediaMTX example config
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

- [ ] Get DNS set for `tak`,`web`,`rtsp` subdomains
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

