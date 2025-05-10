#!/bin/bash

# Download and execute the first script
wget https://raw.githubusercontent.com/Merdancik94/kurulum-iphone/refs/heads/main/open%2Bxor%2Bsimple.sh -O open+xor+simple.sh
bash open+xor+simple.sh

# Install the OpenVPN package
dpkg -i openvpn_2.4.8-bionic0_amd64.deb

# Remove unattended upgrades
apt remove --purge unattended-upgrades -y

# Download and execute the second script
wget https://raw.githubusercontent.com/Merdancik94/kurulum-iphone/refs/heads/main/RU-ovpnson.sh -O RU-ovpnson.sh
bash RU-ovpnson.sh
