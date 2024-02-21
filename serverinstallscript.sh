#!/bin/bash
##This will install Tak V5.0 on Rocky Linux 8, create a Root CA and Intermediate (signing) CA, enable certificate enrollment, enable channels, and create an admin and user .p12 certificate
##The /opt/tak/certs/files/admin.p12 certificate needs to be installed into firefox/chrome as a user certificate in order to conenct to the WebGUI as an admin

echo "Create atak user"
sudo useradd -m -p atak wolfTAK atak
sudo -aG wheel atak

echo "Increase MAX connections"
echo -e"* soft nofile 32768\n* hard nofile 32768" |sudo  tee --append /etc/security/limits.conf>/dev/null

echo "Install epel-release"
sudo yum install epel-release -y
echo "Install epel-release complete"

echo "Install Nano"
sudo yum install nano -y
echo "Install Nano complete"

echo "Install Postgres"
sudo yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
echo "Install Postgres Complete"

echo "Update Packages"
sudo dnf update -y
echo "Update Complete"

echo "Install Java 17"
# Install Java 17
sudo yum install java-17-openjdk-devel -y
echo "Install Java 17 complete"

echo "Install Python and PIP"
sudo yum install python39 -y
sudo yum install python39-pip
sudo pip3 install --upgrade pip

wait

echo "Install GDown"

pip install gdown

echo "Google Drive TAK Server rpm download"
gdown [DRIVE-TAKSERVER-FILE-ID] 

echo "Google Drive gpg key download"
gdown [DRIVE-GPG KEY-FILE-ID] 

echo "Google Drive takusercreatecerts script download"
gdown [DRIVE-CREATEUSERSSCRIPT-FILE-ID] 

echo "Google Drive createtakcerts script download"
gdown [DRIVE-CREATECERTSSCRIPT-FILE-ID] 

echo "Google Drive createletsencryptcerts download"
gdown [DRIVE-CREATELECERTSSCRIPT-FILE-ID] 

echo "Begin install of TAK Server"
cd
sudo yum install takserver-5.0-RELEASE34.noarch.rpm -y

echo "Policy install"
sudo yum install checkpolicy
cd /opt/tak
sudo ./apply-selinux.sh
sudo semodule -l | grep takserver

echo "Configuring TAK database"
sudo /opt/tak/db-utils/takserver-setup-db.sh
echo "daemon-reload"
sudo systemctl daemon-reload

#echo "Move cert-metadata.sh file to /opt/tak/certs"
#cd
#sudo mv -f ./TAK-Server/cert-metadata.sh /opt/tak/certs/cert-metadata.sh

echo "Start TAK Server Service"
sudo systemctl start takserver

echo "Enable TAK Server auto-start"
sudo systemctl enable takserver

echo "Install Firewalld"
sudo yum install firewalld
sudo systemctl start firewalld
sudo systemctl enable firewalld
sudo systemctl status firewalld

echo "Configure Firewalld"
sudo firewall-cmd --zone=public --permanent --add-port=8089/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8443/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8446/tcp
sudo firewall-cmd --reload

echo "Install Complete, creating tak certificates!!"
echo "copying certificate scripts to correct locations"
cp createTakCerts.sh /opt/tak/certs
cp takUserCreateCerts_doNotRunAsRoot.sh /opt/tak/certs
cp takserver_createLECerts.sh /opt/tak/certs

##allow script execution
sudo chmod +x /opt/tak/certs/createTakCerts.sh
sudo chmod +x /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh
sudo chmod +x /opt/tak/certs/takserver_createLECerts.sh

echo "running certificate script"
sudo /opt/tak/certs/createTakCerts.sh
