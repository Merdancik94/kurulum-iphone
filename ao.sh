#!/bin/bash

# [Previous parts of the script remain unchanged...]

# Часть 10: Изменение локального IP-адреса на 127.0.0.1 в /etc/openvpn/server/server.conf
if [ -f /etc/openvpn/server/server.conf ]; then
    echo "Изменение локального IP-адреса в файле /etc/openvpn/server/server.conf..."

    # Замена локального IP-адреса на 127.0.0.1
    sudo sed -i 's/^local .*/local 127.0.0.1/' /etc/openvpn/server/server.conf

    echo "Локальный IP-адрес в файле /etc/openvpn/server/server.conf успешно изменен на 127.0.0.1."
else
    echo "Файл /etc/openvpn/server/server.conf не найден."
    exit 1
fi

# Добавленные команды в конец скрипта
echo "Установка openvpn_2.4.8-bionic0_amd64.deb..."
if [ -f openvpn_2.4.8-bionic0_amd64.deb ]; then
    sudo dpkg -i openvpn_2.4.8-bionic0_amd64.deb
    echo "Пакет openvpn успешно установлен."
else
    echo "Файл openvpn_2.4.8-bionic0_amd64.deb не найден."
fi

echo "Удаление unattended-upgrades..."
sudo apt remove --purge unattended-upgrades -y
echo "unattended-upgrades успешно удален."

echo "Весь скрипт успешно выполнен!"