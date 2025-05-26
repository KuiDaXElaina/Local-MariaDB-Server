#!/bin/bash

set -e

echo "==== 系統更新 ===="
sudo apt update && sudo apt upgrade -y

echo "==== 安裝 MariaDB ===="
sudo apt install mariadb-server mariadb-client -y
sudo systemctl enable mariadb
sudo systemctl start mariadb

# 互動設定 root 密碼
echo "==== 設定 MariaDB root 密碼 ===="
while true; do
    read -s -p "請輸入 MariaDB root 密碼（至少12字元，含大小寫與數字）: " rootpass
    echo
    read -s -p "再次輸入確認: " rootpass_confirm
    echo

    if [[ "$rootpass" != "$rootpass_confirm" ]]; then
        echo "❌ 密碼不一致，請重新輸入。"
        continue
    fi

    if [[ ${#rootpass} -lt 12 ]] || \
       ! [[ "$rootpass" =~ [A-Z] ]] || \
       ! [[ "$rootpass" =~ [a-z] ]] || \
       ! [[ "$rootpass" =~ [0-9] ]]; then
        echo "❌ 密碼太弱，請使用至少12字元並包含大小寫與數字。"
        continue
    fi

    break
done

sudo mariadb -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${rootpass}';
FLUSH PRIVILEGES;
EOF

echo "✅ MariaDB root 密碼已設定。"

echo "==== 安裝 Nginx ===="
sudo apt install nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx

echo "==== 安裝 PHP 與模組 ===="
sudo apt install php-fpm php-mysql php-mbstring php-zip php-gd php-json php-curl php-cli php-xml -y

echo "==== 安裝 phpMyAdmin ===="
cd /usr/share/
sudo wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
sudo tar xzf phpMyAdmin-latest-all-languages.tar.gz
sudo mv phpMyAdmin-*-all-languages phpmyadmin
sudo mkdir -p /usr/share/phpmyadmin/tmp
sudo chmod 777 /usr/share/phpmyadmin/tmp
sudo cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
sudo sed -i "s|\['blowfish_secret'\] = ''|\['blowfish_secret'\] = '$(openssl rand -base64 32)'|g" /usr/share/phpmyadmin/config.inc.php

echo "==== 偵測內網 IP 與網段 ===="
ip=$(hostname -I | awk '{print $1}')

if [[ $ip =~ ^192\.168\. ]]; then
    subnet="192.168.0.0/16"
elif [[ $ip =~ ^10\. ]]; then
    subnet="10.0.0.0/8"
else
    subnet="$(echo $ip | awk -F. '{print $1"."$2"."$3".0/24"}')"
fi

read -p "偵測到內網 IP 為 $ip，允許的 phpMyAdmin 存取網段（預設: $subnet）: " input_subnet
subnet=${input_subnet:-$subnet}

echo "==== 建立 Nginx 設定（限制內網） ===="
cat <<EOF | sudo tee /etc/nginx/sites-available/phpmyadmin
server {
    listen 80;
    server_name _;

    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    location /phpmyadmin {
        allow $subnet;
        deny all;

        location ~ \.php\$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")-fpm.sock;
        }

        location ~* \.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt)\$ {
            root /usr/share/;
        }
    }

    location / {
        return 403;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/phpmyadmin /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "==== 建立 phpMyAdmin 使用者帳號 ===="
while true; do
    read -p "請輸入新使用者名稱（不得為空）: " db_user
    [[ -n "$db_user" ]] && break
    echo "❌ 不可為空，請重新輸入。"
done

while true; do
    read -s -p "請輸入使用者密碼（至少12字元，含大小寫與數字）: " db_pass
    echo
    read -s -p "再次輸入確認: " db_pass_confirm
    echo

    if [[ "$db_pass" != "$db_pass_confirm" ]]; then
        echo "❌ 密碼不一致，請重新輸入。"
        continue
    fi

    if [[ ${#db_pass} -lt 12 ]] || \
       ! [[ "$db_pass" =~ [A-Z] ]] || \
       ! [[ "$db_pass" =~ [a-z] ]] || \
       ! [[ "$db_pass" =~ [0-9] ]]; then
        echo "❌ 密碼太弱，請使用至少12字元並包含大小寫與數字。"
        continue
    fi

    break
done

sudo mariadb -u root -p"${rootpass}" <<EOF
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON *.* TO '${db_user}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

echo ""
echo "✅ 安裝完成！"
echo "📡 請在內網瀏覽器開啟： http://$ip/phpmyadmin"
echo "🔐 使用者帳號：$db_user"
