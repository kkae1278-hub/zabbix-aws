#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ============================================================
# Zabbix Server Setup Script (Ubuntu 22.04)
# ============================================================

PROJECT_NAME="${project_name}"
ZABBIX_VERSION="${zabbix_version}"
SECRET_ARN="${secret_arn}"
AWS_REGION="${aws_region}"
LOG_GROUP="${log_group}"

exec > >(tee /var/log/zabbix-setup.log) 2>&1
echo "=== Zabbix Setup Start: $(date) ==="

# ============================================================
# 1. System Update
# ============================================================
apt-get update -y
apt-get upgrade -y

# ============================================================
# 2. CloudWatch Agent
# SSM Association（cloudwatch_agent.tf）が全 EC2 に対して
# インストール・設定を行うためここでは省略
# ============================================================

# ============================================================
# 3. Zabbix Repository
# ============================================================
wget -q "https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu22.04_all.deb" \
  -O /tmp/zabbix-release.deb
dpkg -i /tmp/zabbix-release.deb
apt-get update -y

# ============================================================
# 4. Install Zabbix Server / Web / MySQL Client
# ============================================================
apt-get install -y \
  zabbix-server-mysql \
  zabbix-frontend-php \
  zabbix-nginx-conf \
  zabbix-sql-scripts \
  mysql-client \
  jq \
  awscli

# ============================================================
# 5. Get DB Credentials from Secrets Manager
# ============================================================
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)

DB_HOST=$(echo "$SECRET" | jq -r '.host')
DB_PORT=$(echo "$SECRET" | jq -r '.port')
DB_NAME=$(echo "$SECRET" | jq -r '.dbname')
DB_USER=$(echo "$SECRET" | jq -r '.username')
DB_PASS=$(echo "$SECRET" | jq -r '.password')

# ============================================================
# 6. Import Zabbix DB Schema
# ============================================================
echo "=== Importing Zabbix schema ==="

for i in $(seq 1 30); do
  if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1;" > /dev/null 2>&1; then
    echo "DB connection OK"
    break
  fi
  echo "Waiting for DB... ($i/30)"
  sleep 10
done

TABLE_COUNT=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" 2>/dev/null | tail -1)

if [ "$TABLE_COUNT" = "0" ] || [ -z "$TABLE_COUNT" ]; then
  zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | \
    mysql --default-character-set=utf8mb4 \
    -h "$DB_HOST" -P "$DB_PORT" \
    -u "$DB_USER" -p"$DB_PASS" "$DB_NAME"
  echo "Schema imported successfully"
else
  echo "Schema already exists, skipping import"
fi

# ============================================================
# 7. Zabbix Server Configuration
# ============================================================
cat <<EOF > /etc/zabbix/zabbix_server.conf
DBHost=$DB_HOST
DBPort=$DB_PORT
DBName=$DB_NAME
DBUser=$DB_USER
DBPassword=$DB_PASS

StartPollers=10
StartPingers=5
StartTrappers=5
StartDiscoverers=3
CacheSize=128M
HistoryCacheSize=64M
TrendCacheSize=32M
ValueCacheSize=256M

LogFile=/var/log/zabbix/zabbix_server.log
LogFileSize=100
DebugLevel=3

AlertScriptsPath=/usr/lib/zabbix/alertscripts
ExternalScripts=/usr/lib/zabbix/externalscripts
EOF

# ============================================================
# 8. Nginx / PHP-FPM Configuration
# ============================================================
# Disable default nginx site to avoid port conflict
rm -f /etc/nginx/sites-enabled/default

cat <<'EOF' > /etc/nginx/conf.d/zabbix.conf
server {
    listen      80;
    server_name _;
    root        /usr/share/zabbix;
    index       index.php;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        fastcgi_pass  unix:/run/php/zabbix.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include       fastcgi_params;
    }
}
EOF

# PHP-FPM timezone setting
PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "8.1")
PHP_FPM_CONF="/etc/php/$${PHP_VER}/fpm/pool.d/zabbix.conf"
if [ -f "$PHP_FPM_CONF" ]; then
  sed -i 's/^;*php_value\[date\.timezone\].*/php_value[date.timezone] = Asia\/Tokyo/' "$PHP_FPM_CONF"
fi

# ============================================================
# 9. Start Services
# ============================================================
# zabbix-server: use --no-block to avoid waiting on PID file creation
systemctl enable zabbix-server
systemctl start --no-block zabbix-server

# nginx: reload config if already running, otherwise start
systemctl enable nginx
systemctl reload-or-restart nginx

# PHP-FPM
systemctl enable "php$${PHP_VER}-fpm" 2>/dev/null || systemctl enable php-fpm 2>/dev/null || true
systemctl start "php$${PHP_VER}-fpm" 2>/dev/null || systemctl start php-fpm 2>/dev/null || true

echo "=== Zabbix Setup Complete: $(date) ==="
echo "  Web UI: http://localhost/ (via SSM port forward)"
echo "  Default login: Admin / zabbix"
