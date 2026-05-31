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
        http://localhost:8080/
```

## 実装機能

### 監視・可視化
| 機能 | 詳細 |
|------|------|
| Zabbix Web シナリオ | ALB に対して HTTP 200/404/503 を定期チェック |
| Zabbix Agent 監視 | AP サーバーの CPU・メモリ・ディスクを収集 |
| CloudWatch CWAgent | EC2 全台の mem/disk/cpu を 1 分間隔でカスタムメトリクス化（SSM Association で全インスタンスに自動インストール・設定）|
| CloudWatch Dashboard | 5 行 × 2 列（EC2/RDS/ALB/CWAgent/VPC Peering 経路）|
| CloudWatch Alarms | CPU high / Status check / RDS CPU / RDS storage / ALB 5xx / Root 使用（CIS 3.3）/ 不正 API（CIS 3.1）計 7 件 |

### セキュリティ
| 機能 | 詳細 |
|------|------|
| CloudTrail | マルチリージョン・ログ改ざん検知・CloudWatch Logs 転送 |
| CIS Benchmark アラーム | Root 使用 (3.3) / 不正 API 呼び出し (3.1) を検知・SNS 通知 |
| GuardDuty | ML ベース脅威検知（S3 監視 + EBS マルウェアスキャン） |
| Security Hub | CIS AWS Foundations v1.4.0 + AWS FSBP を継続評価 |
| VPC Flow Logs | 両 VPC の全通信を CloudWatch Logs に記録 |
| Secrets Manager | RDS の `manage_master_user_password` により自動生成・管理・自動ローテーション対応。tfstate にパスワードが含まれない |

### インフラ設計
| 設計方針 | 詳細 |
|---------|------|
| ゼロインターネット設計 | EC2 にパブリック IP なし・NAT Gateway 経由でのみ外部アクセス |
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
| VPC Endpoints | ssm / ssmmessages / ec2messages / secretsmanager / logs（Interface）、s3（Gateway）|
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

### 3. Zabbix GUI へのアクセス（SSM ポートフォワーディング）

```powershell
# Windows PowerShell
aws ssm start-session `
  --target (terraform output -raw zabbix_server_instance_id) `
  --document-name AWS-StartPortForwardingSession `
  --parameters "{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8080\"]}"
```

```bash
# macOS / Linux
aws ssm start-session \
  --target $(terraform output -raw zabbix_server_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'
```

ブラウザで `http://localhost:8080/` にアクセス。

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
| NAT Gateway × 2 | ~$2.16 | $0.045/h × 2台（Zabbix VPC + Monitored VPC） |
| EC2 × 3 台 | ~$0.60 | t3.micro × 3 |
| RDS | ~$0.39 | db.t3.micro |
| ALB | ~$0.55 | 最低料金 |
| S3・CloudWatch・その他 | ~$0.30 | |
| **合計** | **~$9.38 / 日** | **~$66 / 週** |

### NAT Gateway のコスト削減

NAT Gateway は初回セットアップ（Zabbix・パッケージのダウンロード）にのみ必要です。  
セットアップ完了後に削除するとコストを削減できます（SSM 接続・Zabbix 監視は VPC Endpoint で継続動作します）。

```bash
# セットアップ完了後に削除（$2.16/日 削減）
terraform destroy \
  -target="aws_nat_gateway.main" \
  -target="aws_nat_gateway.monitored" \
  -target="aws_eip.nat" \
  -target="aws_eip.monitored_nat"
```

> パッケージ更新（`apt-get upgrade` 等）が必要な場合は一時的に再作成してください。
> ```bash
> terraform apply \
>   -target="aws_nat_gateway.main" \
>   -target="aws_nat_gateway.monitored"
> ```

### VPC Interface Endpoint のコスト削減

VPC Interface Endpoint は不使用時に削除することでさらにコストを削減できます。

```bash
# 削除（$5.38/日 削減、SSM 接続不可になるので要注意）
terraform destroy \
  -target="aws_vpc_endpoint.ssm" \
  -target="aws_vpc_endpoint.ssmmessages" \
  -target="aws_vpc_endpoint.ec2messages" \
  -target="aws_vpc_endpoint.secretsmanager" \
  -target="aws_vpc_endpoint.logs" \
  -target="aws_vpc_endpoint.monitored_ssm" \
  -target="aws_vpc_endpoint.monitored_ssmmessages" \
  -target="aws_vpc_endpoint.monitored_ec2messages"

# 復元（SSM 接続が必要なとき）
terraform apply \
  -target="aws_vpc_endpoint.ssm" \
  -target="aws_vpc_endpoint.ssmmessages" \
  -target="aws_vpc_endpoint.ec2messages" \
  -target="aws_vpc_endpoint.secretsmanager" \
  -target="aws_vpc_endpoint.logs" \
  -target="aws_vpc_endpoint.monitored_ssm" \
  -target="aws_vpc_endpoint.monitored_ssmmessages" \
  -target="aws_vpc_endpoint.monitored_ec2messages"
```

## セキュリティリスク（学習用設定による既知の制限）

本リポジトリは **学習・検証目的** の構成です。以下の設定は意図的にコスト・操作性を優先しており、本番環境では必ず対策が必要です。

| 該当リソース | 問題 | 理由（学習用） | 本番での対策 |
|------------|------|-------------|------------|
| `rds.tf` `aws_db_instance.zabbix` | `multi_az = false`: AZ 障害時に自動フェイルオーバーなし（手動復旧に 1〜2 分） | `rds.tf:65` に `# 学習用：true にすると本番同等` と明記。繰り返し apply/destroy するためコスト抑制 | `multi_az = true` |
| `rds.tf` `deletion_protection` | `false`: 誤操作による DB 削除が可能 | `terraform destroy` で DB をクリーンに削除できるようにするため | `true` に変更 |
| `rds.tf` `skip_final_snapshot` | `true`: 削除時にスナップショット未作成、データ永久消失リスク | destroy 後に孤立スナップショットを残さないようにするため | `false` + `final_snapshot_identifier` を設定 |
| `alb.tf` `aws_lb_listener.monitored_http` | HTTP のみ（ポート 80）: 通信が暗号化されていない | ALB は `internal = true` でプライベートサブネット内に閉じており外部通信なし。HTTPS には ACM 証明書が必要なため省略 | HTTPS リスナー（443）追加 + ACM 証明書 + HTTP→HTTPS リダイレクト |
| `vpc.tf` `aws_subnet.public` / `monitored_public` | `map_public_ip_on_launch = true`: 誤って EC2 を公開サブネットに配置した際にパブリック IP が自動付与される | 公開サブネットは NAT Gateway 専用（EC2 は配置しない設計）。NAT Gateway は EIP を使用するため本設定は不要だが、デフォルト値のまま残存 | `false` に変更 |
| `alb.tf` `aws_lb.monitored` | `enable_deletion_protection` 未設定: 誤操作による ALB 削除が可能 | `terraform destroy` でリソースを一括削除できるようにするため | `enable_deletion_protection = true` |
| `alb.tf` `aws_lb.monitored` | `drop_invalid_header_fields` 未設定: HTTP リクエストスマグリング攻撃に対して脆弱 | ALB は Internal でありインターネット通信なし。外部からの L7 攻撃リスクが低い学習構成 | `drop_invalid_header_fields = true` |
| `alb.tf` `aws_s3_bucket.alb_logs` | `force_destroy = true`: バケット削除時にアクセスログが全消失 | `terraform destroy` でバケット内オブジェクトごとクリーンに削除するため | `false` に変更 |
| `cloudtrail.tf` `aws_s3_bucket.cloudtrail` | `force_destroy = true`: 監査ログが全消失（証跡破壊リスク） | 繰り返し apply/destroy する学習用途でクリーンな削除を優先 | `false` に変更 |
| `cloudtrail.tf` `aws_cloudtrail.main` | CloudTrail ログが KMS 暗号化なし（SSE-S3 のみ） | KMS CMK は月額約 $1/key のコストが発生。SSE-S3 で保管時暗号化は確保済み | `kms_key_id` に CMK ARN を指定 |
| `ec2.tf` `aws_instance.monitored_target` | 詳細モニタリング無効（デフォルト 5 分間隔） | CloudWatch Agent + Zabbix Agent で 1 分間隔メトリクスをカバー済み。詳細モニタリングは月額 $3.50/インスタンス | `monitoring = true` |
| `rds.tf` `monitoring_interval` | `0`: Enhanced Monitoring 無効。OS プロセスレベルの詳細が取得不可 | `AWS/RDS` 標準メトリクス（`FreeableMemory`・`CPUUtilization`）で基本モニタリングはカバー済み。Enhanced Monitoring はプロセス単位分析用で学習スコープ外 | `60` + `monitoring_role_arn` を設定 |
| `rds.tf` `performance_insights_enabled` | `false`: SQL 単位の待機分析・スロークエリ特定が不可 | DB チューニングは学習スコープ外。Zabbix 動作確認には不要 | `true` に変更 |
| 各 CloudWatch Logs グループ | CMK 暗号化なし（AWS マネージドキーのみ） | KMS CMK は月額 $1/key のコストと IAM キーポリシー管理が増加 | 各 Log Group に `kms_key_id` を指定 |
| 各 IAM Role | `description` フィールドなし | リソース名と `default_tags`（`Project = zabbix`）で用途・管理元が識別可能 | 各ロールに `description` を追加 |
| `cloudwatch.tf` `aws_sns_topic.zabbix_alerts` | SNS トピックが CMK 暗号化なし | アラート通知はトランジェントなメッセージ。AWS マネージド暗号化で保護済み | `kms_master_key_id` に CMK ARN を指定 |
| `cloudwatch.tf` SNS Subscription | `redrive_policy` なし: 配信失敗メッセージがサイレントに破棄される | 学習目的のメール通知。配信失敗は許容 | DLQ（SQS）を作成し `redrive_policy` を設定 |
| RDS 自動管理シークレット | デフォルト AWS マネージドキーで暗号化: CMK によるキー管理・監査が不可 | AWS マネージドキーでの暗号化は有効。CMK の管理は月額 $1 で学習環境では省略 | `master_user_secret_kms_key_id` に CMK ARN を指定 |
| `cloudtrail.tf` | S3 バケットにバージョニング・MFA Delete なし | MFA Delete は手動操作が必要。学習環境では操作手順の複雑化を避けるため省略 | バージョニング有効化 + MFA Delete を設定 |

> **静的解析では検出されないリスク（インフラ固有）**
>
> | 問題 | 該当箇所 | 理由（学習用） | 本番での対策 |
> |------|---------|-------------|------------|
> | RDS パスワードが設定ファイルに平文記載 | `user_data.sh`（Zabbix Server 設定セクション） | `zabbix_server.conf` には平文パスワードが必要なため、起動時に Secrets Manager から取得して書き込む。`manage_master_user_password` により RDS 側の自動ローテーションは対応済みだが、ローテーション後の `zabbix_server.conf` 再書き込みは未実装 | Secrets Manager ローテーションフック（Lambda）で `zabbix_server.conf` を更新 + `zabbix-server` サービスを再起動 |
> | Zabbix デフォルトパスワード（`Admin / zabbix`） | `user_data.sh:199` | インストール直後はデフォルトパスワード。変更スクリプトは用意済みだが自動実行はされない | 初回ログイン直後に変更必須（[変更スクリプト](terraform/scripts/change_zabbix_password.sh)） |
> | ALB に WAF なし | `alb.tf` | ALB は Internal のため外部からのアクセスなし。WAF のルール設計・コスト（$5/WebACL/月）を省略 | AWS WAF WebACL を ALB に関連付け |
> | AWS Config 未設定 | ― | CloudTrail で API 操作ログを代替。リソース変更の履歴追跡よりも構成の簡潔さを優先 | `aws_config_configuration_recorder` を追加 |
> | GuardDuty / Security Hub の自動修復なし | `security.tf` | 検知ルールと SNS 通知は実装済み。Lambda による自動対応は学習スコープ外 | EventBridge → Lambda による自動 isolation を検討 |

---

## 冗長化の考慮事項

本構成は **コスト最小化** を優先しており、以下のコンポーネントは単一障害点（SPOF）になっています。

### 単一障害点の一覧

| コンポーネント | 現状 | 障害時の影響 | 理由（学習用） | 本番での対策 |
|-------------|------|------------|-------------|------------|
| RDS | Single-AZ（`multi_az = false`） | AZ 障害・インスタンス障害時に DB が停止、Zabbix 全機能停止（自動フェイルオーバーなし） | `rds.tf:65` に `# 学習用：true にすると本番同等` と明記。Multi-AZ はインスタンス費用が 2倍になるためコスト削減で省略 | `multi_az = true`、コスト +$0.39/日 |
| NAT Gateway | 各 VPC 1台・単一 AZ（AZ-a のみ） | その AZ 障害時にプライベートサブネットからのアウトバウンド通信が全断 | 初回セットアップ（パッケージ取得）後は削除可能な設計（「コスト管理」参照）。常時稼働させる場合でも学習用では単一 AZ で許容 | 各 VPC で 2台（AZ-a・AZ-b に各 1台）、コスト +$2.16/日 |
| Zabbix Server EC2 | 単一インスタンス・Auto Recovery なし | ハードウェア障害時に監視が全停止 | Zabbix の Active-Passive 冗長化はデータベース共有・フェイルオーバー設定が複雑。監視基盤の構築方法の学習が目的であり、Zabbix 自体の HA 設計は学習スコープ外 | EC2 Auto Recovery アラーム追加または ASG (min=1) 化 |
| Zabbix Server EBS | `delete_on_termination = true` | インスタンス削除時にデータ（設定・ログ）が消失 | `terraform destroy` でインスタンスごとクリーンに削除するため。学習環境では再 apply でスキーマ・設定を再構築可能な設計（`user_data.sh` で冪等に再セットアップ） | `delete_on_termination = false` + 定期 EBS スナップショット |

### 冗長化済みのコンポーネント

| コンポーネント | 構成 |
|-------------|------|
| AP Server（監視対象） | 2台 × 2 AZ（`monitored_private[0]`・`[1]`） |
| Internal ALB | 2 AZ のプライベートサブネットにまたがって配置 |
| VPC Interface Endpoints | 2 AZ のサブネットに配置（`subnet_ids = aws_subnet.private[*].id`） |
| RDS Subnet Group | 2 AZ のサブネット（Multi-AZ 昇格に即対応できる構成） |

### 本番相当にする場合の追加コスト試算

| 対策 | 追加コスト / 日 |
|------|--------------|
| RDS Multi-AZ 有効化 | +$0.39 |
| NAT Gateway を各 VPC 2台に増設 | +$2.16 |
| EC2 Auto Recovery（追加料金なし） | $0 |
| 合計 | **+$2.55 / 日**（~$18 / 週） |

---

## 適合済みベストプラクティス

実装済みのベストプラクティスです。

| カテゴリ | 内容 |
|---------|------|
| ネットワーク | VPC Flow Logs で全トラフィック記録（両 VPC）|
| 脅威検知 | GuardDuty（S3 ログ監視 + EBS マルウェアスキャン）有効 |
| コンプライアンス | Security Hub（CIS v1.4.0 + FSBP）有効 |
| 監査 | CloudTrail マルチリージョン・グローバルイベント・ログ改ざん検知・CloudWatch Logs 転送 |
| EC2 | IMDSv2 全インスタンスで強制（`http_tokens = required`）|
| EC2 | EBS ルートボリューム全インスタンスで暗号化済み |
| EC2 | `key_name` 未設定（SSH キー不使用・SSM Session Manager のみ）|
| RDS | ストレージ暗号化済み・バックアップ保持 7 日以上 |
| シークレット | RDS `manage_master_user_password` で自動生成・管理・自動ローテーション。tfstate にパスワードが残らない |
| セキュリティグループ | `aws_vpc_security_group_ingress_rule` / `egress_rule` によるルールベース管理（AWS provider v5 推奨）。ルール単位で独立管理し SG 全体の再作成を回避 |
| S3 | 全バケットでパブリックアクセスブロック有効 |
| VPC | SSM / Secrets Manager / CloudWatch Logs / S3 の VPC Endpoints 構成済み |
| 監視 | ALB アクセスログ有効・CloudWatch Dashboard 設定済み・CloudWatch アラーム 7 件（全件アクション設定） |

---

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
