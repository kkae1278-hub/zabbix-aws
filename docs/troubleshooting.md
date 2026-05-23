# Zabbix on AWS 構築 トラブルシュートまとめ

Terraform + AWS で Zabbix 監視基盤を構築する際に実際にハマった問題と解決策をまとめます。

---

## 1. Amazon Linux 2023 では Zabbix 7.0 がインストールできない

### 症状

```
nothing provides liblber.so.2()(64bit) needed by zabbix-server-mysql
nothing provides libOpenIPMI.so.0()(64bit) needed by zabbix-server-mysql
```

### 原因

Zabbix 7.0 の el9 パッケージ（RHEL9 / AlmaLinux9 向け）は `openldap` と `OpenIPMI` の特定バージョンに依存しているが、Amazon Linux 2023 のリポジトリにはこれらが含まれていない。

### 解決策

**Ubuntu 22.04 LTS** を使用する。Zabbix は Ubuntu 22.04 の公式パッケージを提供しており、依存関係の問題が発生しない。

```hcl
# Terraform AMI 設定
data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
```

---

## 2. プライベートサブネットから外部リポジトリに接続できない

### 症状

```
Curl error (28): Timeout was reached for https://repo.zabbix.com/...
```

### 原因

Zabbix VPC にインターネット経路（NAT Gateway）がなく、`repo.zabbix.com` への接続がタイムアウトする。

### 解決策

初回セットアップ時のみ NAT Gateway を追加し、パッケージインストール完了後に削除する。

```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]
}
```

> **コスト注意:** NAT Gateway は約 $0.062/時間。セットアップ完了後は `terraform destroy -target` で削除する。

---

## 3. Amazon Linux 2023 の dnf が S3 VPC Endpoint なしでタイムアウトする

### 症状

```
Curl error (28): Timeout was reached for
https://al2023-repos-ap-northeast-1-xxx.s3.dualstack.ap-northeast-1.amazonaws.com/...
```

### 原因

Amazon Linux 2023 のパッケージリポジトリは S3 上に置かれている。プライベートサブネットから S3 に到達するには S3 Gateway Endpoint が必要。

### 解決策

各 VPC に S3 Gateway Endpoint を追加する。

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}
```

---

## 4. user_data.sh の `set -e` でスクリプトが途中終了する

### 症状

EC2 起動後にパッケージインストールが途中で失敗し、後続の設定（nginx 起動など）が一切実行されない。

### 原因

`set -euo pipefail` を指定していると、任意のコマンドが失敗した時点でスクリプトが即終了する。

### 解決策

`set -euo pipefail` を維持したまま、失敗しても継続したいコマンドに `|| true` を付ける。  
（`-e` を外すと予期しないエラーが無視されるため、現行の `user_data.sh` では `-e` は保持している）

```bash
# 失敗しても続行する場合
systemctl enable "php$${PHP_VER}-fpm" 2>/dev/null || systemctl enable php-fpm 2>/dev/null || true
systemctl start "php$${PHP_VER}-fpm" 2>/dev/null || systemctl start php-fpm 2>/dev/null || true
```

---

## 5. Terraform templatefile 内で bash の `${}` がテンプレート変数と衝突する

### 症状

```
Invalid value for "vars" parameter: vars map does not contain key "PHP_VER"
```

### 原因

Terraform の `templatefile` 関数はファイル全体の `${...}` をテンプレート変数として解釈するため、bash スクリプト内の `${PHP_VER}` も変数展開しようとする。

### 解決策

bash のブレース展開を使いたい場合は `$${VAR}` と二重の `$` でエスケープする。

```bash
# NG: Terraform がテンプレート変数として解釈してしまう
PHP_FPM_CONF="/etc/php/${PHP_VER}/fpm/pool.d/zabbix.conf"

# OK: $$ でエスケープする
PHP_FPM_CONF="/etc/php/$${PHP_VER}/fpm/pool.d/zabbix.conf"
```

---

## 6. IMDSv2 強制時は curl に Token ヘッダーが必要

### 症状

EC2 メタデータの取得に失敗し、インスタンス ID やプライベート IP が取得できない。

### 原因

Terraform で `http_tokens = "required"` を設定した場合（IMDSv2 強制）、従来の IMDSv1 の curl コマンドは 401 エラーになる。

### 解決策

```bash
# IMDSv2 対応の書き方
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)
```

---

## 7. systemctl enable --now がサービス起動待ちでブロックされる

### 症状

`user_data.sh` が `systemctl enable --now zabbix-server` で20分以上停止し、後続の nginx・PHP-FPM 起動コマンドが実行されない。

### 原因

Zabbix Server が PID ファイルの生成に時間がかかり、systemd が `activating` 状態のまま待ち続ける。

```
zabbix-server.service: Can't open PID file /run/zabbix/zabbix_server.pid (yet?)
```

### 解決策

`enable` と `start` を分け、start はノンブロッキングにする。

```bash
# NG: 起動完了を待ってしまう
systemctl enable --now zabbix-server

# OK: 起動を待たずに次の処理へ進む
systemctl enable zabbix-server
systemctl start --no-block zabbix-server
```

---

## 8. PowerShell で AWS CLI に JSON パラメータを渡すと文字化けする

### 症状

```
Error parsing parameter '--parameters': Invalid JSON
JSON received: {portNumber:[80],localPortNumber:[8080]}
```

### 原因

PowerShell 5.1 はネイティブコマンドに引数を渡す際にダブルクォートを除去してしまう。

### 解決策

バックスラッシュでダブルクォートをエスケープする。

```powershell
# NG
--parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'

# OK
--parameters '{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8080\"]}'
```

---

## 9. RDS db.t3.micro では Performance Insights が使えない

### 症状

```
Error: creating RDS DB Instance: InvalidParameterCombination:
Performance Insights is not supported for your DB instance class.
```

### 原因

`db.t3.micro` は **Performance Insights に非対応**。  
Enhanced Monitoring は db.t3.micro でも動作するが、CloudWatch Logs への追加書き込みコストが発生するため本構成では無効化している。

### 解決策

`rds.tf` で無効化する。

```hcl
resource "aws_db_instance" "zabbix" {
  monitoring_interval          = 0      # Enhanced Monitoring 無効
  performance_insights_enabled = false  # Performance Insights 無効
}
```

Enhanced Monitoring 用の IAM ロールも不要になるため削除する。

---

## 10. ALB アクセスログの S3 書き込みが Access Denied になる

### 症状

```
Access Denied when trying to write ALB access logs to S3
```

### 原因

Terraform が ALB を S3 バケットポリシーより先に作成してしまい、バケットポリシーが適用される前に ALB がログ書き込みを試みる。

### 解決策

ALB リソースに `depends_on` を追加してバケットポリシーの適用を待つ。

```hcl
resource "aws_lb" "monitored" {
  # ...
  depends_on = [aws_s3_bucket_policy.alb_logs]
}
```

---

## 11. Ubuntu の apt は S3 VPC Endpoint 経由では取得できない

### 症状

監視対象 VPC（インターネット接続なし）の Ubuntu インスタンスで nginx がインストールできない。

```
Err:1 http://ap-northeast-1.ec2.archive.ubuntu.com/ubuntu jammy InRelease
  Connection failed
```

### 原因

Ubuntu のパッケージリポジトリは Canonical のサーバー（`archive.ubuntu.com` 等）にあるため、S3 Gateway Endpoint では到達できない。

Amazon Linux 2023 のリポジトリは **S3 上** に置かれているため、S3 Gateway Endpoint のみでインターネットなしにパッケージ取得が可能。

| OS | パッケージリポジトリ | S3 Endpoint で取得可能 |
|----|---------------------|----------------------|
| Amazon Linux 2023 | S3（AWS マネージド） | ✅ 可能 |
| Ubuntu 22.04 | Canonical サーバー | ❌ 不可 |

### 解決策

役割によって OS を使い分ける。

- **Zabbix Server**: Ubuntu 22.04（`repo.zabbix.com` から Zabbix パッケージが必要）
- **監視対象 AP サーバー**: Amazon Linux 2023（nginx のみ必要 → S3 VPC Endpoint で取得可能）

```hcl
# Zabbix Server は Ubuntu 22.04
resource "aws_instance" "zabbix_server" {
  ami = data.aws_ami.ubuntu_22_04.id
}

# 監視対象は AL2023（S3 VPC Endpoint で nginx が取得可能）
resource "aws_instance" "monitored_target" {
  ami = data.aws_ami.amazon_linux_2023.id
}
```

---

## 12. Zabbix Web シナリオで「Could not resolve host」が発生する

### 症状

```
Step "200 OK Check" [1 of 1] failed: Could not resolve host: internal-zabbix-monitored-alb-xxxxxxxxx.ap-northeast-1.elb.amazonaws.com
```

### 原因

VPC Peering 接続のデフォルト設定では、対向 VPC のプライベート DNS を解決できない。
Zabbix Server（Zabbix VPC）が Monitored VPC の内部 ALB の DNS 名を引けないため発生する。

### 解決策

`vpc.tf` の VPC Peering リソースに DNS 解決の許可設定を追加する。

```hcl
resource "aws_vpc_peering_connection" "main" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = aws_vpc.monitored.id
  auto_accept = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}
```

設定変更後に `terraform apply`（in-place update のみ、リソース再作成なし）。

### 補足：ALB の DNS 名は apply ごとに変わる

`terraform destroy → apply` のサイクルで ALB の ID 部分が変わるため、
Zabbix Web シナリオの URL は毎回更新が必要。

```powershell
terraform output monitored_alb_dns_name
```

または AWS コンソール → EC2 → ロードバランサー → `zabbix-monitored-alb` → DNS 名 で確認する。

---

## まとめ

| 問題 | 原因 | 対応 |
|------|------|------|
| Zabbix インストール失敗 | AL2023 と el9 パッケージの非互換 | Ubuntu 22.04 に変更 |
| 外部リポジトリに接続できない | NAT Gateway なし | 一時的に NAT Gateway を追加 |
| dnf タイムアウト | S3 VPC Endpoint なし | S3 Gateway Endpoint を追加 |
| user_data が途中終了 | `set -e` による即時終了 | `-e` を外すか `\|\| true` を付ける |
| bash 変数が Terraform に解釈される | `${}` の衝突 | `$${}` でエスケープ |
| IMDS 取得失敗 | IMDSv2 未対応の curl | Token ヘッダーを付与 |
| サービス起動でブロック | systemd PID 待ち | `--no-block` を使用 |
| JSON パラメータが壊れる | PowerShell のクォート除去 | `\"` でエスケープ |
| RDS インスタンス作成失敗 | db.t3.micro が Performance Insights 非対応 | `performance_insights_enabled = false` |
| ALB ログが Access Denied | S3 バケットポリシー適用のタイミング | `depends_on = [aws_s3_bucket_policy.alb_logs]` |
| Ubuntu で apt が失敗する | Ubuntu リポジトリは S3 外のため VPC Endpoint 非対応 | 監視対象は AL2023 を使用 |
| Web シナリオで Could not resolve host | VPC Peering の DNS 解決が無効 | `allow_remote_vpc_dns_resolution = true` を追加 |
