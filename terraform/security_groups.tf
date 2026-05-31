# ============================================================
# Zabbix Server Security Group
# ============================================================
resource "aws_security_group" "zabbix_server" {
  name        = "${var.project_name}-server-sg"
  description = "Security group for Zabbix Server EC2"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-server-sg"
  }
}

# Zabbix Agent からの接続（Zabbix VPC → Server）
resource "aws_vpc_security_group_ingress_rule" "zabbix_server_trapper_from_zabbix_vpc" {
  security_group_id = aws_security_group.zabbix_server.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 10051
  to_port           = 10051
  ip_protocol       = "tcp"
  description       = "Zabbix trapper from Zabbix VPC"
}

# Zabbix Agent からの接続（監視対象 VPC → Server）
resource "aws_vpc_security_group_ingress_rule" "zabbix_server_trapper_from_monitored_vpc" {
  security_group_id = aws_security_group.zabbix_server.id
  cidr_ipv4         = var.monitored_vpc_cidr
  from_port         = 10051
  to_port           = 10051
  ip_protocol       = "tcp"
  description       = "Zabbix trapper from Monitored VPC"
}

# 学習用：全送信を許可。本番では SSM・RDS・NAT GW 等、必要な送信先のみに絞ることを推奨
resource "aws_vpc_security_group_egress_rule" "zabbix_server_all" {
  security_group_id = aws_security_group.zabbix_server.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# ============================================================
# RDS Security Group
# ============================================================
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for Zabbix RDS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_zabbix_server" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.zabbix_server.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  description                  = "MySQL from Zabbix Server"
}

# ============================================================
# Monitored VPC ALB Security Group
# ============================================================
resource "aws_security_group" "monitored_alb" {
  name        = "${var.project_name}-monitored-alb-sg"
  description = "Security group for Monitored VPC ALB"
  vpc_id      = aws_vpc.monitored.id

  tags = {
    Name = "${var.project_name}-monitored-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "monitored_alb_http_from_monitored_vpc" {
  security_group_id = aws_security_group.monitored_alb.id
  cidr_ipv4         = var.monitored_vpc_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from Monitored VPC"
}

resource "aws_vpc_security_group_ingress_rule" "monitored_alb_http_from_zabbix_vpc" {
  security_group_id = aws_security_group.monitored_alb.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from Zabbix VPC (web scenarios)"
}

# 学習用：全送信を許可。本番では必要な送信先のみに絞ることを推奨
resource "aws_vpc_security_group_egress_rule" "monitored_alb_all" {
  security_group_id = aws_security_group.monitored_alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# ============================================================
# Zabbix Agent Security Group（監視対象 VPC 用）
# ============================================================
resource "aws_security_group" "zabbix_agent" {
  name        = "${var.project_name}-agent-sg"
  description = "Security group for Zabbix Agent targets"
  vpc_id      = aws_vpc.monitored.id

  tags = {
    Name = "${var.project_name}-agent-sg"
  }
}

# Zabbix Server からのポーリング（passive check / cross-VPC のため CIDR 指定）
resource "aws_vpc_security_group_ingress_rule" "zabbix_agent_passive_check" {
  security_group_id = aws_security_group.zabbix_agent.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 10050
  to_port           = 10050
  ip_protocol       = "tcp"
  description       = "Zabbix passive check from server"
}

# Monitored ALB からの HTTP
resource "aws_vpc_security_group_ingress_rule" "zabbix_agent_http_from_alb" {
  security_group_id            = aws_security_group.zabbix_agent.id
  referenced_security_group_id = aws_security_group.monitored_alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "HTTP from Monitored ALB"
}

# 学習用：全送信を許可。本番では SSM・NAT GW 経由の通信等、必要な送信先のみに絞ることを推奨
resource "aws_vpc_security_group_egress_rule" "zabbix_agent_all" {
  security_group_id = aws_security_group.zabbix_agent.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# ============================================================
# VPC Endpoint Security Group（監視対象 VPC 用）
# ============================================================
resource "aws_security_group" "monitored_vpc_endpoint" {
  name        = "${var.project_name}-monitored-vpce-sg"
  description = "Security group for VPC Endpoints in Monitored VPC"
  vpc_id      = aws_vpc.monitored.id

  tags = {
    Name = "${var.project_name}-monitored-vpce-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "monitored_vpce_https" {
  security_group_id = aws_security_group.monitored_vpc_endpoint.id
  cidr_ipv4         = var.monitored_vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from Monitored VPC"
}

# ============================================================
# VPC Endpoint Security Group（Zabbix VPC 用）
# ============================================================
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.project_name}-vpce-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-vpce-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https" {
  security_group_id = aws_security_group.vpc_endpoint.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from Zabbix VPC"
}
