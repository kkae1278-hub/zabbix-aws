# Zabbix Monitoring on AWS

AWS 上に Terraform で構築する **Zabbix 監視基盤**のサンプルリポジトリです。  
AWS SAP / SCS / ANS 資格レベルのセキュリティ・監視設計を実装しています。

## アーキテクチャ概要

```
                          AWS Cloud (ap-northeast-1)
 ┌──────────────────────────────────────────────────────────────────────┐
 │                                                                      │
 │  Zabbix VPC (10.0.0.0/16)       Monitored VPC (10.1.0.0/16)        │
 │  ┌────────────────────────┐     ┌────────────────────────┐          │
 │  │  [Private Subnet]      │     │  [Private Subnet]      │          │
 │  │  Zabbix Server         │◄────►  Internal ALB           │          │
 │  │  Ubuntu 22.04 t3.micro │VPC  │  AP Server × 2         │          │
 │  │                        │Peer │  (Amazon Linux 2023)   │          │
 │  │  RDS MySQL 8.0         │─────│                        │          │
 │  │  db.t3.micro           │     │  VPC Endpoints (SSM)   │          │
 │  │                        │     └────────────────────────┘          │
 │  │  VPC Endpoints         │                                          │
 │  │  (SSM/SM/Logs/S3)      │     CloudWatch Logs ◄── VPC Flow Logs   │
 │  └────────────────────────┘     GuardDuty → EventBridge → SNS      │
 │           │                     CloudTrail → S3 / CloudWatch        │
 │      SSM Port Forward           Security Hub (CIS v1.4 + FSBP)     │
 │           │                                                          │
 └───────────┼──────────────────────────────────────────────────────────┘
             │
        Local PC (Browser)
        http://localhost:8080/zabbix
```

## 実装機能

### 監視・可視化
| 機能 | 詳細 |
|------|------|
| Zabbix Web シナリオ | ALB に対して HTTP 200/404/503 を定期チェック |
| Zabbix Agent 監視 | AP サーバーの CPU・メモリ・ディスクを収集 |
| CloudWatch CWAgent | EC2 全台の mem/disk/cpu を 1 分間隔でカスタムメトリクス化 |
| CloudWatch Dashboard | 5 行 × 2 列（EC2/RDS/ALB/CWAgent/VPC Peering 経路）|
| CloudWatch Alarms | CPU high / Status check / RDS CPU / RDS storage / ALB 5xx |

### セキュリティ
| 機能 | 詳細 |
|------|------|
| CloudTrail | マルチリージョン・ログ改ざん検知・CloudWatch Logs 転送 |
| CIS Benchmark アラーム | Root 使用 (3.3) / 不正 API 呼び出し (3.1) を検知・SNS 通知 |
| GuardDuty | ML ベース脅威検知（S3 監視 + EBS マルウェアスキャン） |
| Security Hub | CIS AWS Foundations v1.4.0 + AWS FSBP を継続評価 |
| VPC Flow Logs | 両 VPC の全通信を CloudWatch Logs に記録 |
| Secrets Manager | RDS パスワードを自動生成・ローテーション対応 |

### インフラ設計
| 設計方針 | 詳細 |
|---------|------|
| ゼロインターネット設計 | EC2 にパブリック IP なし・NAT Gateway なし（通常運用） |
| SSH レス | SSM Session Manager + Port Forwarding のみ |
| VPC Peering | Zabbix VPC ↔ Monitored VPC（最小ルーティング） |
| Terraform Remote State | S3 バックエンド + DynamoDB State ロック |

## 主なリソース

| リソース | 仕様 |
|---------|------|
| Zabbix Server | Ubuntu 22.04 / t3.micro / プライベートサブネット |
| RDS | MySQL 8.0 / db.t3.micro / 20GB gp3 |
| AP Server × 2 | Amazon Linux 2023 / t3.micro / 内部 ALB 配下 |
| Internal ALB | Monitored VPC / アクセスログ → S3 |
| VPC Endpoints | ssm / ssmmessages / ec2messages / secretsmanager / logs（Interface） |
| CloudTrail | マルチリージョントレイル / S3 保存 90 日 / CIS アラーム |
| GuardDuty | S3 保護 + EC2 マルウェアスキャン |
| Security Hub | CIS v1.4.0 + AWS FSBP |
| VPC Flow Logs | 両 VPC ALL トラフィック → CloudWatch Logs 30 日保持 |

## 前提条件

- Terraform >= 1.6.0
- AWS CLI v2
- AWS IAM Identity Center（SSO）設定済み
- Session Manager Plugin インストール済み

## セットアップ手順

### 1. AWS SSO ログイン

```bash
aws configure sso
aws sso login --profile <profile-name>
export AWS_PROFILE=<profile-name>
```

### 2. Terraform 初期化・適用

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

> **注意:** 初回セットアップ時は外部リポジトリ（`repo.zabbix.com`）へのアクセスが必要です。  
> NAT Gateway を一時的に追加して Zabbix をインストール後に削除してください。  
> 詳細は [docs/troubleshooting.md](docs/troubleshooting.md) を参照してください。

### 3. Zabbix GUI へのアクセス（SSM ポートフォワーディング）

```bash
aws ssm start-session \
  --target <zabbix-server-instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'
```

ブラウザで `http://localhost:8080/zabbix` にアクセス。

- **Username:** `Admin`
- **Password:** 初回ログイン後すぐに変更してください（[パスワード変更スクリプト](terraform/scripts/change_zabbix_password.sh)）

### 4. 接続テスト

```bash
ALB=<monitored_alb_dns_name>
curl -i http://$ALB/         # 200 OK
curl -i http://$ALB/notfound # 404 Not Found
curl -i http://$ALB/error    # 503 Service Unavailable
```

## コスト管理

| コスト要因 | 目安 / 日 | 備考 |
|-----------|----------|------|
| VPC Interface Endpoints | ~$5.38 | 8 エンドポイント × 2 AZ × $0.014/h |
| EC2 × 3 台 | ~$0.60 | t3.micro × 3 |
| RDS | ~$0.39 | db.t3.micro |
| ALB | ~$0.55 | 最低料金 |
| S3・CloudWatch・その他 | ~$0.30 | |
| **合計** | **~$7.22 / 日** | **~$50 / 週** |

VPC Interface Endpoint は不使用時に削除することでコストを削減できます:

```bash
# 削除（コスト削減）
terraform destroy \
  -target="aws_vpc_endpoint.ssm" \
  -target="aws_vpc_endpoint.ssm_messages" \
  -target="aws_vpc_endpoint.ec2_messages" \
  -target="aws_vpc_endpoint.secretsmanager" \
  -target="aws_vpc_endpoint.logs" \
  -target="aws_vpc_endpoint.monitored_ssm" \
  -target="aws_vpc_endpoint.monitored_ssm_messages" \
  -target="aws_vpc_endpoint.monitored_ec2_messages"

# 復元（SSM 接続が必要なとき）
terraform apply \
  -target="aws_vpc_endpoint.ssm" \
  -target="aws_vpc_endpoint.ssm_messages" \
  ...
```

## Terraform Remote State のセットアップ

```bash
# 1. Bootstrap（S3 バケット・DynamoDB 作成）
cd terraform/bootstrap
terraform init
terraform apply

# 2. 出力された backend_config を terraform/main.tf の backend ブロックに貼り付け

# 3. State を S3 に移行
cd ../
terraform init -migrate-state
```

## ドキュメント

| ファイル | 内容 |
|---------|------|
| [構築手順書](docs/構築手順書.md) | セットアップ全体手順・チェックリスト・コスト管理 |
| [Zabbix 監視設定手順](docs/zabbix_monitoring_setup.md) | Web シナリオ・Agent 監視・アラートアクション・自動登録 |
| [トラブルシューティング](docs/troubleshooting.md) | 構築時にハマった問題と解決策 |
| [アーキテクチャ図](docs/architecture.drawio) | draw.io 形式の構成図 |
