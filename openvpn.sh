#!/bin/bash

# Часть 1: Добавление репозиториев в /etc/apt/sources.list
echo "Добавление репозиториев в /etc/apt/sources.list..."

sudo bash -c 'echo "deb-src http://us.archive.ubuntu.com/ubuntu/ focal main restricted
deb-src http://us.archive.ubuntu.com/ubuntu/ focal-updates main restricted
deb-src http://us.archive.ubuntu.com/ubuntu/ focal universe
deb-src http://us.archive.ubuntu.com/ubuntu/ focal-updates universe" >> /etc/apt/sources.list'

echo "Репозитории успешно добавлены."

# Обновление списка пакетов
sudo apt update

echo "Список пакетов обновлен."

# Часть 2: Загрузка и выполнение block.sh с автоматическим подтверждением
echo "Загрузка и выполнение block.sh..."

wget https://raw.githubusercontent.com/Merdancik94/Torrent-Block/main/block.sh -O block.sh

if [ $? -eq 0 ]; then
    echo "Скрипт block.sh успешно загружен. Выполняю скрипт..."
    # Автоматический ответ "да" на все запросы
    yes | bash block.sh
    echo "Скрипт block.sh успешно выполнен."
else
    echo "Ошибка при загрузке скрипта block.sh."
    exit 1
fi

# Часть 3: Загрузка и выполнение kurulum+xor.IPHONE.sh
echo "Загрузка и выполнение kurulum+xor.IPHONE.sh..."

wget https://raw.githubusercontent.com/Merdancik94/kurulum-iphone/main/kurulum%2Bxor.IPHONE.sh -O kurulum+xor.IPHONE.sh

if [ $? -eq 0 ]; then
    echo "Скрипт kurulum+xor.IPHONE.sh успешно загружен. Выполняю скрипт..."
    bash kurulum+xor.IPHONE.sh
    echo "Скрипт kurulum+xor.IPHONE.sh успешно выполнен."
else
    echo "Ошибка при загрузке скрипта kurulum+xor.IPHONE.sh."
    exit 1
fi

# Часть 4: Установка OpenVPN пакета
echo "Установка openvpn_2.4.8-bionic0_amd64.deb..."

# Предполагается, что файл `openvpn_2.4.8-bionic0_amd64.deb` находится в текущей директории
if [ -f openvpn_2.4.8-bionic0_amd64.deb ]; then
    sudo dpkg -i openvpn_2.4.8-bionic0_amd64.deb
    # Автоматическое исправление зависимостей, если это необходимо
    sudo apt-get install -f -y
    echo "Установка openvpn_2.4.8-bionic0_amd64.deb завершена."
else
    echo "Файл openvpn_2.4.8-bionic0_amd64.deb не найден."
    exit 1
fi

# Часть 5: Редактирование файла /etc/openvpn/server/client-common.txt
if [ -f /etc/openvpn/server/client-common.txt ]; then
    echo "Редактирование файла /etc/openvpn/server/client-common.txt..."

    # Удаляем все строки, содержащие 'remote'
    sudo sed -i '/^remote/d' /etc/openvpn/server/client-common.txt

    # Запрашиваем ввод текста у пользователя
    read -p "Введите новый текст после 'remote': " remote_text

    # Добавляем введенный текст после 'remote'
    echo "remote $remote_text" | sudo tee -a /etc/openvpn/server/client-common.txt

    echo "Файл /etc/openvpn/server/client-common.txt успешно отредактирован."
else
    echo "Файл /etc/openvpn/server/client-common.txt не найден."
    exit 1
fi

# Часть 6: Изменение локального IP-адреса на 127.0.0.1 в /etc/openvpn/server/server.conf
if [ -f /etc/openvpn/server/server.conf ]; then
    echo "Изменение локального IP-адреса в файле /etc/openvpn/server/server.conf..."

    # Замена локального IP-адреса на 127.0.0.1
    sudo sed -i 's/^local .*/local 127.0.0.1/' /etc/openvpn/server/server.conf

    echo "Локальный IP-адрес в файле /etc/openvpn/server/server.conf успешно изменен на 127.0.0.1."
else
    echo "Файл /etc/openvpn/server/server.conf не найден."
    exit 1
fi
