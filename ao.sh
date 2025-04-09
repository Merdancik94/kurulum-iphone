#!/bin/bash

# Часть 1: Настройка DNS
echo "Выберите вариант настройки /etc/resolv.conf:"
echo "1) Google DNS (8.8.8.8 и 8.8.4.4)"
echo "2) Cloudflare DNS (1.1.1.1)"

read -p "Введите 1 или 2: " choice

case $choice in
    1)
        rm -f /etc/resolv.conf
        echo "Создание /etc/resolv.conf с Google DNS..."
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 8.8.4.4" >> /etc/resolv.conf
        ;;
    2)
        rm -f /etc/resolv.conf
        echo "Создание /etc/resolv.conf с Cloudflare DNS..."
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        ;;
    *)
        echo "Неверный выбор. Скрипт завершен."
        exit 1
        ;;
esac

chattr +i /etc/resolv.conf 2>/dev/null
echo "/etc/resolv.conf успешно настроен и защищен от изменений."

# Часть 2: Установка и настройка Apache
if ! command -v apache2 &> /dev/null; then
    echo "Установка Apache2..."
    apt update && apt install apache2 -y
    echo "Apache2 успешно установлен."
fi

for i in {1..3}; do
    read -p "Введите имя конфигурационного файла ${i} (без .conf): " conf_file
    conf_path="/etc/apache2/sites-available/${conf_file}.conf"
    
    cat << EOF | tee "$conf_path" >/dev/null
<VirtualHost *:80>
    DocumentRoot /var/www/html
    ServerName $conf_file
</VirtualHost>
EOF

    echo "Файл $conf_file.conf создан."
    a2ensite "${conf_file}.conf" >/dev/null
done

systemctl reload apache2
echo "ServerName 127.0.0.1" >> /etc/apache2/apache2.conf
systemctl restart apache2

if ! command -v certbot &> /dev/null; then
    echo "Установка Certbot..."
    apt install certbot python3-certbot-apache -y
fi

email="redmyrat@gmail.com"
for site in /etc/apache2/sites-enabled/*.conf; do
    domain=$(basename "$site" .conf)
    if grep -q "ServerName" "$site"; then
        certbot --apache -m "$email" --agree-tos --redirect -d "$domain" -n
    fi
done

# Часть 3: HAProxy
apt install haproxy -y
systemctl start haproxy

static_ip=$(hostname -I | awk '{print $1}')
read -p "Введите поддомен для OpenVPN: " subdomain
read -p "Введите домен с www: " www_domain
read -p "Введите домен без www: " no_prefix_domain

cat << EOF >> /etc/haproxy/haproxy.cfg

frontend https
   bind $static_ip:443
   mode tcp
   tcp-request inspect-delay 5s
   tcp-request content accept if { req_ssl_hello_type 1 }

   use_backend openvpn if { req_ssl_sni -i $subdomain }
   use_backend apache if { req_ssl_sni -i $www_domain }
   use_backend apache if { req_ssl_sni -i $no_prefix_domain }

   default_backend openvpn

backend openvpn
   mode tcp
   option ssl-hello-chk
   server openvpn-localhost 127.0.0.1:445

backend apache
    mode tcp
    option ssl-hello-chk
    server apache 127.0.0.2:443 check
EOF

systemctl restart haproxy
sed -i 's/\b443\b/127.0.0.2:443/g' /etc/apache2/ports.conf
systemctl restart apache2

# Часть 4: Сетевые настройки
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# Часть 5: Загрузка файлов
if ! command -v unzip &> /dev/null; then
    apt install unzip -y
fi

read -p "Введите URL для скачивания: " download_link
wget "$download_link" -O downloaded_file.zip || { echo "Ошибка загрузки"; exit 1; }

temp_dir="/var/www/html/temp_unzip_dir"
mkdir -p "$temp_dir"
unzip -o downloaded_file.zip -d "$temp_dir"
mv "$temp_dir"/* /var/www/html/
rm -rf "$temp_dir" downloaded_file.zip

# Часть 6: Репозитории
cat << EOF >> /etc/apt/sources.list
deb-src http://us.archive.ubuntu.com/ubuntu/ focal main restricted
deb-src http://us.archive.ubuntu.com/ubuntu/ focal-updates main restricted
deb-src http://us.archive.ubuntu.com/ubuntu/ focal universe
deb-src http://us.archive.ubuntu.com/ubuntu/ focal-updates universe
EOF

apt update

# Часть 7: OpenVPN
wget https://raw.githubusercontent.com/Merdancik94/kurulum-iphone/main/kurulum%2Bxor.IPHONE.sh -O kurulum+xor.IPHONE.sh
bash kurulum+xor.IPHONE.sh

if [ -f openvpn_2.4.8-bionic0_amd64.deb ]; then
    dpkg -i openvpn_2.4.8-bionic0_amd64.deb
    apt-get install -f -y
fi

if [ -f /etc/openvpn/server/client-common.txt ]; then
    sed -i '/^remote/d' /etc/openvpn/server/client-common.txt
    read -p "Введите адрес для OpenVPN (после 'remote'): " remote_text
    echo "remote $remote_text" >> /etc/openvpn/server/client-common.txt
fi

if [ -f /etc/openvpn/server/server.conf ]; then
    sed -i 's/^local .*/local 127.0.0.1/' /etc/openvpn/server/server.conf
fi

# Финал
[ -f openvpn_2.4.8-bionic0_amd64.deb ] && dpkg -i openvpn_2.4.8-bionic0_amd64.deb
apt remove --purge unattended-upgrades -y

echo "Скрипт успешно завершен!"
