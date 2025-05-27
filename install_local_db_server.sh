#!/bin/bash
set -e

# === 檢查是否為 root ===
if [[ "$EUID" -ne 0 ]]; then
  echo "請使用 sudo 或 root 權限執行本腳本。"
  exit 1
fi

echo "==== 系統更新 ===="
apt update && apt upgrade -y

echo "==== 安裝必備套件 ===="
apt install -y mariadb-server mariadb-client nginx php-fpm php-mysql php-mbstring php-zip php-gd php-json php-curl php-cli php-xml wget unzip fail2ban

echo "==== 啟用 MariaDB ===="
systemctl enable mariadb
systemctl start mariadb

# === 設定 root 密碼 ===
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
    if [[ ${#rootpass} -lt 12 || ! "$rootpass" =~ [A-Z] || ! "$rootpass" =~ [a-z] || ! "$rootpass" =~ [0-9] ]]; then
        echo "❌ 密碼太弱，請使用至少12字元並包含大小寫與數字。"
        continue
    fi
    break
done

mariadb -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${rootpass}';
FLUSH PRIVILEGES;
EOF

echo "✅ MariaDB root 密碼已設定。"

echo "==== 啟用 Nginx ===="
systemctl enable nginx
systemctl start nginx

# === 啟用 PHP-FPM（自動偵測版本） ===
php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
php_fpm_service="php${php_version}-fpm"
echo "==== 啟用 PHP FPM 服務 ($php_fpm_service) ===="
systemctl enable "$php_fpm_service"
systemctl start "$php_fpm_service"

# === 安裝 phpMyAdmin ===
echo "==== 安裝 phpMyAdmin ===="
cd /usr/share/
wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
tar xzf phpMyAdmin-latest-all-languages.tar.gz
rm phpMyAdmin-latest-all-languages.tar.gz
mv phpMyAdmin-*-all-languages phpmyadmin
mkdir -p /usr/share/phpmyadmin/tmp
chmod 777 /usr/share/phpmyadmin/tmp
cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php

# 生成 32 字元的 blowfish_secret
blowfish_secret=$(openssl rand -base64 32 | cut -c1-32)
sed -i "s|\['blowfish_secret'\] = ''|\['blowfish_secret'\] = '${blowfish_secret}'|g" /usr/share/phpmyadmin/config.inc.php

echo "✅ phpMyAdmin 已安裝。"

# === 偵測內網 IP 與網段 ===
ip=$(hostname -I | awk '{print $1}')
IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
default_subnet="$i1.$i2.$i3.0/24"

read -p "偵測到內網 IP 為 $ip，允許的 phpMyAdmin 存取網段（預設: $default_subnet）: " input_subnet
subnet=${input_subnet:-$default_subnet}

# === 隨機後台路徑 ===
admin_path="admin_$(openssl rand -hex 4)"

echo "🛡️ 管理後台路徑將設定為 /$admin_path"

# === 建立 Nginx 設定 ===
cat <<EOF > /etc/nginx/sites-available/phpmyadmin
server {
    listen 80;
    server_name _;

    location /$admin_path {
        alias /usr/share/phpmyadmin/;
        index index.php index.html index.htm;

        allow $subnet;
        deny all;

        try_files \$uri \$uri/ @phpmyadmin;

        location ~ \.php\$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
        }
    }

    location @phpmyadmin {
        rewrite ^/$admin_path/(.*)$ /$admin_path/index.php?\$1 last;
    }

    location / {
        return 403;
    }
}
EOF

ln -sf /etc/nginx/sites-available/phpmyadmin /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# === 建立新資料庫使用者 ===
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

    if [[ ${#db_pass} -lt 12 || ! "$db_pass" =~ [A-Z] || ! "$db_pass" =~ [a-z] || ! "$db_pass" =~ [0-9] ]]; then
        echo "❌ 密碼太弱，請使用至少12字元並包含大小寫與數字。"
        continue
    fi

    break
done

mariadb -u root -p"${rootpass}" <<EOF
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON *.* TO '${db_user}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# === fail2ban 設定（MariaDB 防暴力破解） ===
cat <<EOF > /etc/fail2ban/jail.d/mariadb.local
[mariadb]
enabled = true
port = mysql
filter = mysqld-auth
logpath = /var/log/mysql/error.log
maxretry = 5
bantime = 3600
EOF

systemctl restart fail2ban

# === 完成提示 ===
echo ""
echo "✅ 安裝完成！"
echo "📡 請在內網瀏覽器開啟： http://$ip/$admin_path"
echo "🔐 使用者帳號：$db_user"
echo "🔑 密碼：請使用您剛才設定的密碼"
echo "⚠️ 請務必記住您的使用者名稱和密碼！"
