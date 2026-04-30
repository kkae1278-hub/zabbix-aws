# Zabbix 監視設定手順

Zabbix GUI で AP サーバー（ALB 経由）の HTTP 監視を設定する手順です。

## 事前準備：GUI へのアクセス

SSM ポートフォワーディングでローカル PC から Zabbix GUI に接続します。

```powershell
# Windows PowerShell
$env:AWS_PROFILE = "zabbix-dev"
aws ssm start-session --target <zabbix-server-instance-id> `
  --document-name AWS-StartPortForwardingSession `
  --parameters '{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8080\"]}'
```

ブラウザで `http://localhost:8080/zabbix` を開き、`Admin` / `zabbix` でログイン。

---

## Step 1: ホストの作成

**Configuration → Hosts → Create host**

| 項目 | 値 |
|------|-----|
| Host name | `monitored-alb` |
| Visible name | `Monitored ALB` |
| Host groups | `Linux servers`（既存）または任意のグループ |
| Interfaces | 追加不要（HTTP 監視のため Agent 不要） |

**Add** をクリックして保存。

---

## Step 2: Web シナリオの作成

**Configuration → Hosts → monitored-alb → Web → Create web scenario**

### General タブ

| 項目 | 値 |
|------|-----|
| Name | `ALB HTTP Check` |
| Update interval | `1m` |
| Attempts | `1` |

### Steps タブ

**Add** で以下の 3 ステップを追加：

**Step 1 - 200 OK 確認**

| 項目 | 値 |
|------|-----|
| Name | `200 OK Check` |
| URL | `http://internal-zabbix-monitored-alb-134365578.ap-northeast-1.elb.amazonaws.com/` |
| Required status codes | `200` |

**Step 2 - 4xx 確認**

| 項目 | 値 |
|------|-----|
| Name | `404 Check` |
| URL | `http://internal-zabbix-monitored-alb-134365578.ap-northeast-1.elb.amazonaws.com/notfound` |
| Required status codes | `404` |

**Step 3 - 5xx 確認**

| 項目 | 値 |
|------|-----|
| Name | `503 Check` |
| URL | `http://internal-zabbix-monitored-alb-134365578.ap-northeast-1.elb.amazonaws.com/error` |
| Required status codes | `503` |

**Add** をクリックして保存。

---

## Step 3: トリガーの作成

**Configuration → Hosts → monitored-alb → Triggers → Create trigger**

| 項目 | 値 |
|------|-----|
| Name | `ALB Web scenario failed` |
| Severity | `High` |
| Expression | `last(/monitored-alb/web.test.fail[ALB HTTP Check])<>0` |

> **Zabbix 7.0 の式の書き方:** `func(/host/key)<>value` 形式を使用する。  
> 旧バージョンの `{host:key.func()}<>value` 形式はエラーになる。

**Add** をクリックして保存。

---

## Step 4: 監視結果の確認

**Monitoring → Web**

`ALB HTTP Check` が表示され、ステータスが `OK` になれば設定完了です。

| 表示項目 | 説明 |
|----------|------|
| Status | `OK` / `Failed` |
| Last check | 最終チェック時刻 |
| Number of steps | 実行ステップ数（3） |

---

## 参考: ALB DNS 名の確認

```powershell
cd terraform
terraform output monitored_alb_dns_name
```

---

## Step 5: Admin パスワード変更

初回ログイン後に必ずデフォルトパスワード（`zabbix`）を変更する。

### GUI で変更

**User settings（右上アイコン）→ Profile → Password → Change password**

### API スクリプトで変更（SSM セッション内）

```bash
# Zabbix Server に SSM 接続
aws ssm start-session --target <zabbix-server-instance-id>

# スクリプト実行
sudo bash /tmp/change_zabbix_password.sh 'NewPassword123!'
```

スクリプトは `terraform/scripts/change_zabbix_password.sh` を Zabbix Server にコピーして使用する。

---

## Step 6: アラートアクション設定（Zabbix → SNS 通知）

Zabbix のトリガー発火時に SNS トピックへ通知するよう設定する。

### 6-1. アラートスクリプトの配置（Zabbix Server 上）

```bash
# SSM で Zabbix Server に接続
aws ssm start-session --target <zabbix-server-instance-id>

# スクリプト配置
sudo mkdir -p /usr/lib/zabbix/alertscripts
sudo tee /usr/lib/zabbix/alertscripts/sns_notify.sh > /dev/null << 'EOF'
#!/bin/bash
TOPIC_ARN="$1"
SUBJECT="$2"
MESSAGE="$3"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-1}"
aws sns publish --topic-arn "$TOPIC_ARN" --subject "$SUBJECT" --message "$MESSAGE" --region "$REGION"
EOF

sudo chmod +x /usr/lib/zabbix/alertscripts/sns_notify.sh
```

### 6-2. SNS Topic ARN の確認

```bash
# ローカル PC で実行
cd terraform
terraform output  # SNS ARN は AWS コンソールか以下で確認
aws sns list-topics --region ap-northeast-1
```

### 6-3. メディアタイプの作成

**Administration → Media types → Create media type**

| 項目 | 値 |
|------|-----|
| Name | `AWS SNS` |
| Type | `Script` |
| Script name | `sns_notify.sh` |
| Script parameters | `{ALERT.SENDTO}` / `{ALERT.SUBJECT}` / `{ALERT.MESSAGE}` |

**Add** で3つのパラメータを順番に追加して保存。

### 6-4. Admin ユーザーにメディアを追加

**Administration → Users → Admin → Media タブ → Add**

| 項目 | 値 |
|------|-----|
| Type | `AWS SNS` |
| Send to | `arn:aws:sns:ap-northeast-1:<account-id>:zabbix-alerts` |
| When active | `1-7,00:00-24:00` |
| Use if severity | `High` 以上にチェック |

### 6-5. アクションの作成

**Configuration → Actions → Trigger actions → Create action**

| 項目 | 値 |
|------|-----|
| Name | `Notify via SNS` |
| Conditions | Trigger severity >= High |

**Operations タブ → Add**

| 項目 | 値 |
|------|-----|
| Send to users | `Admin` |
| Send only to | `AWS SNS` |

**Add** → **Update** で保存。

> **注意:** Zabbix Server から SNS へのアウトバウンド通信が必要。  
> NAT Gateway または SNS VPC Endpoint を追加すること（コスト増あり）。  
> CloudWatch アラームの SNS 連携は Terraform で設定済み（インフラ異常の通知はそちらで対応可能）。

---

## Step 7: Zabbix Agent による AP サーバー OS 監視

AP サーバー（AL2023）には `zabbix-agent2` がインストール済み。  
Zabbix GUI にホストを追加するだけで OS 監視が開始できる。

### AP サーバーのプライベート IP を確認

```bash
cd terraform
terraform output monitored_target_instance_ids
# 出力された Instance ID で IP を確認
aws ec2 describe-instances \
  --instance-ids <id1> <id2> \
  --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]' \
  --output table \
  --region ap-northeast-1
```

### ホストの追加

**Configuration → Hosts → Create host**（AP サーバー × 2 台分繰り返す）

| 項目 | 値 |
|------|-----|
| Host name | `<Instance ID>`（agent_user_data.sh で Hostname に設定済み） |
| Visible name | `AP Server 1`（任意） |
| Host groups | `Linux servers` |
| Interfaces → Agent | IP: `<AP サーバーのプライベート IP>` / Port: `10050` |

### テンプレートのリンク

**Templates タブ → Link new templates**

`Linux by Zabbix agent` を選択して **Add** → **Update**。

これで CPU・メモリ・ディスク・ネットワークなどの OS メトリクスが自動収集される。

---

## Step 8: ホスト自動登録（Auto-registration）

AP サーバーが増えた際に Zabbix ホストを自動登録する設定。  
`zabbix-agent2` は起動時から `ServerActive` で Zabbix Server への接続を試みている。

### 自動登録アクションの作成

**Configuration → Actions → Autoregistration actions → Create action**

| 項目 | 値 |
|------|-----|
| Name | `Auto-register Linux servers` |

**Conditions タブ**（条件なしでも可。絞りたい場合は Host metadata 等を使用）

**Operations タブ → Add**

| Operation | 設定 |
|-----------|------|
| Add host | （チェック） |
| Add to host groups | `Linux servers` |
| Link to templates | `Linux by Zabbix agent` |

**Add** → **Update** で保存。

保存後、未登録のエージェントが接続してくると自動的にホストが作成される。  
登録状況は **Monitoring → Latest data** で確認できる。

---

## トラブルシューティング

### 502 Bad Gateway が返る

ALB バックエンドの AP サーバーが応答していない。

```bash
# AP サーバーに SSM 接続して nginx を確認
aws ssm start-session --target <ap-server-instance-id>
sudo systemctl status nginx
sudo systemctl start nginx
```

### トリガー式でエラーになる

Zabbix 7.0 では式の形式が変わっています。

```
# 正しい形式（7.0）
last(/monitored-alb/web.test.fail[ALB HTTP Check])<>0

# 誤った形式（6.x 以前）
{monitored-alb:web.test.fail[ALB HTTP Check].last()}<>0
```
