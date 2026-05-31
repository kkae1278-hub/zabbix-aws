output "monitored_alb_dns_name" {
  description = "監視対象 AP サーバー ALB の DNS 名"
  value       = "http://${aws_lb.monitored.dns_name}"
}

output "zabbix_server_instance_id" {
  description = "Zabbix Server の Instance ID（SSM 接続に使用）"
  value       = aws_instance.zabbix_server.id
}

output "zabbix_server_private_ip" {
  description = "Zabbix Server のプライベート IP"
  value       = aws_instance.zabbix_server.private_ip
}

output "monitored_target_instance_ids" {
  description = "監視対象 EC2 の Instance ID 一覧"
  value       = aws_instance.monitored_target[*].id
}

output "rds_endpoint" {
  description = "RDS エンドポイント"
  value       = aws_db_instance.zabbix.address
}

output "secrets_manager_arn" {
  description = "RDS が自動管理する Secrets Manager ARN（DB パスワード）"
  value       = aws_db_instance.zabbix.master_user_secret[0].secret_arn
}

output "ssm_connect_command" {
  description = "SSM Session Manager での Zabbix Server 接続コマンド"
  value       = "aws ssm start-session --target ${aws_instance.zabbix_server.id} --region ${var.aws_region}"
}

output "ssm_portforward_command" {
  description = "SSM ポートフォワード経由で Zabbix GUI にアクセスするコマンド（実行後 http://localhost:8080/）"
  value       = "aws ssm start-session --target ${aws_instance.zabbix_server.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8080\"]}' --region ${var.aws_region}"
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch ダッシュボード URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.zabbix.dashboard_name}"
}

output "sns_topic_arn" {
  description = "アラート通知用 SNS Topic ARN"
  value       = aws_sns_topic.zabbix_alerts.arn
}
