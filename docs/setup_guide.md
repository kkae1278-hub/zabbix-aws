# Zabbix on AWS 構築手順書

## 概要

AWS 上に Zabbix 7.x 監視基盤を構築する手順書です。
SAP/SCS/ANS レベルのポートフォリオ向け本格構成を想定しています。

---

## アーキテクチャ構成図

```
Internet
    │
    ▼
[Route 53] (オプション)
    │
    ▼
[ALB] ─── Public Subnet (AZ-1a / AZ-1c)
    │       ├── NAT Gateway
    │
    ▼
[Zabbix Server EC2] ─── Private Subnet (AZ-1a)
    │   ├── t3.medium / Amazon Linux 2023
    │   ├── Zabbix Server 7.x
    │   └── SSM Session Manager でアクセス
    │
    ▼
[RDS MySQL 8.0] ─── Private Subnet (Multi-AZ)
    │
[監視対象 EC2] ─── Private Subnet (AZ-1c)
    └── Zabbix Agent 2
```

---

## 前提条件

- AWS アカウント（AdministratorAccess 相当の権限）
- Terraform >= 1.6.0 インストール済み
- AWS CLI v2 インストール・設定済み
- Session Manager Plugin インストール済み

```bash
# AWS CLI 設定確認
aws sts get-caller-identity

# Session Manager Plugin インストール（macOS）
brew install --cask session-manager-plugin

# Session Manager Plugin インストール（Windows）
# https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
```

---

## 手順 1: Terraform 初期化・デプロイ

### 1-1. リポジトリ準備

```bash
cd ~/zabbix-aws/terraform
```

### 1-2. 変数ファイル作成

```bash
cat <<'EOF' > terraform.tfvars
project_name         = "zabbix"
aws_region           = "ap-northeast-1"
vpc_cidr             = "10.0.0.0/16"
zabbix_instance_type = "t3.medium"
rds_instance_class   = "db.t3.small"
zabbix_version       = "7.0"
sns_email            = "your-email@example.com"  # アラート通知先

# ALB へのアクセス制限（自分のIPに絞ること）
# allowed_cidr_blocks = ["xxx.xxx.xxx.xxx/32"]
EOF
```

### 1-3. Terraform 初期化・プラン確認

```bash
terraform init
terraform plan
```

### 1-4. デプロイ実行

```bash
terraform apply
# "yes" を入力して実行
```

### 1-5. 出力確認

```bash
terraform output
```

出力例：
```
alb_dns_name                = "http://zabbix-alb-xxxxxxxxxx.ap-northeast-1.elb.amazonaws.com/zabbix"
ssm_connect_command         = "aws ssm start-session --target i-xxxxxxxxxx --region ap-northeast-1"
zabbix_server_instance_id   = "i-xxxxxxxxxx"
```

---

## 手順 2: Zabbix セットアップ状態確認

### 2-1. SSM でサーバーに接続

```bash
# terraform output の ssm_connect_command を使用
aws ssm start-session --target i-xxxxxxxxxx --region ap-northeast-1
```

### 2-2. セットアップログ確認

```bash
# セットアップ進捗確認
sudo tail -f /var/log/zabbix-setup.log

# Zabbix Server 起動確認
sudo systemctl status zabbix-server

# Nginx 起動確認
sudo systemctl status nginx

# PHP-FPM 起動確認
sudo systemctl status php-fpm
```

### 2-3. DB 接続確認

```bash
# Secrets Manager から認証情報取得
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "zabbix/rds/password" \
  --region ap-northeast-1 \
  --query SecretString --output text)

DB_HOST=$(echo $SECRET | jq -r '.host')
DB_USER=$(echo $SECRET | jq -r '.username')
DB_PASS=$(echo $SECRET | jq -r '.password')

# MySQL 接続テスト
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" zabbix -e "SHOW TABLES;" | head -20
```

---

## 手順 3: Zabbix Web UI 初期設定

### 3-1. ブラウザでアクセス

```
http://<ALB_DNS_NAME>/zabbix
```

### 3-2. セットアップウィザード

1. **Welcome** → Next step
2. **Check of pre-requisites** → すべて OK であることを確認 → Next step
3. **Configure DB connection**：
   - Database host: `<RDS エンドポイント>` (terraform output で確認)
   - Database port: `3306`
   - Database name: `zabbix`
   - User: `zabbix`
   - Password: Secrets Manager から取得した値
4. **Settings**：
   - Zabbix server name: `Zabbix on AWS`
   - Default time zone: `Asia/Tokyo`
5. **Pre-installation summary** → Next step
6. **Install** → Finish

### 3-3. 初回ログイン

- URL: `http://<ALB_DNS_NAME>/zabbix`
- ユーザー: `Admin`
- パスワード: `zabbix` **(必ず変更すること)**

### 3-4. 管理者パスワード変更

1. 右上アイコン → User settings
2. Change password → 新しいパスワードを設定

---

## 手順 4: 監視対象 EC2 の登録

### 4-1. Zabbix Agent の起動確認

```bash
# 監視対象 EC2 に SSM 接続
aws ssm start-session --target <monitored-target-instance-id> --region ap-northeast-1

# Agent 状態確認
sudo systemctl status zabbix-agent2
sudo tail -f /var/log/zabbix/zabbix_agent2.log
```

### 4-2. Zabbix Web UI でホスト登録

1. Configuration → Hosts → Create host
2. **Host** タブ：
   - Host name: `monitored-target` (Instance ID を推奨)
   - Templates: `Linux by Zabbix agent`
   - Groups: `Linux servers`
3. **Interfaces** タブ：
   - Type: `Agent`
   - IP address: `<監視対象のプライベート IP>`
   - Port: `10050`
4. **Add** をクリック

### 4-3. 接続確認

- Monitoring → Hosts で Status が `Enabled` かつ `ZBX` アイコンが緑になることを確認

---

## 手順 5: SNS アラート設定（Zabbix → SNS → メール）

### 5-1. Lambda + SNS 連携（オプション）

Zabbix の Alert Script から SNS に通知する場合：

```bash
# アラートスクリプトディレクトリ
sudo mkdir -p /usr/lib/zabbix/alertscripts
sudo cat <<'SCRIPT' > /usr/lib/zabbix/alertscripts/sns_notify.sh
#!/bin/bash
SNS_TOPIC_ARN="$1"
SUBJECT="$2"
MESSAGE="$3"

aws sns publish \
  --topic-arn "$SNS_TOPIC_ARN" \
  --subject "$SUBJECT" \
  --message "$MESSAGE" \
  --region ap-northeast-1
SCRIPT
sudo chmod +x /usr/lib/zabbix/alertscripts/sns_notify.sh
```

### 5-2. Zabbix で Media Type 設定

1. Administration → Media types → Create media type
2. Type: `Script`
3. Script name: `sns_notify.sh`
4. Script parameters:
   - `{$SNS_TOPIC_ARN}`
   - `{ALERT.SUBJECT}`
   - `{ALERT.MESSAGE}`

---

## 手順 6: 動作確認チェックリスト

```
[ ] Terraform apply が正常完了
[ ] ALB DNS でブラウザアクセス可能
[ ] Zabbix Web UI 初期設定完了
[ ] Admin パスワード変更済み
[ ] 監視対象 EC2 が Zabbix 上で緑（ZBX）表示
[ ] CPU/メモリのグラフが表示されている
[ ] CloudWatch ダッシュボードで EC2/RDS メトリクス確認
[ ] SNS メールが届いている（サブスクリプション承認）
```

---

## 手順 7: 後片付け（学習終了後）

```bash
# リソース全削除
terraform destroy
# "yes" を入力して実行
```

> **注意**: destroy 前に Terraform state を確認し、削除対象を把握すること。

---

## コスト目安（ap-northeast-1、1日あたり）

| リソース | 仕様 | 概算コスト |
|---|---|---|
| EC2 (Zabbix Server) | t3.medium | ~$0.067/h |
| EC2 (監視対象) | t3.micro | ~$0.017/h |
| RDS MySQL | db.t3.small | ~$0.034/h |
| NAT Gateway | - | ~$0.062/h + データ転送 |
| ALB | - | ~$0.024/h |
| VPC Endpoints | 5本 × Interface | ~$0.014/h × 5 |
| **合計（概算）** | | **~$0.3〜0.5/h** |

> 学習目的の場合は使わない時間は **terraform destroy** または EC2/RDS を停止して節約すること。

---

## トラブルシューティング

### Zabbix Web UI にアクセスできない

```bash
# ALB ターゲットヘルスチェック確認
aws elbv2 describe-target-health \
  --target-group-arn <tg-arn> \
  --region ap-northeast-1

# EC2 の user_data 実行状況確認
aws ssm start-session --target <instance-id>
sudo tail -100 /var/log/zabbix-setup.log
```

### Zabbix Server が DB に接続できない

```bash
# Security Group 確認（3306 ポート）
aws ec2 describe-security-groups --group-ids <rds-sg-id>

# RDS エンドポイント疎通確認（EC2 上から）
nc -zv <rds-endpoint> 3306
```

### SSM Session Manager で接続できない

```bash
# IAM ロール確認
aws iam get-instance-profile --instance-profile-name zabbix-server-profile

# VPC Endpoint 確認
aws ec2 describe-vpc-endpoints --filters "Name=service-name,Values=*ssm*"
```
