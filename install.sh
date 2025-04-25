#!/bin/bash

# Usage: sudo ./setup_openvpn.sh [client_name]
CLIENT_NAME=${1:-client1}

# VPN network settings
VPN_NET="10.8.0.0"
VPN_MASK="255.255.255.0"

# OpenVPN listens on port 443/TCP by default
PORT=443
PROTO=tcp

# Detect public IP
SERVER_IP=$(curl -s https://ipinfo.io/ip)

# 1) Install packages
sudo apt update
sudo apt install -y openvpn easy-rsa ufw curl

# 2) Easy-RSA PKI setup
echo "==> Setting up PKI..."
make-cadir ~/openvpn-ca
cd ~/openvpn-ca
source vars
./clean-all
yes "" | ./build-ca
yes "" | ./build-key-server server
./build-dh
echo "==> Generating TLS auth key..."
openvpn --genkey --secret keys/ta.key
yes "" | ./build-key "$CLIENT_NAME"

# 3) Copy certs & keys to /etc/openvpn
echo "==> Copying keys to /etc/openvpn..."
sudo cp keys/ca.crt /etc/openvpn/
sudo cp keys/server.crt /etc/openvpn/
sudo cp keys/server.key /etc/openvpn/
sudo cp keys/dh2048.pem /etc/openvpn/
sudo cp keys/ta.key /etc/openvpn/

# 4) Generate server.conf with absolute paths and modern ciphers
echo "==> Writing server.conf..."
sudo tee /etc/openvpn/server.conf > /dev/null <<EOF
port $PORT
proto $PROTO
dev tun

# PKI
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh2048.pem

# TLS auth
tls-auth /etc/openvpn/ta.key 0
auth SHA256

# Network
topology subnet
server $VPN_NET $VPN_MASK
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"

# Keepalive
keepalive 10 120

# Ciphers (modern & fallback)
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-CBC

# Permissions
user nobody
group nogroup
persist-key
persist-tun

status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
EOF

# 5) Enable IPv4 forwarding
echo "==> Enabling IP forwarding..."
sudo sed -i '/^#net.ipv4.ip_forward=1/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
sudo sysctl -p

# 6) UFW firewall rules & NAT
echo "==> Configuring UFW..."
sudo ufw allow OpenSSH
sudo ufw allow $PORT/$PROTO
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

sudo sed -i '1i\
# START OPENVPN RULES\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s $VPN_NET/$VPN_MASK -o eth0 -j MASQUERADE\nCOMMIT\n# END OPENVPN RULES\n' /etc/ufw/before.rules

sudo ufw disable && sudo ufw enable

# 7) Start & enable OpenVPN service
echo "==> Starting OpenVPN..."
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server

# 8) Prepare client config generator
echo "==> Generating client .ovpn..."
mkdir -p ~/client-configs/files
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/base.conf

# Tweak client template for absolute paths & TCP/443
sed -i "s|^remote .*|remote $SERVER_IP $PORT|" ~/client-configs/base.conf
sed -i 's/^proto.*/proto '"$PROTO"'/' ~/client-configs/base.conf
echo "key-direction 1" >> ~/client-configs/base.conf

echo '#!/bin/bash
KEY_DIR=/etc/openvpn
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf
cat "${BASE_CONFIG}" \
    <(echo -e "<ca>") \
    "${KEY_DIR}/ca.crt" \
    <(echo -e "</ca>\n<cert>") \
    "${KEY_DIR}/${CLIENT_NAME}.crt" \
    <(echo -e "</cert>\n<key>") \
    "${KEY_DIR}/${CLIENT_NAME}.key" \
    <(echo -e "</key>\n<tls-auth>") \
    "${KEY_DIR}/ta.key" \
    <(echo -e "</tls-auth>") \
    > "${OUTPUT_DIR}/${CLIENT_NAME}.ovpn"' \
> ~/client-configs/make_config.sh

chmod +x ~/client-configs/make_config.sh
~/client-configs/make_config.sh

echo "\n✅ OpenVPN is now running on $PORT/$PROTO"
echo "📄 Client profile: ~/client-configs/files/$CLIENT_NAME.ovpn"
