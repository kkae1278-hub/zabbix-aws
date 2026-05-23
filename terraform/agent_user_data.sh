#!/bin/bash
set -euo pipefail

# ============================================================
# Zabbix Agent Setup Script (Amazon Linux 2023)
# ============================================================

PROJECT_NAME="${project_name}"
ZABBIX_VERSION="${zabbix_version}"
SERVER_IP="${server_ip}"
AWS_REGION="${aws_region}"

exec > >(tee /var/log/zabbix-agent-setup.log) 2>&1
echo "=== Zabbix Agent Setup Start: $(date) ==="

# ============================================================
# 1. System Update
# ============================================================
dnf update -y

# ============================================================
# 2. Zabbix Agent 2
# ============================================================
rpm -Uvh "https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/alma/9/x86_64/zabbix-release-$ZABBIX_VERSION-1.el9.noarch.rpm" || \
  dnf install -y "https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/rhel/9/x86_64/zabbix-release-latest-$ZABBIX_VERSION.el9.noarch.rpm" || true

dnf clean all
dnf install -y zabbix-agent2 || true

# Get instance metadata via IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id || echo "zabbix-agent")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

cat <<EOF > /etc/zabbix/zabbix_agent2.conf
PidFile=/run/zabbix/zabbix_agent2.pid
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=10

Server=$SERVER_IP
ServerActive=$SERVER_IP
Hostname=$INSTANCE_ID

Plugins.SystemRun.EnableRemoteCommands=0
EOF

systemctl enable --now zabbix-agent2 || true

# ============================================================
# 3. nginx (Connection Test Endpoints)
# ============================================================
dnf install -y nginx

# 200 OK page
cat <<EOF > /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html>
<head><title>AP Server - 200 OK</title></head>
<body>
  <h1>200 OK</h1>
  <p>Instance ID: $INSTANCE_ID</p>
  <p>Private IP: $PRIVATE_IP</p>
  <p>Project: ${project_name}</p>
</body>
</html>
EOF

# 5xx test endpoint
cat <<'EOF' > /etc/nginx/default.d/test-locations.conf
location /error {
    return 503 "Service Unavailable (test)";
}
EOF

systemctl enable --now nginx

echo "=== Setup Complete: $(date) ==="
echo "  200 OK : curl http://<ALB>/"
echo "  4xx    : curl http://<ALB>/notfound"
echo "  5xx    : curl http://<ALB>/error"
