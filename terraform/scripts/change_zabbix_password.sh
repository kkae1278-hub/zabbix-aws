#!/bin/bash
# Zabbix Admin パスワードを Zabbix API 経由で変更するスクリプト
# Zabbix Server 上で実行すること（SSM セッション内）
#
# 使い方: sudo bash change_zabbix_password.sh <新しいパスワード>

set -euo pipefail

NEW_PASSWORD="${1:?使い方: $0 <新しいパスワード>}"
ZABBIX_URL="http://localhost/zabbix/api_jsonrpc.php"

echo "=== Zabbix Admin パスワード変更 ==="

# 1. 現在のデフォルトパスワードでログイン
echo "[1/3] ログイン中..."
TOKEN=$(curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {
      "username": "Admin",
      "password": "zabbix"
    },
    "id": 1
  }' | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'error' in data:
    print('ERROR: ' + data['error']['data'], file=sys.stderr)
    sys.exit(1)
print(data['result'])
")

echo "[2/3] パスワード変更中..."
RESULT=$(curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"user.update\",
    \"params\": {
      \"userid\": \"1\",
      \"passwd\": \"$NEW_PASSWORD\"
    },
    \"id\": 2
  }" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'error' in data:
    print('ERROR: ' + data['error']['data'], file=sys.stderr)
    sys.exit(1)
print('OK: userid=' + str(data['result']['userids'][0]))
")

echo "[3/3] $RESULT"
echo "=== パスワード変更完了 ==="
echo "新しいパスワードで http://localhost:8080/zabbix にログインしてください"
