# TAK Server Installation - Test & Validation Checklist
### Use this while following the Quick Install guide to verify each step.
---

## Pre-Installation Checklist
  - VPS provisioned with Ubuntu 22.04 LTS
  - Can SSH into VPS as root
  - DNS records configured (tak, web, rtsptak → VPS IP)
  - TAK files downloaded from tak.gov
  - installTAK downloaded from your GitHub fork

---
## 5.1 Host Provisioning & Hardening
After running commands, verify:
SSH Access:
```bash
# Open NEW terminal, test SSH as takadmin
ssh takadmin@YOUR_VPS_IP
```
 - Login works without password prompt
 - No errors displayed

Sudo Rights:
```bash
sudo whoami
```
 Output shows: `root`

Root SSH Disabled:
```bash
ssh root@YOUR_VPS_IP
```
 - Connection should be refused or "Permission denied"

Firewall Active:
```bash
sudo ufw status
```
 - Shows "Status: active"
 - Shows rules for: 22/tcp, 80/tcp, 443/tcp, 8089/tcp, 8443/tcp, 8554/tcp

Fail2ban Running:
```bash
sudo systemctl status fail2ban
```
 Shows "active (running)"

LXD Installed:
bashlxd version

 - Shows version 5.x or higher

---
## 5.2 LXD Initialization
LXD Bridge Exists:
```bash
lxc network list
```
 - Shows lxdbr0 with STATE = CREATED
 - Shows IPv4 address (e.g., 10.x.x.1/24)

LXD Storage Pool:
```bash
lxc storage list
```
 - Shows `default` pool with STATE = CREATED

---
## 5.3 Container Creation
Containers Created:
```bash
lxc list
```
 - haproxy - RUNNING
 - tak - RUNNING
 - web - RUNNING
 - rtsptak - RUNNING

Initial State (Before Networking Fix):

 - Containers may show only IPv6 addresses (this is normal)

---
## 5.3b Container Networking Fix
After manual IP assignment:
```bash
lxc list
```
 - haproxy shows: 10.206.248.10
 - tak shows: 10.206.248.11
 - web shows: 10.206.248.12
 - rtsptak shows: 10.206.248.13

DNS Resolution Works:
```bash
lxc exec tak -- nslookup archive.ubuntu.com
```
 - Returns IP addresses (not "connection timed out")

Internet Connectivity:
```bash
lxc exec tak -- ping -c 3 8.8.8.8
```
 - Shows "3 packets transmitted, 3 received, 0% packet loss"

Package Updates Work:
```bash
lxc exec tak -- apt update
```
 - No DNS errors
 - Shows "Reading package lists... Done"

Netplan Applied:
```bash
lxc exec tak -- cat /etc/netplan/10-lxc.yaml
```
 - File exists and shows static IP configuration

Host Firewall Rules:
```bash
sudo iptables -L FORWARD -n | grep lxdbr0
```
 - Shows ACCEPT rules for lxdbr0

---
## 5.4 Container Preparation
Basic Tools Installed:
```bash
lxc exec tak -- which curl
lxc exec tak -- which wget
lxc exec tak -- which vim
```
 - Each command returns a path (e.g., /usr/bin/curl)

---
## 5.5 HAProxy Configuration
HAProxy Installed:
```bash
lxc exec haproxy -- haproxy -v
```
 - Shows HAProxy version 2.x

Config File Exists:
```bash
lxc exec haproxy -- cat /etc/haproxy/haproxy.cfg | head -20
```
 - Shows your custom config (not default)

HAProxy Running:
```bash
lxc exec haproxy -- systemctl status haproxy
```
 - Shows "active (running)"
 - No error messages

HAProxy Listening on Ports:
```bash
lxc exec haproxy -- ss -tulpn | grep haproxy
```
 - Shows listening on: 80, 8089, 8443, 8404, 8554

---
## 5.5b Port Forwarding
Proxy Devices Added:
```bash
lxc config show haproxy | grep -A3 "devices:"
```
 - Shows http, https, tak8089, tak8443, rtsp8554, stats devices

Host Listening on Public Ports:
```bash
sudo ss -tulpn | grep -E ':(80|443|8089|8443|8554|8404)'
```
 - Port 80 - listening (lxd process)
 - Port 443 - listening (lxd process)
 - Port 8089 - listening (lxd process)
 - Port 8443 - listening (lxd process)
 - Port 8554 - listening (lxd process)
 - Port 8404 - listening (lxd process)

External Connectivity Test:
```bash
curl -v http://YOUR_VPS_IP 2>&1 | grep "Connected"
```
 - Shows "Connected to YOUR_VPS_IP"

---
## 5.7 TAK Server Installation
Files Uploaded to Host:
```bash
ls -lh /home/takadmin/
```
 - installTAK (or installTAK.sh)
 - takserver_5.5-RELEASE58_all.deb (~531MB)
 - takserver-public-gpg.key (~1.3KB)
 - deb_policy.pol (~473B)

Files Pushed to Container:
```bash
sudo lxc exec tak -- ls -lh /root/
```
 - All 4 files present
 - installTAK has execute permission (-rwx)

Installer Running:

 - Accepts .deb file signature
 - No immediate errors/aborts

Installation Progress Indicators:

 - `✓ Container networking verified` (LXD mode)
 - `[1/8] Prerequisite Checks Completed`
 - `[2/8] JVM Task Complete`
 - `[3/8] Debian System detected`
 - `[4/8] PostgreSQL and PostGIS Task Complete`
 - `✓ PostgreSQL verified and running` (LXD mode)
 - `[5/8] Java-OpenJDK Task Complete`
 - `[6/8] Installation of takserver.deb Task Complete`
 - Let's Encrypt certificate obtained successfully
 - `✓ TAK Server service is running` (LXD mode)
 - `✓ TAK Server started successfully` (LXD mode)
 - `✓ Enrollment package created: /root/enrollment-default.zip` (LXD mode)
 - `Initialization Complete`

PostgreSQL Running:
```bash
sudo lxc exec tak -- systemctl status postgresql
```
 - Shows "active (running)" or "active (exited)" with cluster active

PostgreSQL Listening:
```bash
sudo lxc exec tak -- ss -tulpn | grep 5432
```
 - Shows listening on 127.0.0.1:5432

TAK Server Service Running:
```bash
sudo lxc exec tak -- systemctl status takserver
```
 - Shows "active (running)" or "active (exited)" with processes running

TAK Processes Active:
```bash
sudo lxc exec tak -- ps aux | grep java
```

 - Shows multiple java processes
 - Includes takserver-messaging, takserver-api, takserver-plugins

TAK Listening on Ports:
```bash
sudo lxc exec tak -- ss -tulpn | grep java
```
 - Port 8089 (client connections)
 - Port 8443 (web UI)
 - Port 9001 (federation)

TAK Server Logs Show Success:
```bash
sudo lxc exec tak -- tail -n 50 /opt/tak/logs/takserver-messaging.log
```
 - Shows "Successfully Started Netty Server for TlsServerInitializer on Port 8089"
 - Shows "Server started"
 - Shows "Started TAK Server messaging Microservice"
 - NO "Connection refused" errors
 - NO "permission denied" errors

Database Connection Working:
```bash
sudo lxc exec tak -- tail -n 100 /opt/tak/logs/takserver-messaging.log | grep -i "database\|postgres"
```
 - No error messages about database connection
 - Shows successful database pool initialization

---
## 5.7b Certificate Retrieval
Files Exist in Container:
```bash
sudo lxc exec tak -- ls -lh /root/*.p12 /root/*.zip
```
 - webadmin.p12 present (~4.6KB)
 - enrollment-default.zip present (varies)

Files Pulled to Host:
```bash
ls -lh ~/webadmin.p12 ~/enrollment-default.zip
```
 - Both files present
 - Owned by takadmin:takadmin

Downloaded to Windows:

 - webadmin.p12 downloaded via WinSCP
 - enrollment-default.zip downloaded via WinSCP
 - Files are not corrupted (can open .zip, see .p12)

---
## 5.8 Web UI Access
Certificate Import:

 - webadmin.p12 imported to Windows certificate store
 - Import used "Automatically select certificate store" option
 - No import errors
 - Browser restarted after import

Certificate Visible in Browser:

 - Settings → Certificates → Personal certificates shows webadmin cert
 - Certificate shows valid dates
 - Issued to: webadmin
 - Issued by: Your Intermediate CA name

External Access Test:
```bash
curl -v https://tak.pinenut.tech:8443 2>&1 | grep "Connected"
```
 - Shows "Connected to tak.pinenut.tech"
 - May show SSL handshake errors (normal without client cert)

Web UI Accessible:

 - Navigate to: https://tak.pinenut.tech:8443
 - Browser prompts to select certificate (webadmin)
 - Certificate accepted
 - TAK Server dashboard loads
 - No certificate errors
 - Can see "TAK Server" title/logo

Web UI Functions:

 - Left sidebar navigation works
 - "Missions" page loads
 - "Data Packages" page loads
 - No JavaScript errors in browser console

---
## 5.9 User Enrollment (Optional Test)
Create Test User Certificate:
```bash
sudo lxc exec tak -- bash -c "cd /opt/tak/certs && ./makeCert.sh client testuser"
```
 - Certificate created without errors
 - Shows "Certificate request self-signature ok"

Create Enrollment Package:
```bash
sudo lxc exec tak -- bash -c "cd /opt/tak/certs/files && zip /root/enrollment-testuser.zip testuser.p12 truststore-root.p12"
```
 - ZIP created successfully
 - Shows "adding: testuser.p12" and "adding: truststore-root.p12"

Retrieve Package:
```bash
sudo lxc file pull tak/root/enrollment-testuser.zip ~/
sudo chown takadmin:takadmin ~/enrollment-testuser.zip
```
 - File pulled successfully
 - File is downloadable via WinSCP

---
## 5.10 MediaMTX (Optional)
MediaMTX Installed:
```bash
lxc exec rtsptak -- ls -lh /opt/mediamtx/mediamtx
```
 - Binary exists and is executable

Service Running:
```bashl
xc exec rtsptak -- systemctl status mediamtx
```
 - Shows "active (running)"

MediaMTX Listening:
```bash
lxc exec rtsptak -- ss -tulpn | grep 8554
```
 - Shows listening on 8554

HAProxy Backend Accessible:

 - Port 8554 forwarded from host
 - Can test with: curl -v rtsp://rtsptak.pinenut.tech:8554 (will timeout but shows connection)

---
### Overall System Health
All Containers Running:
```bash
lxc list
```
 - All 4 containers show RUNNING state
 - All have IPv4 addresses

Host Resource Usage:
```bash
free -h
df -h
```
 - Sufficient free memory (4GB+ recommended)
 - Sufficient disk space (20GB+ free)

No Critical Errors in Logs:
```bash
sudo journalctl -xe --no-pager | tail -50
```
 - No critical system errors
 - No LXD errors

DNS Resolution from External:
```bash
# From your local machine (not VPS)
nslookup tak.pinenut.tech
nslookup web.pinenut.tech
nslookup rtsptak.pinenut.tech
```
 - All resolve to your VPS IP
 - No NXDOMAIN errors

---
### Final Smoke Tests
TAK Server End-to-End:

 - Can access https://tak.pinenut.tech:8443 in browser
 - Dashboard loads completely
 - Can navigate to different sections
 - No certificate warnings
 - enrollment-default.zip can be extracted
 - Contains .p12 files

ATAK Client Test (If Available):

 - Import enrollment-default.zip into ATAK
 - ATAK connects to server
 - Self-SA appears on map
 - No connection errors

Performance Test:
```bash
# Check TAK Server response time
time curl -k https://localhost:8443 -I
```
 - Response time under 2 seconds

---
## Troubleshooting Decision Tree
### If TAK Server won't start:

1. Check: `sudo lxc exec tak -- systemctl status takserver`
2. Check: `sudo lxc exec tak -- tail -100 /opt/tak/logs/takserver-messaging.log`
Common issues:

- PostgreSQL not running → See PostgreSQL checks above
- Database connection errors → Check PostgreSQL permissions
- Certificate errors → Verify Let's Encrypt succeeded



If Web UI not accessible:

1. Check: External connectivity test passed?
2. Check: Certificate imported correctly?
3. Check: Using domain name (not IP)?
4. Check: HAProxy port forwarding configured?

If containers have no IPv4:

1. Return to Section 5.3b
2. Verify host firewall rules
3. Check netplan configuration
4. Restart containers: `lxc restart CONTAINER`

---
## Success Criteria Summary
### Minimum for "Successful Install":

 - All 4 containers running with IPv4 addresses
 - TAK Server service active and logs show "Started TAK Server"
 - Can access https://tak.pinenut.tech:8443 with webadmin.p12
 - Dashboard fully loads and is functional
 - enrollment-default.zip created and downloadable

Bonus (Nice to Have):

 - ATAK client successfully connects
 - MediaMTX installed and running
 - Snapshots taken of working configuration
 - Additional user enrollments work

---
If all checks pass: ✅ Installation successful!
If 80%+ checks pass: ⚠️ Mostly working, minor issues to fix
If <80% checks pass: ❌ Major issues, review failed sections
