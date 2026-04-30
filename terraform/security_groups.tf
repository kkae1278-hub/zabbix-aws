# ============================================================
# Zabbix Server Security Group
# ============================================================
resource "aws_security_group" "zabbix_server" {
  name        = "${var.project_name}-server-sg"
  description = "Security group for Zabbix Server EC2"
  vpc_id      = aws_vpc.main.id

  # Zabbix Agent からの接続（監視対象 VPC → Server）
  ingress {
    description = "Zabbix trapper from agents"
    from_port   = 10051
    to_port     = 10051
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.monitored_vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-server-sg"
  }
}

# ============================================================
# RDS Security Group
# ============================================================
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for Zabbix RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from Zabbix Server"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.zabbix_server.id]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# ============================================================
# Monitored VPC ALB Security Group
# ============================================================
resource "aws_security_group" "monitored_alb" {
  name        = "${var.project_name}-monitored-alb-sg"
  description = "Security group for Monitored VPC ALB"
  vpc_id      = aws_vpc.monitored.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-monitored-alb-sg"
  }
}

# ============================================================
# Zabbix Agent Security Group（監視対象 VPC 用）
# ============================================================
resource "aws_security_group" "zabbix_agent" {
  name        = "${var.project_name}-agent-sg"
  description = "Security group for Zabbix Agent targets"
  vpc_id      = aws_vpc.monitored.id

  # Zabbix Server からのポーリング（passive check / cross-VPC のため CIDR 指定）
  ingress {
    description = "Zabbix passive check from server"
    from_port   = 10050
    to_port     = 10050
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Monitored ALB からの HTTP
  ingress {
    description     = "HTTP from Monitored ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.monitored_alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-agent-sg"
  }
}

# ============================================================
# VPC Endpoint Security Group（監視対象 VPC 用）
# ============================================================
resource "aws_security_group" "monitored_vpc_endpoint" {
  name        = "${var.project_name}-monitored-vpce-sg"
  description = "Security group for VPC Endpoints in Monitored VPC"
  vpc_id      = aws_vpc.monitored.id

  ingress {
    description = "HTTPS from Monitored VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.monitored_vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-monitored-vpce-sg"
  }
}

# ============================================================
# VPC Endpoint Security Group
# ============================================================
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.project_name}-vpce-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-vpce-sg"
  }
}
