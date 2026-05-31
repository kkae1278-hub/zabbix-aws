# ============================================================
# RDS Subnet Group
# ============================================================
resource "aws_db_subnet_group" "zabbix" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ============================================================
# RDS Parameter Group（Zabbix 向け最適化）
# ============================================================
resource "aws_db_parameter_group" "zabbix" {
  name   = "${var.project_name}-mysql8-params"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_bin"
  }

  parameter {
    name  = "log_bin_trust_function_creators"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-mysql8-params"
  }
}

# ============================================================
# RDS Instance（MySQL 8.0）
# ============================================================
resource "aws_db_instance" "zabbix" {
  identifier = "${var.project_name}-db"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.rds_instance_class

  db_name  = var.rds_db_name
  username = var.rds_username

  # RDS がパスワードを生成して Secrets Manager で自動管理・ローテーションする
  # tfstate にパスワードが平文で残らないため random_password より安全
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.zabbix.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.zabbix.name

  # ストレージ
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  # 可用性
  multi_az = false # 学習用：true にすると本番同等

  # バックアップ
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # 削除保護（学習用は false）
  deletion_protection = false
  skip_final_snapshot = true

  # モニタリング
  monitoring_interval          = 0
  performance_insights_enabled = false

  tags = {
    Name = "${var.project_name}-db"
  }
}

