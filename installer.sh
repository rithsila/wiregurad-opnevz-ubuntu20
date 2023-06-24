#!/bin/bash

#Variables
IP=$(hostname -I | awk '{print $1}')
SslKeyPath='/etc/nginx/ssl/priv.key'
SslCertPath='/etc/nginx/ssl/ssl.crt'
UiScreen=$(screen -ls | grep Detached | awk '{print $1}')
PasswordGenerator=$(tr -dc '[:alnum:]' < /dev/urandom | head -c 15)
now=$(date +'%Y-%m-%dT%H:%M:%S.%NZ')
PresharedKeyGen=$(openssl rand -base64 32)
export DEBIAN_FRONTEND=noninteractive

#Set proper mirrors
mv /etc/apt/sources.list /etc/apt/sources.list_backup
tee /etc/apt/sources.list <<EOF
deb https://mirrors.neterra.net/ubuntu/ focal main restricted universe
deb https://mirrors.neterra.net/ubuntu/ focal-updates main restricted universe
deb https://mirrors.neterra.net/ubuntu/ focal-security main restricted universe multiverse
deb http://archive.canonical.com/ubuntu focal partner
EOF

#Update software and install required packages
apt-get -yq --allow-releaseinfo-change update
apt-get -y install curl nginx
apt-get -y install golang-go
apt-get -y install wireguard-tools

#Install BoringTun
wget -P /usr/local/bin https://boringtun.hannobraun.de/releases/boringtun-0.2.0-x86_64-linux.tar.gz
tar -xf /usr/local/bin/boringtun-0.2.0-x86_64-linux.tar.gz -C /usr/local/bin
mv /usr/local/bin/boringtun-0.2.0-x86_64-linux/boringtun /usr/local/bin/boringtun
chmod +x /usr/local/bin/boringtun
rm -rf /usr/local/bin/boringtun-0.2.0-x86_64-linux.tar.gz

#Install WireGuard UI
wget -P /usr/local/src/ui https://github.com/ngoduykhanh/wireguard-ui/releases/download/v0.14.0/wireguard-ui-linux-amd64
mv /usr/local/src/ui/wireguard-ui-linux-amd64 /usr/local/src/ui/wireguard-ui
chmod +x /usr/local/src/ui/wireguard-ui

#Cleaning after the installation
apt-get clean

#Generate SSL key and certificate
mkdir /etc/nginx/ssl
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj "/C=US/ST=State/L=City/O=Organization/CN=$IP" -keyout "$SslKeyPath" -out "$SslCertPath"

#Configure Nginx reverse proxy
tee /etc/nginx/sites-available/ui.conf <<EOF
server {
    listen 7654 ssl;
    server_name $IP;

    ssl_certificate $SslCertPath;
    ssl_certificate_key $SslKeyPath;

    location / {
        proxy_pass http://127.0.0.1:5000;
    }
}
EOF

ln -s /etc/nginx/sites-available/ui.conf /etc/nginx/sites-enabled/ui.conf
rm -rf /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

#Start WireGuard and Nginx services
systemctl enable --now wg-quick@wg0.service
systemctl enable --now nginx.service

#Configure SSH
sed -i 's/#Port 22/Port 22000/g' /etc/ssh/sshd_config
systemctl restart sshd

#Remove unnecessary packages
apt-get -y purge tcpdump telnet exim4* apache2* python* libpython* pwgen
apt-get -y autoremove
apt-get -y clean

#Reboot the system
reboot
