# ============================================================
# Zabbix Server 用 IAM Role（SSM + Secrets Manager + CloudWatch）
# ============================================================
resource "aws_iam_role" "zabbix_server" {
  name = "${var.project_name}-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# SSM Session Manager
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.zabbix_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.zabbix_server.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Secrets Manager 読み取り（DB パスワード取得用）
resource "aws_iam_role_policy" "secrets_manager_read" {
  name = "${var.project_name}-secrets-read"
  role = aws_iam_role.zabbix_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.rds_password.arn
      }
    ]
  })
}

# SNS 通知（Zabbix アラートアクション用）
resource "aws_iam_role_policy" "sns_publish" {
  name = "${var.project_name}-sns-publish"
  role = aws_iam_role.zabbix_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.zabbix_alerts.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "zabbix_server" {
  name = "${var.project_name}-server-profile"
  role = aws_iam_role.zabbix_server.name
}

# ============================================================
# Zabbix Agent 用 IAM Role（監視対象 EC2 用）
# ============================================================
resource "aws_iam_role" "zabbix_agent" {
  name = "${var.project_name}-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "agent_ssm_core" {
  role       = aws_iam_role.zabbix_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "agent_cloudwatch" {
  role       = aws_iam_role.zabbix_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "zabbix_agent" {
  name = "${var.project_name}-agent-profile"
  role = aws_iam_role.zabbix_agent.name
}
