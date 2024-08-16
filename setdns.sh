#!/bin/bash

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
