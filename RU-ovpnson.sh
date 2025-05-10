#!/bin/bash
#
# OpenVPN Road Warrior Installer - Модифицированная версия с исправлением массового удаления клиентов
# https://github.com/Nyr/openvpn-install
#
# Copyright (c) 2013 Nyr. Released under the MIT License.

# Проверка запуска через bash
if readlink /proc/$$/exe | grep -q "dash"; then
	echo 'Этот установщик должен быть запущен через "bash", а не через "sh".'
	exit
fi

# Очищаем ввод
read -N 999999 -t 0.001

# Создание папки для ключей
HOME_DIR=$(eval echo ~${SUDO_USER})
KEYS_DIR="$HOME_DIR/keys"
mkdir -p "$KEYS_DIR"

# Проверка ядра
if [[ $(uname -r | cut -d "." -f 1) -eq 2 ]]; then
	echo "У вас слишком старое ядро. Этот установщик не поддерживает ядро 2.x."
	exit
fi

# Определение дистрибутива
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
	group_name="nogroup"
elif [[ -e /etc/debian_version ]]; then
	os="debian"
	os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
	group_name="nogroup"
elif [[ -e /etc/almalinux-release || -e /etc/rocky-release || -e /etc/centos-release ]]; then
	os="centos"
	os_version=$(grep -shoE '[0-9]+' /etc/almalinux-release /etc/rocky-release /etc/centos-release | head -1)
	group_name="nobody"
elif [[ -e /etc/fedora-release ]]; then
	os="fedora"
	os_version=$(grep -oE '[0-9]+' /etc/fedora-release | head -1)
	group_name="nobody"
else
	echo "Этот скрипт поддерживает только Ubuntu, Debian, CentOS, Fedora, AlmaLinux и Rocky Linux."
	exit
fi

# Проверка версий
if [[ "$os" == "ubuntu" && "$os_version" -lt 1804 ]]; then
	echo "Для использования установщика требуется Ubuntu 18.04 или новее."
	exit
fi

if [[ "$os" == "debian" && "$os_version" -lt 9 ]]; then
	echo "Для использования установщика требуется Debian 9 или новее."
	exit
fi

if [[ "$os" == "centos" && "$os_version" -lt 7 ]]; then
	echo "Для использования установщика требуется CentOS 7 или новее."
	exit
fi

# Проверка PATH
if ! grep -q sbin <<< "$PATH"; then
	echo 'Ошибка: $PATH не содержит sbin. Используйте "su -" вместо "su".'
	exit
fi

if [[ "$EUID" -ne 0 ]]; then
	echo "Этот скрипт должен быть запущен с правами суперпользователя."
	exit
fi

if [[ ! -e /dev/net/tun ]] || ! ( exec 7<>/dev/net/tun ) 2>/dev/null; then
	echo "TUN устройство недоступно. Нужно включить TUN перед установкой."
	exit
fi

# Функция для генерации клиента
new_client () {
	{
	cat /etc/openvpn/server/client-common.txt
	echo "<ca>"
	cat /etc/openvpn/server/easy-rsa/pki/ca.crt
	echo "</ca>"
	echo "<cert>"
	sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt
	echo "</cert>"
	echo "<key>"
	cat /etc/openvpn/server/easy-rsa/pki/private/"$client".key
	echo "</key>"
	echo "<tls-crypt>"
	sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/server/tc.key
	echo "</tls-crypt>"
	} > "$KEYS_DIR/$client.ovpn"

	# Установка безопасных прав на файл
	chmod 600 "$KEYS_DIR/$client.ovpn"
	echo
	echo "Конфигурация клиента сохранена в: $KEYS_DIR/$client.ovpn"
}

# Проверка существующей установки
if [[ ! -e /etc/openvpn/server/server.conf ]]; then
	# Установка wget, если его нет
	if ! hash wget 2>/dev/null && ! hash curl 2>/dev/null; then
		echo "Wget необходим для работы установщика."
		read -n1 -r -p "Нажмите любую клавишу для установки Wget..."
		apt-get update
		apt-get install -y wget
	fi
	clear
	echo 'Добро пожаловать в установщик OpenVPN!'

	# Определение IPv4 адреса
	if [[ $(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}') -eq 1 ]]; then
		ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}')
	else
		number_of_ip=$(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}')
		echo
		echo "Какой IPv4 адрес использовать?"
		ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | nl -s ') '
		read -p "IPv4 адрес [1]: " ip_number
		until [[ -z "$ip_number" || "$ip_number" =~ ^[0-9]+$ && "$ip_number" -le "$number_of_ip" ]]; do
			echo "$ip_number: неверный выбор."
			read -p "IPv4 адрес [1]: " ip_number
		done
		[[ -z "$ip_number" ]] && ip_number="1"
		ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sed -n "$ip_number"p)
	fi

	# NAT (если внутренний IP)
	if echo "$ip" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
		echo
		echo "Сервер находится за NAT. Введите внешний IP или хостнейм:"
		get_public_ip=$(grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$(wget -T 10 -t 1 -4qO- "http://ip1.dynupdate.no-ip.com/" || curl -m 10 -4Ls "http://ip1.dynupdate.no-ip.com/")")
		read -p "Публичный IPv4/хостнейм [$get_public_ip]: " public_ip
		until [[ -n "$get_public_ip" || -n "$public_ip" ]]; do
			echo "Некорректный ввод."
			read -p "Публичный IPv4/хостнейм: " public_ip
		done
		[[ -z "$public_ip" ]] && public_ip="$get_public_ip"
	fi

	# Определение протокола
	echo
	echo "Выберите протокол для OpenVPN:"
	echo "   1) UDP"
	echo "   2) TCP (рекомендуется)"
	read -p "Протокол [1]: " protocol
	until [[ -z "$protocol" || "$protocol" =~ ^[12]$ ]]; do
		echo "$protocol: неверный выбор."
		read -p "Протокол [1]: " protocol
	done
	case "$protocol" in
		1|"") protocol=udp ;;
		2) protocol=tcp ;;
	esac

	# Порт
	echo
	echo "На каком порту будет работать OpenVPN?"
	read -p "Порт [1194]: " port
	until [[ -z "$port" || "$port" =~ ^[0-9]+$ && "$port" -le 65535 ]]; do
		echo "$port: неверный порт."
		read -p "Порт [1194]: " port
	done
	[[ -z "$port" ]] && port="1194"

	# Выбор DNS для клиентов
	echo
	echo "Выберите DNS-сервер для клиентов:"
	echo "   1) Текущие системные резолверы"
	echo "   2) Google DNS"
	echo "   3) Cloudflare 1.1.1.1"
	echo "   4) OpenDNS"
	echo "   5) Quad9"
	echo "   6) AdGuard"
	read -p "DNS-сервер [1]: " dns
	until [[ -z "$dns" || "$dns" =~ ^[1-6]$ ]]; do
		echo "$dns: неверный выбор."
		read -p "DNS-сервер [1]: " dns
	done

	# Запрос имени первого клиента
	echo
	echo "Введите имя для первого клиента:"
	read -p "Имя [client]: " unsanitized_client
	client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
	[[ -z "$client" ]] && client="client"

	echo
	echo "Установка OpenVPN начнется сейчас..."
	read -n1 -r -p "Нажмите любую клавишу для продолжения..."

	# Установка необходимых пакетов
	if [[ "$os" = "debian" || "$os" = "ubuntu" ]]; then
		apt-get update
		apt-get install -y openvpn openssl ca-certificates wget curl
	elif [[ "$os" = "centos" ]]; then
		yum install -y epel-release
		yum install -y openvpn openssl ca-certificates tar wget curl
	else
		dnf install -y openvpn openssl ca-certificates tar wget curl
	fi

	# Загрузка easy-rsa
	easy_rsa_url='https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.0/EasyRSA-3.1.0.tgz'
	mkdir -p /etc/openvpn/server/easy-rsa/
	{ wget -qO- "$easy_rsa_url" 2>/dev/null || curl -sL "$easy_rsa_url" ; } | tar xz -C /etc/openvpn/server/easy-rsa/ --strip-components 1
	chown -R root:root /etc/openvpn/server/easy-rsa/
	chmod +x /etc/openvpn/server/easy-rsa/  # Добавленная строка
	cd /etc/openvpn/server/easy-rsa/

	# Инициализация PKI
	./easyrsa init-pki
	./easyrsa --batch build-ca nopass
	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-server-full server nopass
	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass
	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

	# Копирование ключей и сертификатов
	cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn/server
	chown nobody:"$group_name" /etc/openvpn/server/crl.pem
	chmod o+x /etc/openvpn/server/

	# Генерация ключа для tls-crypt
	openvpn --genkey --secret /etc/openvpn/server/tc.key

	# Создание конфигурации сервера
	echo "local $ip
port $port
proto $protocol
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA512
tls-crypt tc.key
topology subnet
server 10.8.0.0 255.255.255.0" > /etc/openvpn/server/server.conf

	# Добавление маршрутизации и DNS
	echo 'ifconfig-pool-persist ipp.txt' >> /etc/openvpn/server/server.conf
	case "$dns" in
		1|"")
			if grep -q '^nameserver 127.0.0.53' "/etc/resolv.conf"; then
				resolv_conf="/run/systemd/resolve/resolv.conf"
			else
				resolv_conf="/etc/resolv.conf"
			fi
			grep -v '^#\|^;' "$resolv_conf" | grep '^nameserver' | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | while read line; do
				echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server/server.conf
			done
			;;
		2)
			echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server/server.conf
			;;
		3)
			echo 'push "dhcp-option DNS 1.1.1.1"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 1.0.0.1"' >> /etc/openvpn/server/server.conf
			;;
		4)
			echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server/server.conf
			;;
		5)
			echo 'push "dhcp-option DNS 9.9.9.9"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 149.112.112.112"' >> /etc/openvpn/server/server.conf
			;;
		6)
			echo 'push "dhcp-option DNS 94.140.14.14"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 94.140.15.15"' >> /etc/openvpn/server/server.conf
			;;
	esac

	# Завершение конфигурации
	echo "keepalive 10 120
cipher AES-256-CBC
user nobody
group $group_name
persist-key
persist-tun
verb 3
crl-verify crl.pem" >> /etc/openvpn/server/server.conf

	if [[ "$protocol" = "udp" ]]; then
		echo "explicit-exit-notify" >> /etc/openvpn/server/server.conf
	fi

	# Включение пересылки пакетов
	echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-openvpn-forward.conf
	echo 1 > /proc/sys/net/ipv4/ip_forward

	# Если есть IPv6
	if [[ -n "$ip6" ]]; then
		echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.d/99-openvpn-forward.conf
		echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
	fi

	# Конфигурация Firewall или iptables
	if systemctl is-active --quiet firewalld.service; then
		firewall-cmd --add-port="$port"/"$protocol"
		firewall-cmd --zone=trusted --add-source=10.8.0.0/24
		firewall-cmd --permanent --add-port="$port"/"$protocol"
		firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
	else
		# iptables fallback
		iptables_path=$(command -v iptables)
		ip6tables_path=$(command -v ip6tables)

		if [[ $(systemd-detect-virt) == "openvz" ]] && readlink -f "$(command -v iptables)" | grep -q "nft" && hash iptables-legacy 2>/dev/null; then
			iptables_path=$(command -v iptables-legacy)
			ip6tables_path=$(command -v ip6tables-legacy)
		fi

		echo "[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=$iptables_path -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $ip
ExecStart=$iptables_path -I INPUT -p $protocol --dport $port -j ACCEPT
ExecStart=$iptables_path -I FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStart=$iptables_path -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/openvpn-iptables.service

		systemctl enable --now openvpn-iptables.service
	fi

	# Обработка SELinux
	if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$port" != 1194 ]]; then
		if ! hash semanage 2>/dev/null; then
			if [[ "$os_version" -eq 7 ]]; then
				yum install -y policycoreutils-python
			else
				dnf install -y policycoreutils-python-utils
			fi
		fi
		semanage port -a -t openvpn_port_t -p "$protocol" "$port"
	fi

	# Создание client-common.txt
	echo "client
dev tun
proto $protocol
remote $ip $port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-CBC
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3" > /etc/openvpn/server/client-common.txt

	systemctl enable --now openvpn-server@server.service

	# Генерация первого клиента
	new_client
	echo
	echo "Установка завершена!"
	echo
	echo "Конфигурация клиента сохранена в: $KEYS_DIR/$client.ovpn"
	echo "Новые клиенты можно добавлять, перезапустив скрипт."
else
	clear
	echo "OpenVPN уже установлен."
	echo
	echo "Выберите опцию:"
	echo "   1) Добавить нового клиента"
	echo "   2) Показать список клиентов"
	echo "   3) Отозвать клиента(ов)"
	echo "   4) Удалить OpenVPN"
	echo "   5) Выйти"
	read -p "Опция: " option
	until [[ "$option" =~ ^[1-5]$ ]]; do
		echo "$option: неверный выбор."
		read -p "Опция: " option
	done

	case "$option" in
				1)
			echo
			echo "Сколько ключей создать?"
			read -p "Количество: " num_keys
			until [[ "$num_keys" =~ ^[0-9]+$ && "$num_keys" -ge 1 ]]; do
				echo "$num_keys: неверное значение."
				read -p "Количество: " num_keys
			done

			echo
			echo "Префикс для имени клиента (например 'user'):"
			read -p "Префикс: " prefix

			# Проверяем, есть ли ключи с таким префиксом
			existing_keys=()
			for cert in /etc/openvpn/server/easy-rsa/pki/issued/*.crt; do
				cert_name=$(basename "$cert" .crt)
				if [[ "$cert_name" =~ ^([0-9]+)("$prefix")$ ]]; then
					existing_keys+=(${BASH_REMATCH[1]})
				fi
			done

			# Определяем стартовый номер
			if [ ${#existing_keys[@]} -gt 0 ]; then
				# Если есть ключи с таким префиксом - продолжаем последовательность
				max_num=$(printf '%s\n' "${existing_keys[@]}" | sort -nr | head -1)
				start_num=$((max_num + 1))
				echo "Найдены существующие ключи с префиксом '$prefix' (макс. номер: $max_num)"
				echo "Новые ключи будут созданы с номерами $start_num-$((start_num + num_keys - 1))"
			else
				# Если ключей с таким префиксом нет - начинаем с 1
				start_num=1
				echo "Ключей с префиксом '$prefix' не найдено"
				echo "Новые ключи будут созданы с номерами 1-$num_keys"
			fi

			# Создаем новые ключи
			for ((i=0; i<num_keys; i++)); do
				current_num=$((start_num + i))
				client="${current_num}${prefix}"
				
				# Проверка на случай, если ключ уже существует (на всякий случай)
				if [[ -e /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt ]]; then
					echo "Ключ $client уже существует, пропускаем..."
					continue
				fi

				cd /etc/openvpn/server/easy-rsa/
				EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass
				new_client
				echo
				echo "$client добавлен. Конфигурация сохранена в $KEYS_DIR/$client.ovpn"
			done
			exit
			;;

		2)
			# Показ существующих клиентов
			number_of_clients=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -c "^V")
			if [[ "$number_of_clients" == 0 ]]; then
				echo
				echo "Нет существующих клиентов!"
			else
				echo
				echo "Список клиентов:"
				tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
				echo
				echo "Файлы конфигураций находятся в: $KEYS_DIR/"
			fi
			exit
			;;

		3)
			# Отзыв клиентов (одного или нескольких)
			number_of_clients=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -c "^V")
			if [[ "$number_of_clients" == 0 ]]; then
				echo
				echo "Нет клиентов для отзыва!"
				exit
			fi

			echo
			echo "Выберите опцию отзыва:"
			echo "   1) Отозвать одного клиента"
			echo "   2) Отозвать несколько клиентов"
			read -p "Опция [1]: " revoke_option
			until [[ -z "$revoke_option" || "$revoke_option" =~ ^[12]$ ]]; do
				echo "$revoke_option: неверный выбор."
				read -p "Опция [1]: " revoke_option
			done
			[[ -z "$revoke_option" ]] && revoke_option="1"

			case "$revoke_option" in
				1)
					echo
					echo "Выберите клиента для отзыва:"
					tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
					read -p "Клиент: " client_number
					until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
						echo "$client_number: неверный выбор."
						read -p "Клиент: " client_number
					done
					client=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "${client_number}p")

					echo
					read -p "Подтвердить отзыв клиента $client? [y/N]: " revoke
					until [[ "$revoke" =~ ^[yYnN]*$ ]]; do
						echo "$revoke: неверный ввод."
						read -p "Подтвердить отзыв клиента $client? [y/N]: " revoke
					done

					if [[ "$revoke" =~ ^[yY]$ ]]; then
						cd /etc/openvpn/server/easy-rsa/
						./easyrsa --batch revoke "$client"
						EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
						rm -f /etc/openvpn/server/crl.pem
						cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem
						chown nobody:"$group_name" /etc/openvpn/server/crl.pem
						if [[ -f "$KEYS_DIR/$client.ovpn" ]]; then
							rm -f "$KEYS_DIR/$client.ovpn"
							echo "Удален $KEYS_DIR/$client.ovpn"
						fi
						echo "$client отозван!"
					else
						echo "Отзыв отменен."
					fi
					;;

				2)
					echo
					echo "Выберите клиентов для отзыва (номера через пробел):"
					tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
					read -p "Клиенты: " client_numbers
					
					clients_to_revoke=()

					for num in $client_numbers; do
						client=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "${num}p")
						clients_to_revoke+=("$client")
					done

					echo
					read -p "Подтвердить отзыв выбранных клиентов? [y/N]: " revoke
					until [[ "$revoke" =~ ^[yYnN]*$ ]]; do
						echo "$revoke: неверный ввод."
						read -p "Подтвердить отзыв выбранных клиентов? [y/N]: " revoke
					done

					if [[ "$revoke" =~ ^[yY]$ ]]; then
						cd /etc/openvpn/server/easy-rsa/
						for client in "${clients_to_revoke[@]}"; do
							./easyrsa --batch revoke "$client"
							if [[ -f "$KEYS_DIR/$client.ovpn" ]]; then
								rm -f "$KEYS_DIR/$client.ovpn"
								echo "Удален $KEYS_DIR/$client.ovpn"
							fi
							echo "$client отозван!"
						done
						EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
						rm -f /etc/openvpn/server/crl.pem
						cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem
						chown nobody:"$group_name" /etc/openvpn/server/crl.pem
						echo "Все выбранные клиенты отозваны!"
					else
						echo "Отзыв отменен."
					fi
					;;
			esac
			exit
			;;

		4)
			echo
			read -p "Вы уверены, что хотите удалить OpenVPN? [y/N]: " remove
			until [[ "$remove" =~ ^[yYnN]*$ ]]; do
				echo "$remove: неверный ввод."
				read -p "Вы уверены, что хотите удалить OpenVPN? [y/N]: " remove
			done

			if [[ "$remove" =~ ^[yY]$ ]]; then
				systemctl disable --now openvpn-server@server.service
				rm -rf /etc/openvpn/server
				apt-get remove --purge -y openvpn || yum remove -y openvpn
				echo "OpenVPN удален!"
			else
				echo "Удаление отменено."
			fi
			exit
			;;

		5)
			exit
			;;
	esac
fi
