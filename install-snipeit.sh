#!/bin/bash

# ==========================================
# SNIPE-IT installer to debian 12
# ==========================================

# In case of an error the script should stop
set -e

# Check if the running user is root
if [ "$EUID" -ne 0 ]; then
  echo "Please run the script as root (sudo)!"
  exit
fi

# --- CONFIGURATION VARIABLES ---
# Try to find out the ip address automatically.
# If incorrect, you can overwrite it manually eg: SERVER_IP="10.1.1.37"
SERVER_IP=$(hostname -I | awk '{print $1}')
DB_NAME="snipeit"
DB_USER="snipeituser"
# Generating random password but you can change it to a manual one.
DB_PASS=$(openssl rand -base64 12)
TIMEZONE="Europe/Budapest" # Change this to your own timezone.

echo "=================================================="
echo " Snipe-IT Installer Starting..."
echo " IP address: $SERVER_IP"
echo " Database password: $DB_PASS"
echo "=================================================="
sleep 3

echo "[1/9] Updating..."
apt update -q && apt upgrade -y -q

echo "[2/9] Installing dependencies (Apache, MariaDB, PHP)..."
apt install -y apache2 mariadb-server git unzip curl wget nano \
php php-curl php-mysql php-gd php-mbstring php-bcmath php-common php-xml php-zip php-ldap php-intl php-tokenizer

echo "[3/9] Creating Database and Users..."
mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "[4/9] Installing Composer..."
if [ ! -f /usr/local/bin/composer ]; then
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
else
    echo "Composer is already installed"
fi

echo "[5/9] Downloading Snipe-IT..."
cd /var/www/html
# If the folder already exists recloning is aborted.
if [ ! -d "snipe-it" ]; then
    git clone https://github.com/snipe/snipe-it.git snipe-it
else
    echo "The snipe-it folder already exists."
fi
cd snipe-it

echo "[6/9] Installing PHP Dependencies (This might take a while)..."
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --prefer-source

# Configuring Environment Variables (.env) - CRITICAL
echo "[7/9] Setting up configuration files..."
cp .env.example .env

# Most important: adding http:// to IP!
sed -i "s|APP_URL=null|APP_URL=http://${SERVER_IP}|g" .env
sed -i "s|APP_TIMEZONE='UTC'|APP_TIMEZONE='${TIMEZONE}'|g" .env
sed -i "s|DB_DATABASE=snipeit|DB_DATABASE=${DB_NAME}|g" .env
sed -i "s|DB_USERNAME=snipeit|DB_USERNAME=${DB_USER}|g" .env
sed -i "s|DB_PASSWORD=snipeit|DB_PASSWORD=${DB_PASS}|g" .env

if grep -q "REQUIRE_HTTPS" .env; then
    sed -i "s|REQUIRE_HTTPS=true|REQUIRE_HTTPS=false|g" .env
else
    echo "REQUIRE_HTTPS=false" >> .env
fi

php artisan key:generate

echo "[8/9] Configuring permissions..."
chown -R www-data:www-data /var/www/html/snipe-it
chmod -R 755 /var/www/html/snipe-it
chmod -R 775 /var/www/html/snipe-it/storage /var/www/html/snipe-it/public/uploads

echo "[9/9] Configuring Apache VirtualHost..."
cat <<EOF > /etc/apache2/sites-available/snipeit.conf
<VirtualHost *:80>
    ServerName ${SERVER_IP}
    DocumentRoot /var/www/html/snipe-it/public

    <Directory /var/www/html/snipe-it/public>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/snipeit-error.log
    CustomLog \${APACHE_LOG_DIR}/snipeit-access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf
a2ensite snipeit.conf
a2enmod rewrite

php artisan config:clear
php artisan cache:clear

systemctl restart apache2

echo ""
echo "=================================================="
echo " INSTALLATION READY!"
echo "=================================================="
echo "You can reach the site here: http://${SERVER_IP}"
echo ""
echo "Important: During the Pre-Flight check everything should be green."
echo "Have fun!"