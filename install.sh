#!/bin/bash

set -e

# === CONFIGURABLE VARIABLES ===
USERNAME="vpnuser123"
USER_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9@#%!' | head -c 16)
ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9@#%!' | head -c 16)
PSK=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9@#%!' | head -c 20)
CUSTOM_PORT=4443
HUB_NAME="MYHUB"

# === DEPENDENCIES ===
apt update && apt install -y build-essential libreadline-dev libssl-dev libncurses5-dev zlib1g-dev ufw

# === DOWNLOAD & COMPILE ===
wget -O softether.tar.gz https://www.softether-download.com/files/softether/v4.44-9807-rtm-2025.04.16-tree/Linux/SoftEther_VPN_Server/64bit_-_Intel_x64_or_AMD64/softether-vpnserver-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz
tar xzf softether.tar.gz
cd vpnserver
yes 1 | make
cd ..
mv vpnserver /usr/local/
chmod 600 /usr/local/vpnserver/*
chmod 700 /usr/local/vpnserver/vpncmd /usr/local/vpnserver/vpnserver

# === SYSTEMD SERVICE ===
cat <<EOF > /etc/systemd/system/vpnserver.service
[Unit]
Description=SoftEther VPN Server
After=network.target

[Service]
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStop=/usr/local/vpnserver/vpnserver stop
Type=forking

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable vpnserver
systemctl start vpnserver

# === VPN CONFIGURATION ===
vpncmd="/usr/local/vpnserver/vpncmd localhost /SERVER"

$vpncmd /CMD ServerPasswordSet $ADMIN_PASSWORD
$vpncmd /PASSWORD:$ADMIN_PASSWORD /CMD HubCreate $HUB_NAME /PASSWORD:hubpass
$vpncmd /PASSWORD:$ADMIN_PASSWORD /HUB:$HUB_NAME /CMD UserCreate $USERNAME
$vpncmd /PASSWORD:$ADMIN_PASSWORD /HUB:$HUB_NAME /CMD UserPasswordSet $USERNAME /PASSWORD:$USER_PASSWORD
$vpncmd /PASSWORD:$ADMIN_PASSWORD /HUB:$HUB_NAME /CMD SecureNatEnable
$vpncmd /PASSWORD:$ADMIN_PASSWORD /CMD IPsecEnable /L2TP:yes /L2TPRAW:yes /ETHERIP:no /PSK:$PSK /DEFAULTHUB:$HUB_NAME
$vpncmd /PASSWORD:$ADMIN_PASSWORD /CMD SstpEnable yes
$vpncmd /PASSWORD:$ADMIN_PASSWORD /CMD ListenerCreate $CUSTOM_PORT
$vpncmd /PASSWORD:$ADMIN_PASSWORD /CMD ListenerDelete 443

# === FIREWALL ===
ufw allow $CUSTOM_PORT/tcp || true

# === DONE ===
echo -e "\n✅ SoftEther VPN Installed Securely!"
echo "Admin Password:  $ADMIN_PASSWORD"
echo "VPN Username:    $USERNAME"
echo "VPN Password:    $USER_PASSWORD"
echo "L2TP/IPSec PSK:  $PSK"
echo "VPN Hub:         $HUB_NAME"
echo "Custom Port:     $CUSTOM_PORT"
