# ============================================================
# RDS パスワードを Secrets Manager で管理
# ============================================================
resource "random_password" "rds" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds_password" {
  name                    = "${var.project_name}/rds/password"
  description             = "Zabbix RDS master password"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-rds-secret"
  }
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    username = var.rds_username
    password = random_password.rds.result
    host     = aws_db_instance.zabbix.address
    port     = 3306
    dbname   = var.rds_db_name
  })
}

