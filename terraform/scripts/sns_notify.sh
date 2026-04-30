#!/bin/bash
# Zabbix → SNS 通知スクリプト
# /usr/lib/zabbix/alertscripts/sns_notify.sh に配置すること
#
# Zabbix メディアタイプのパラメータ設定:
#   パラメータ1: {ALERT.SENDTO}  → SNS Topic ARN
#   パラメータ2: {ALERT.SUBJECT} → 件名
#   パラメータ3: {ALERT.MESSAGE} → 本文

TOPIC_ARN="$1"
SUBJECT="$2"
MESSAGE="$3"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-1}"

if [[ -z "$TOPIC_ARN" ]]; then
  echo "ERROR: SNS Topic ARN が未設定です" >&2
  exit 1
fi

aws sns publish \
  --topic-arn "$TOPIC_ARN" \
  --subject "$SUBJECT" \
  --message "$MESSAGE" \
  --region "$REGION"
