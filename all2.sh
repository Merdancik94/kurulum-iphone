#!/bin/bash

# Часть 1: Настройка DNS
echo "Выберите вариант настройки /etc/resolv.conf:"
echo "1) Google DNS (8.8.8.8 и 8.8.4.4)"
echo "2) Cloudflare DNS (1.1.1.1)"

read -p "Введите 1 или 2: " choice

case $choice in
    1)
        # Удаляем существующий resolv.conf и создаем новый с Google DNS
        rm /etc/resolv.conf
        echo "Создание /etc/resolv.conf с Google DNS..."
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 8.8.4.4" >> /etc/resolv.conf
        ;;
    2)
        # Удаляем существующий resolv.conf и создаем новый с Cloudflare DNS
        rm /etc/resolv.conf
        echo "Создание /etc/resolv.conf с Cloudflare DNS..."
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        ;;
    *)
        echo "Неверный выбор. Скрипт завершен."
        exit 1
        ;;
esac

# Защита файла от изменений
chattr +i /etc/resolv.conf

echo "/etc/resolv.conf успешно настроен и защищен от изменений."

# Часть 2: Установка и настройка Apache
# Установка Apache2, если он не установлен
if ! command -v apache2 &> /dev/null; then
    echo "Apache2 не установлен. Устанавливаем Apache2..."
    sudo apt update
    sudo apt install apache2 -y
    echo "Apache2 успешно установлен."
fi

# Запрашиваем у пользователя имя файла конфигурации три раза и записываем блоки <VirtualHost>
for i in 1 2 3; do
    read -p "Введите имя конфигурационного файла ${i} (без расширения .conf): " conf_file
    
    # Путь к файлу конфигурации
    conf_path="/etc/apache2/sites-available/${conf_file}.conf"
    
    # Создаем или очищаем файл конфигурации и записываем блок <VirtualHost>
    sudo bash -c "cat > $conf_path <<EOL
<VirtualHost *:80>
    DocumentRoot /var/www/html
    ServerName $conf_file
</VirtualHost>
EOL"

    # Сообщаем, что файл создан и сохранен
    echo "Конфигурационный файл $conf_file.conf создан и сохранен."

    # Активируем сайт с помощью a2ensite
    sudo a2ensite "${conf_file}.conf"
done

# Перезагружаем Apache после активации всех сайтов
sudo systemctl reload apache2

echo "Все три сайта успешно активированы и Apache перезапущен."

# Добавляем строку ServerName 127.0.0.1 в apache2.conf
sudo bash -c "echo 'ServerName 127.0.0.1' >> /etc/apache2/apache2.conf"

# Перезапускаем Apache для применения изменений
sudo systemctl restart apache2

echo "ServerName 127.0.0.1 добавлен в /etc/apache2/apache2.conf и Apache перезапущен."

# Устанавливаем certbot, если он не установлен
if ! command -v certbot &> /dev/null; then
    echo "Certbot не установлен. Устанавливаем certbot..."
    sudo apt update
    sudo apt install certbot python3-certbot-apache -y
    echo "Certbot успешно установлен."
fi

# Используем заранее заданный email для регистрации в Let's Encrypt
email="redmyrat@gmail.com"

# Получаем список всех активированных сайтов
sites=$(ls /etc/apache2/sites-enabled/*.conf)

# Проходим по каждому активированному сайту и запускаем certbot для создания сертификата
for site in $sites; do
    # Извлекаем имя домена из конфигурационного файла
    domain=$(basename "$site" .conf)

    # Проверяем, есть ли запись ServerName в конфигурационном файле
    if grep -q "ServerName" "$site"; then
        echo "Создание сертификата для $domain..."
        
        # Запуск certbot с автоматическим принятием условий и созданием сертификата для домена
        sudo certbot --apache -m "$email" --agree-tos --redirect -d "$domain" -n
        
        echo "Сертификат для $domain успешно создан и перенаправление на HTTPS включено."
    else
        echo "Конфигурация для $domain не содержит ServerName. Пропускаем..."
    fi
done

echo "Сертификаты успешно созданы для всех активированных доменов."

# Часть 3: Установка и настройка HAProxy
# Устанавливаем HAProxy и запускаем его
sudo apt install haproxy -y
sudo systemctl start haproxy

# Получаем статический IP-адрес сервера
static_ip=$(hostname -I | awk '{print $1}')

# Запрашиваем ввод поддомена, домена с префиксом www, и домена без префикса
read -p "Введите поддомен для use_backend openvpn: " subdomain
read -p "Введите домен с префиксом www для use_backend apache: " www_domain
read -p "Введите домен без префикса для use_backend apache: " no_prefix_domain

# Открываем файл конфигурации HAProxy и добавляем необходимые настройки
sudo bash -c "cat >> /etc/haproxy/haproxy.cfg <<EOL

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
EOL"

echo "Конфигурация HAProxy обновлена и применена."

# Перезапускаем HAProxy для применения изменений
sudo systemctl restart haproxy

echo "HAProxy успешно настроен и перезапущен."

# Редактируем файл /etc/apache2/ports.conf, заменяя все порты 443 на 127.0.0.2:443
ports_conf="/etc/apache2/ports.conf"
sudo sed -i 's/\b443\b/127.0.0.2:443/g' "$ports_conf"

# Сообщаем, что изменения внесены
echo "Все упоминания порта 443 в файле $ports_conf заменены на 127.0.0.2:443."

# Перезапуск Apache для применения изменений
sudo systemctl restart apache2

echo "Apache успешно перезапущен."

# Часть 4: Настройка сетевых параметров

# Добавляем параметры в файл /etc/sysctl.conf
echo "Добавляем параметры в /etc/sysctl.conf..."
sudo bash -c "echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf"
sudo bash -c "echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf"
sudo bash -c "echo 'net.ipv4.icmp_echo_ignore_all=1' >> /etc/sysctl.conf"

# Применяем изменения
echo "Применяем изменения сетевых параметров..."
sudo sysctl -p

echo "Настройка сетевых параметров завершена."

# Часть 5: Скачивание и распаковка файла

# Проверяем, установлен ли unzip, и устанавливаем его, если нужно
if ! command -v unzip &> /dev/null; then
    echo "Unzip не установлен. Устанавливаем unzip..."
    sudo apt update && sudo apt install unzip -y
    echo "Unzip успешно установлен."
fi

# Запрашиваем у пользователя ссылку для скачивания файла
read -p "Введите ссылку для скачивания файла (wget): " download_link

# Скачиваем файл
wget "$download_link" -O downloaded_file.zip

# Проверяем, успешно ли был скачан файл
if [ $? -ne 0 ]; then
    echo "Ошибка при скачивании файла."
    exit 1
fi

# Распаковываем содержимое архива во временную папку внутри /var/www/html/
temp_dir="/var/www/html/temp_unzip_dir"
mkdir -p "$temp_dir"
unzip -o downloaded_file.zip -d "$temp_dir"

# Переходим в распакованную папку (предполагаем, что архив содержит только одну верхнюю папку)
extracted_dir=$(ls -d "$temp_dir"/*/)

# Проверяем, что распакованная директория существует
if [ -z "$extracted_dir" ]; then
    echo "Не удалось найти распакованную директорию."
    rm -rf "$temp_dir"
    rm downloaded_file.zip
    exit 1
fi

# Копируем все файлы и папки из распакованной директории в /var/www/html/
mv "$extracted_dir"* /var/www/html/
mv "$extracted_dir".* /var/www/html/ 2>/dev/null

# Удаляем временную папку и архив
rm -rf "$temp_dir"
rm downloaded_file.zip

echo "Все файлы и папки из распакованного архива успешно перемещены в /var/www/html/."
