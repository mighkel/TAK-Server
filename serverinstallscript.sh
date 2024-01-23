#!/bin/bash
# Update OS
sudo yum update -y

# Increase system limit for number of concurrent TCP connections
echo -e"* soft nofile 32768\n* hard nofile 32768" |sudo  tee --append /etc/security/limits.conf>/dev/null

# Install EPEL
sudo yum install epel-release -y

# Install Nano
sudo dnf install nano -y

# Install PostgreSQL and PostGIS packages
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Update
sudo dnf update -y

# Enable PowerTools
sudo dnf config-manager --set-enabled powertools

# Disable system default PostgreSQL
sudo dnf -qy module disable postgresql

echo "If prompted, press y and then enter to import the GPG key"

# Install PostgreSQL 15
sudo dnf install -y postgresql15-server

# Install Java 17
sudo yum install java-17-openjdk-devel -y

# Install Python and PIP
sudo dnf install python39 -y

sudo dnf install python39-pip

# Upgrade PIP
sudo pip3 install --upgrade pip

wait

# Install GDown

pip install gdown

# Begin Google Drive TAK Server rpm download

gdown 1-lYWLTCblFbPmJkqDAwPolu6ZkkL4ISg 

# Begin Google Drive TAK Server public gpg key download

gdown 151lKtT1xfj8lyeZJ8VMRyxgK1X8-8CVv 


# Begin install of TAK Server
cd
sudo yum install takserver-5.0-RELEASE34.noarch.rpm -y

# Policy install

sudo yum install checkpolicy
cd /opt/tak
sudo ./apply-selinux.sh
sudo semodule -l | grep takserver

# Database install

sudo /opt/tak/db-utils/takserver-setup-db.sh
sudo systemctl daemon-reload

# Move cert-metadata.sh file to /opt/tak/certs

# cd

# sudo mv -f ./TS-Install/cert-metadata.sh /opt/tak/certs/cert-metadata.sh

# Start TAK Server Service

sudo systemctl start takserver

# Enable TAK Server auto-start

sudo systemctl enable takserver

# Install Firewalld

sudo yum install firewalld
sudo systemctl start firewalld
sudo systemctl enable firewalld
sudo systemctl status firewalld

# Configure Firewalld

sudo firewall-cmd --zone=public --add-port 8080/tcp --permanent
sudo firewall-cmd --zone=public --add-port 8088/tcp --permanent
sudo firewall-cmd --zone=public --add-port 8089/tcp --permanent
sudo firewall-cmd --zone=public --add-port 8443/tcp --permanent
sudo firewall-cmd --zone=public --add-port 8444/tcp --permanent
sudo firewall-cmd --zone=public --add-port 8446/tcp --permanent
sudo firewall-cmd --zone=public --add-port 9000/tcp --permanent
sudo firewall-cmd --zone=public --add-port 9001/tcp --permanent
sudo firewall-cmd --reload

echo "********** INSTALLATION COMPLETE! **********"
echo ""
echo "**** CHECK NOBODY IS OVER YOUR SHOULDER ****"
echo ""
echo "Access your your TAK server via web browser"
echo ""
echo "http://[TAK Server IP]:8080/setup for initial setup"
echo "|"
echo "http://[TAK Server IP]:8446 unsecure connection"
echo "|"
echo " ---> requires admin account creation"
echo ""
echo "http://[TAK Server IP]:8443 secure connection"
echo "|"
echo " ---> requires certificate creation"
echo "|"
echo "Password must be a minimum of 15 characters including 1 uppercase, 1 lowercase, 1 number, and 1 special character from this list [-_!@#$%^&*(){}[]+=~`|:;<>,./?]."
echo "|"
echo "sudo java -jar /opt/tak/utils/UserManager.jar usermod -A -p [create password] [adminusername]"
echo "|"
echo "sudo systemctl restart takserver"
