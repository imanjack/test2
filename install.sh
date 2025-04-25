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
make-cadir ~/openvpn-ca
cd ~/openvpn-ca
source vars
./clean-all
yes "" | ./build-ca
yes "" | ./build-key-server server
./build-dh
openvpn --genkey --secret keys/ta.key
yes "" | ./build-key "$CLIENT_NAME"

# 3) Copy certs & keys to /etc/openvpn
sudo cp keys/{ca.crt,server.crt,server.key,ta.key,dh2048.pem} /etc/openvpn/

# 4) Generate server.conf
sudo tee /etc/openvpn/server.conf > /dev/null <<EOF
port $PORT
proto $PROTO
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh2048.pem
auth SHA256
tls-auth ta.key 0
topology subnet
server $VPN_NET $VPN_MASK
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF

# 5) Enable IPv4 forwarding
sudo sed -i '/^#net.ipv4.ip_forward=1/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
sudo sysctl -p

# 6) UFW firewall rules & NAT
# Allow SSH and OpenVPN port
sudo ufw allow OpenSSH
sudo ufw allow $PORT/$PROTO

# Enable forwarding in UFW config
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

# Insert NAT rules for VPN subnet into before.rules
sudo sed -i '1i\
# START OPENVPN RULES\n\
*nat\n\
:POSTROUTING ACCEPT [0:0]\n\
-A POSTROUTING -s '"$VPN_NET/$VPN_MASK"' -o eth0 -j MASQUERADE\n\
COMMIT\n\
# END OPENVPN RULES\n' /etc/ufw/before.rules

# Reload UFW to apply changes
sudo ufw disable
sudo ufw enable

# 7) Start & enable OpenVPN service
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server

# 8) Prepare client config generator
mkdir -p ~/client-configs/files
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/base.conf

# Tweak client template
sed -i "s/^remote .*/remote $SERVER_IP $PORT/" ~/client-configs/base.conf
sed -i 's/;proto .*/proto '"$PROTO"'/' ~/client-configs/base.conf
sed -i 's/;user nobody/user nobody/' ~/client-configs/base.conf
sed -i 's/;group nogroup/group nogroup/' ~/client-configs/base.conf
sed -i 's/ca ca.crt/#ca ca.crt/' ~/client-configs/base.conf
sed -i 's/cert client.crt/#cert client.crt/' ~/client-configs/base.conf
sed -i 's/key client.key/#key client.key/' ~/client-configs/base.conf
echo "key-direction 1" >> ~/client-configs/base.conf

# 9) Client .ovpn builder script
cat <<'EOF' > ~/client-configs/make_config.sh
#!/bin/bash
KEY_DIR=~/openvpn-ca/keys
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf

cat "${BASE_CONFIG}" \
    <(echo -e '<ca>') \
    "${KEY_DIR}/ca.crt" \
    <(echo -e '</ca>\n<cert>') \
    "${KEY_DIR}/'"$CLIENT_NAME"'.crt" \
    <(echo -e '</cert>\n<key>') \
    "${KEY_DIR}/'"$CLIENT_NAME"'.key" \
    <(echo -e '</key>\n<tls-auth>') \
    "${KEY_DIR}/ta.key" \
    <(echo -e '</tls-auth>') \
    > "${OUTPUT_DIR}/'"$CLIENT_NAME"'.ovpn"
EOF

chmod +x ~/client-configs/make_config.sh
~/client-configs/make_config.sh

echo
echo "✅ OpenVPN is now running on $PORT/$PROTO"
echo "📄 Client profile available at: ~/client-configs/files/$CLIENT_NAME.ovpn"
