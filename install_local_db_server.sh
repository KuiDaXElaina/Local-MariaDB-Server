#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "❌ 請使用 root 權限執行這個腳本： sudo ./install_local_db_server.sh"
    exit 1
fi

echo "==== 系統更新 ===="
apt update && apt upgrade -y

echo "==== 安裝必要套件 ===="
apt install -y mariadb-server mariadb-client nginx php-fpm php-mysql \
    php-mbstring php-zip php-gd php-json php-curl php-cli php-xml \
    unzip wget curl fail2ban dos2unix

systemctl enable mariadb --now
systemctl enable nginx --now
systemctl enable php*-fpm --now

# 設定 root 密碼
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

mariadb -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${rootpass}';
FLUSH PRIVILEGES;
EOF

echo "✅ MariaDB root 密碼已設定。"

# 安裝 phpMyAdmin
cd /usr/share/
wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
rm -rf phpmyadmin phpMyAdmin-*-all-languages

tar xzf phpMyAdmin-latest-all-languages.tar.gz
mv phpMyAdmin-*-all-languages phpmyadmin
mkdir -p /usr/share/phpmyadmin/tmp
chmod 777 /usr/share/phpmyadmin/tmp
cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
sed -i "s|\['blowfish_secret'\] = ''|\['blowfish_secret'\] = '$(openssl rand -base64 32)'|g" /usr/share/phpmyadmin/config.inc.php

# 偵測內網 IP 與網段
ip=$(hostname -I | awk '{print $1}')
IFS=. read -r i1 i2 i3 i4 <<< "$ip"
subnet="${i1}.${i2}.${i3}.0/24"
read -p "偵測到內網 IP 為 $ip，允許的 phpMyAdmin 存取網段（預設: $subnet）: " input_subnet
subnet=${input_subnet:-$subnet}

# 隨機後台路徑
randpath="admin_$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)"
echo "🛡️ 管理後台路徑將設定為 /$randpath"

echo "$randpath" > /root/phpmyadmin_access_path.txt

cat <<EOF > /etc/nginx/sites-available/phpmyadmin
server {
    listen 80;
    server_name _;

    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    location /$randpath {
        allow $subnet;
        deny all;

        location ~ \.php\$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php\$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")-fpm.sock;
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

ln -sf /etc/nginx/sites-available/phpmyadmin /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# 建立新帳號
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

mariadb -u root -p"${rootpass}" <<EOF
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON *.* TO '${db_user}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# 啟用 Fail2Ban
cat <<EOF > /etc/fail2ban/jail.d/mariadb.conf
[mariadb-auth]
enabled  = true
filter   = mysqld-auth
port     = mysql
logpath  = /var/log/mysql/error.log
maxretry = 3
EOF

systemctl restart fail2ban

# 完成訊息
echo ""
echo "✅ 安裝完成！"
echo "📡 請在內網瀏覽器開啟： http://$ip/$randpath"
echo "🔐 使用者帳號：$db_user"
echo "📄 後台路徑也已記錄於 /root/phpmyadmin_access_path.txt"
