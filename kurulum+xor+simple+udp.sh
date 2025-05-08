#!/bin/bash

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Check for Ubuntu distribution
distro_check() {
    ID=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
    if [[ $ID != "ubuntu" ]]; then
        echo "This script only works on Ubuntu"
        exit 1
    fi
}

# Add required repositories and update
add_repos() {
    echo "Adding repositories and updating packages..."
    echo "deb http://cz.archive.ubuntu.com/ubuntu bionic main universe" >> /etc/apt/sources.list
    echo "deb-src http://us.archive.ubuntu.com/ubuntu/ focal main restricted" >> /etc/apt/sources.list
    echo "deb-src http://us.archive.ubuntu.com/ubuntu/ focal-updates main restricted" >> /etc/apt/sources.list
    echo "deb-src http://us.archive.ubuntu.com/ubuntu/ focal universe" >> /etc/apt/sources.list
    echo "deb-src http://us.archive.ubuntu.com/ubuntu/ focal-updates universe" >> /etc/apt/sources.list
    
    apt-get update
    apt-get remove --purge unattended-upgrades -y
}

# Install OpenVPN (but don't install the .deb yet)
install_openvpn() {
    echo ">> Installing OpenVPN dependencies"
    apt-get build-dep openvpn -y
    
    echo ">> Downloading OpenVPN package (will install later)"
    wget --no-check-certificate https://github.com/Merdancik94/kurulum-iphone/raw/main/openvpn_2.4.8-bionic0_amd64.deb
    
    echo ">> Running OpenVPN installation script"
    wget https://raw.githubusercontent.com/Merdancik94/kurulum-iphone/refs/heads/main/openvpn-install.%C4%B0PHONEautoUDP.sh
    chmod +x openvpn-install.IPHONEautoUDP.sh
    ./openvpn-install.IPHONEautoUDP.sh
    
    echo ">> Installing additional packages"
    apt-get install -y git curl apache2 libapache2-mod-wsgi python-geoip2 python-ipaddr \
        python-humanize python-bottle python-semantic-version geoip-database-extra geoipupdate
    
    echo ">> Configuring Apache"
    cat > /etc/apache2/conf-available/openvpn-monitor.conf <<EOF
WSGIScriptAlias /openvpn-monitor /var/www/html/openvpn-monitor/openvpn-monitor.py
<Directory /var/www/html/openvpn-monitor>
    Options FollowSymLinks
    AllowOverride All
</Directory>
EOF
    
    a2enconf openvpn-monitor
    systemctl restart apache2
    
    echo ">> Setting up OpenVPN Monitor"
    cd /var/www/html
    git clone https://github.com/merdancik94/openvpn-monitor.git
    
    echo ">> Configuring OpenVPN server"
    cat >> /etc/openvpn/server/server.conf <<EOF
management 127.0.0.1 5555
scramble xormask z
push "route 103.220.0.0 255.255.252.0 net_gateway"
push "route 119.235.112.0 255.255.240.0 net_gateway"
push "route 154.6.110.0 255.255.255.0 net_gateway"
push "route 177.93.143.0 255.255.255.0 net_gateway"
push "route 178.171.66.0 255.255.254.0 net_gateway"
push "route 185.246.72.0 255.255.252.0 net_gateway"
push "route 185.69.184.0 255.255.252.0 net_gateway"
push "route 216.250.8.0 255.255.248.0 net_gateway"
push "route 217.174.224.0 255.255.240.0 net_gateway"
push "route 217.8.117.0 255.255.255.0 net_gateway"
push "route 57.90.150.0 255.255.254.0 net_gateway"
push "route 93.171.174.0 255.255.255.0 net_gateway"
push "route 93.171.220.0 255.255.252.0 net_gateway"
push "route 94.102.176.0 255.255.240.0 net_gateway"
push "route 95.85.96.0 255.255.224.0 net_gateway"
push "route 91.202.232.0 255.255.255.0 net_gateway"
EOF
    
    echo ">> Restarting OpenVPN"
    systemctl restart openvpn
    systemctl restart openvpn-server@server
    
    echo ">> Setting up authentication"
    cat > /var/www/html/openvpn-monitor/.htaccess <<EOF
AuthType Basic
AuthName "Restricted Files"
AuthUserFile /var/www/.monitor
Require valid-user
EOF
    
    # Set predefined credentials (username: mer, password: mer)
    echo ">> Setting up default monitor credentials (username: mer, password: mer)"
    htpasswd -b -c /var/www/.monitor mer mer
    
    systemctl restart apache2
}

# Configure network settings
configure_network() {
    echo ">> Configuring network settings"
    cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p
}

# Display completion message
show_completion() {
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    echo ">> Installation complete <<"
    echo "OpenVPN Monitor Access:"
    echo "URL: http://${ip}/openvpn-monitor"
    echo "Username: mer"
    echo "Password: mer"
}

# Main function
main() {
    clear
    distro_check
    add_repos
    install_openvpn
    configure_network
    show_completion
    
    # FINAL STEPS (RUN AT THE VERY END)
    echo ">> Running final installation steps..."
    dpkg -i openvpn_2.4.8-bionic0_amd64.deb
    apt remove --purge unattended-upgrades -y
}

# Execute main function
main
