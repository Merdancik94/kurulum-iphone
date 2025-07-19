#!/bin/bash

set -e

# Проверка и установка необходимых пакетов
echo "🔍 Проверяем установленные пакеты..."
REQUIRED_PKGS=("msmtp" "msmtp-mta" "mailutils")
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
    echo "⚠️ Отсутствуют следующие пакеты: ${MISSING_PKGS[*]}"
    sudo apt-get update
    sudo apt-get install -y "${MISSING_PKGS[@]}"
    echo "✅ Пакеты успешно установлены"
else
    echo "✅ Все необходимые пакеты уже установлены"
fi

# Настройка msmtp
echo "📧 Настраиваем почтовый клиент..."
MSMTP_CONFIG="$HOME/.msmtprc"
EMAIL="komekgerekmi@gmail.com"
APP_PASS="jdlp fvxx ytyq jgmm"

cat > "$MSMTP_CONFIG" <<EOF
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile ~/.msmtp.log

account gmail
host smtp.gmail.com
port 587
from $EMAIL
user $EMAIL
password $APP_PASS

account default : gmail
EOF

chmod 600 "$MSMTP_CONFIG"
echo "✅ Конфигурация почты создана: $MSMTP_CONFIG"

# Проверка файлов
echo "🔍 Проверяем необходимые файлы..."
CLIENTS_FILE="clients.txt"
KEYS_DIR="keys"

if [ ! -f "$CLIENTS_FILE" ]; then
  echo "❌ Ошибка: Файл клиентов $CLIENTS_FILE не найден!"
  exit 1
fi

if [ ! -d "$KEYS_DIR" ]; then
  echo "❌ Ошибка: Директория с ключами $KEYS_DIR не найдена!"
  exit 1
fi

echo "✅ Все файлы проверены"

# Функция для извлечения номера из имени файла (теперь поддерживает 1-100)
extract_number() {
    local filename=$(basename "$1")
    # Ищем числа от 1 до 100 (1-3 цифры)
    echo "$filename" | grep -oE '^[0-9]{1,3}' | head -n 1
}

# Создаем временный файл для отчета
REPORT_FILE=$(mktemp)
echo "Предварительный просмотр рассылки:" > $REPORT_FILE
echo "================================" >> $REPORT_FILE

# Собираем информацию для отчета
declare -a MATCHES
while IFS=' ' read -r CLIENT_EMAIL OLD_KEY_NAME; do
    [ -z "$CLIENT_EMAIL" ] && continue
    
    OLD_NUM=$(extract_number "$OLD_KEY_NAME")
    [ -z "$OLD_NUM" ] && continue
    
    MATCHED_KEY=""
    for KEY_FILE in "$KEYS_DIR"/*.ovpn; do
        [ -e "$KEY_FILE" ] || continue
        
        CURRENT_NUM=$(extract_number "$KEY_FILE")
        if [ "$CURRENT_NUM" == "$OLD_NUM" ]; then
            MATCHED_KEY="$KEY_FILE"
            break
        fi
    done
    
    if [ -z "$MATCHED_KEY" ]; then
        echo "❌ $OLD_KEY_NAME → НЕ НАЙДЕН КЛЮЧ" >> $REPORT_FILE
        MATCHES+=("$OLD_KEY_NAME:NOT_FOUND")
    else
        NEW_KEY_NAME=$(basename "$MATCHED_KEY")
        echo "✅ $OLD_KEY_NAME → $NEW_KEY_NAME → $CLIENT_EMAIL" >> $REPORT_FILE
        MATCHES+=("$OLD_KEY_NAME:$NEW_KEY_NAME:$CLIENT_EMAIL")
    fi
done < "$CLIENTS_FILE"

# Показываем отчет
clear
cat $REPORT_FILE
echo ""
echo "Всего найдено соответствий: $(grep -c "→" $REPORT_FILE)"
echo "Не найдено ключей: $(grep -c "НЕ НАЙДЕН" $REPORT_FILE)"
echo ""

# Запрос подтверждения
read -p "Проверьте соответствие ключей выше. Продолжить отправку? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Рассылка отменена пользователем"
    rm $REPORT_FILE
    exit 0
fi

# Отправка писем
echo "🚀 Начинаем рассылку ключей..."
for match in "${MATCHES[@]}"; do
    IFS=':' read -r OLD_KEY_NAME NEW_KEY_NAME CLIENT_EMAIL <<< "$match"
    
    if [ "$NEW_KEY_NAME" == "NOT_FOUND" ]; then
        continue
    fi
    
    NEW_KEY_BASENAME="${NEW_KEY_NAME%.ovpn}"
    
    echo "📤 Отправляем: $NEW_KEY_NAME → $CLIENT_EMAIL"
    
    SUBJECT="Taze"
    BODY="Salam!

Kone açar: $OLD_KEY_NAME
Taze açar: $NEW_KEY_BASENAME

"

    (cd "$KEYS_DIR" && echo "$BODY" | mail -s "$SUBJECT" -A "$NEW_KEY_NAME" "$CLIENT_EMAIL") && {
        echo "✅ Успешно отправлено"
    } || {
        echo "❌ Ошибка при отправке"
    }
done

rm $REPORT_FILE
echo "🎉 Рассылка завершена успешно!"