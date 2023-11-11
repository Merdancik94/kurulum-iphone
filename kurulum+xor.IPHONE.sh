#!/bin/bash
echo "deb http://cz.archive.ubuntu.com/ubuntu bionic main universe" >> /etc/apt/sources.list && apt update
apt-get update && apt-get build-dep openvpn -y
wget --no-check-cert https://github.com/Merdancik94/kurulum-iphone/raw/main/openvpn_2.4.8-bionic0_amd64.deb
dpkg -i openvpn_2.4.8-bionic0_amd64.deb
distro_check(){
	ID=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
	if [[ $ID == ubuntu ]]; then
		main
	else
		die "ubuntu only"
	fi
}

curl_ip(){
        var='/openvpn-monitor'
        ip=`dig +short myip.opendns.com @resolver1.opendns.com`
        echo ">> Kurulum tamamlandi <<"
        echo "http://"${ip}${var}
}

install_openvpn() {
	echo ">> OpenVPN kurulumu baslatiliyor"
	echo ">> indirme islemi basliyor"
	wget https://raw.githubusercontent.com/Merdancik94/kurulum-iphone/main/openvpn-install.IPHONE.sh && bash openvpn-install.IPHONE.sh
	apt-get -y install git curl apache2 libapache2-mod-wsgi python-geoip2 python-ipaddr python-humanize python-bottle python-semantic-version geoip-database-extra geoipupdate
	echo "Apache config ayalari yapiliyor"
	echo "WSGIScriptAlias /openvpn-monitor /var/www/html/openvpn-monitor/openvpn-monitor.py" >> /etc/apache2/conf-available/openvpn-monitor.conf
	echo "<Directory /var/www/html/openvpn-monitor>" >> /etc/apache2/conf-available/openvpn-monitor.conf
	echo "Options FollowSymLinks" >> /etc/apache2/conf-available/openvpn-monitor.conf
	echo "AllowOverride All" >> /etc/apache2/conf-available/openvpn-monitor.conf
	echo "</Directory>" >> /etc/apache2/conf-available/openvpn-monitor.conf
	a2enconf openvpn-monitor
	systemctl restart apache2
	echo "OpenVPN-Monitor kurulumu baslatiliyor"
	cd /var/www/html
	git clone https://github.com/furlongm/openvpn-monitor.git
        echo "management 127.0.0.1 5555" >> /etc/openvpn/server/server.conf
        echo "scramble xormask d" >> /etc/openvpn/server/server.conf
	echo 'push "route 103.220.0.0 255.255.252.0 net_gateway"
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
push "route 91.202.232.0 255.255.255.0 net_gateway"' >> /etc/openvpn/server/server.conf
	service openvpn restart
	service openvpn-server@server restart

	echo "AuthType Basic" >> /var/www/html/openvpn-monitor/.htaccess
	echo 'AuthName "Restricted Files"' >> /var/www/html/openvpn-monitor/.htaccess
	echo "AuthUserFile /var/www/.monitor" >> /var/www/html/openvpn-monitor/.htaccess
	echo "Require valid-user" >> /var/www/html/openvpn-monitor/.htaccess
	echo "monitor sayfasina ulasim icin kullanici olusturuluyor"
	read -p 'lutfen bir kullanici adi giriniz: ' uservar
	echo "$uservar kullanicisi olusturuluyor"
	echo "$uservar icin parola giriniz"
	sudo htpasswd -c /var/www/.monitor $uservar
	systemctl restart apache2
}


main() {
	cd
	clear
	install_openvpn
	curl_ip
}

if [[ "$EUID" -ne 0 ]]; then
	echo "root olarak calistirin"
	exit
else
	distro_check
fi
