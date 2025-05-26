# 📦 Local MariaDB Server Installer (內網資料庫安裝腳本)

一鍵自動安裝 **MariaDB + phpMyAdmin + Nginx + PHP** 的內網伺服器環境，專為 Ubuntu 22.04 設計，並預設限制僅允許內網存取 phpMyAdmin。

---

## 🧩 功能特色

- ✅ 安裝 MariaDB 並安全設定 root 密碼
- ✅ 安裝並設定 phpMyAdmin（圖形化資料庫管理介面）
- ✅ 安裝與配置 Nginx + PHP-FPM
- ✅ 自動偵測本機 IP，限制內網網段存取 phpMyAdmin
- ✅ 不在腳本中儲存任何明文密碼，**安全可開源**
- ✅ 完整互動流程，適合教學與本地部署環境

---

## 📋 系統需求

- 作業系統：Ubuntu 22.04 LTS
- 權限：需 `sudo` 權限
- 網路：可連上 phpMyAdmin 官方網站以下載最新版

---

## 🚀 安裝方式

```bash
# 下載腳本
git clone https://github.com/你的帳號/local-db-server-installer.git
cd local-db-server-installer

# 執行腳本（自動化並包含互動輸入）
chmod +x install_local_db_server.sh
./install_local_db_server.sh
```

---

## 📡 使用方式

安裝完成後，請使用內網瀏覽器造訪：

```
http://內網IP/phpmyadmin
```

輸入你剛剛設定的資料庫帳號與密碼登入。

---

## 🔐 安全建議

- 不建議將此服務暴露在公網上
- 預設限制 `phpMyAdmin` 僅允許內網段存取（例如 `192.168.0.0/16`）
- 若需開放遠端管理，請改用 SSH + tunnel 或 VPN 存取內網
- 所有密碼皆為互動輸入，不應硬編碼於腳本中

---

## 🧰 進階自訂

- phpMyAdmin 設定檔位置：
  ```
  /usr/share/phpmyadmin/config.inc.php
  ```

- Nginx 網站設定檔：
  ```
  /etc/nginx/sites-available/phpmyadmin
  ```

- MariaDB 帳號管理：
  ```
  sudo mariadb -u root -p
  ```

---

## 📄 授權

本專案採用 MIT License 授權，歡迎自由使用與修改。請勿將此腳本與任何含預設密碼的腳本一同佈署於公開環境。