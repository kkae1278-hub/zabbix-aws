# ============================================================
# CloudWatch Log Group（Zabbix ログ）
# ============================================================
resource "aws_cloudwatch_log_group" "zabbix" {
  name              = "/zabbix/server"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-log-group"
  }
}

# ============================================================
# Zabbix Server EC2
# ============================================================
resource "aws_instance" "zabbix_server" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = var.zabbix_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.zabbix_server.id]
  iam_instance_profile   = aws_iam_instance_profile.zabbix_server.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    project_name   = var.project_name
    zabbix_version = var.zabbix_version
    secret_arn     = aws_db_instance.zabbix.master_user_secret[0].secret_arn
    aws_region     = var.aws_region
    db_name        = var.rds_db_name
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 強制
    http_put_response_hop_limit = 1
  }

  monitoring = true

  tags = {
    Name = "${var.project_name}-server"
    Role = "zabbix-server"
  }

  depends_on = [aws_db_instance.zabbix]
}

# ============================================================
# 監視対象 EC2（Zabbix Agent）
# ============================================================
resource "aws_instance" "monitored_target" {
  count                  = 2
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.monitored_private[count.index].id
  vpc_security_group_ids = [aws_security_group.zabbix_agent.id]
  iam_instance_profile   = aws_iam_instance_profile.zabbix_agent.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/agent_user_data.sh", {
    project_name   = var.project_name
    zabbix_version = var.zabbix_version
    server_ip      = aws_instance.zabbix_server.private_ip
    aws_region     = var.aws_region
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # user_data 変更時にインスタンスを再作成する
  lifecycle {
    replace_triggered_by = [terraform_data.agent_user_data]
  }

  tags = {
    Name = "${var.project_name}-monitored-target-${count.index + 1}"
    Role = "zabbix-agent"
  }
}

# ============================================================
# user_data 変更検知トリガー（agent_user_data.sh の内容ハッシュ）
# ============================================================
resource "terraform_data" "agent_user_data" {
  input = templatefile("${path.module}/agent_user_data.sh", {
    project_name   = var.project_name
    zabbix_version = var.zabbix_version
    server_ip      = aws_instance.zabbix_server.private_ip
    aws_region     = var.aws_region
  })
}
