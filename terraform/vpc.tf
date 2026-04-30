# ============================================================
# Zabbix VPC
# ============================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ============================================================
# Private Subnets（ALB / Zabbix Server / RDS 用 / 2AZ）
# ============================================================
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = ["10.0.10.0/24", "10.0.11.0/24"][count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "private"
  }
}

# ============================================================
# Public Subnets（NAT Gateway 用 / 2AZ）
# ============================================================
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = ["10.0.1.0/24", "10.0.2.0/24"][count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  }
}

# ============================================================
# Internet Gateway
# ============================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}


# ============================================================
# Route Table（Public）
# ============================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# Route Table（Private）
# ============================================================
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


# ============================================================
# VPC Endpoints（SSM / SSM Messages / EC2 Messages / Secrets Manager / Logs）
# ============================================================
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ec2messages-endpoint"
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-secretsmanager-endpoint"
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-logs-endpoint"
  }
}

# S3 Gateway Endpoint（ALB アクセスログの S3 書き込みに必要）
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

# ============================================================
# Monitored VPC（監視対象用）
# ============================================================
resource "aws_vpc" "monitored" {
  cidr_block           = var.monitored_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-monitored-vpc"
  }
}

# Private Subnets（監視対象 EC2 用 / 2AZ）
resource "aws_subnet" "monitored_private" {
  count             = 2
  vpc_id            = aws_vpc.monitored.id
  cidr_block        = ["10.1.10.0/24", "10.1.11.0/24"][count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-monitored-private-${count.index + 1}"
    Tier = "private"
  }
}

# Route Table（Monitored Private）
resource "aws_route_table" "monitored_private" {
  vpc_id = aws_vpc.monitored.id

  route {
    cidr_block                = var.vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.main.id
  }

  tags = {
    Name = "${var.project_name}-monitored-private-rt"
  }
}

resource "aws_route_table_association" "monitored_private" {
  count          = 2
  subnet_id      = aws_subnet.monitored_private[count.index].id
  route_table_id = aws_route_table.monitored_private.id
}

# VPC Endpoints（監視対象 VPC 用 SSM）
resource "aws_vpc_endpoint" "monitored_ssm" {
  vpc_id              = aws_vpc.monitored.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.monitored_private[*].id
  security_group_ids  = [aws_security_group.monitored_vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-monitored-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "monitored_ssmmessages" {
  vpc_id              = aws_vpc.monitored.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.monitored_private[*].id
  security_group_ids  = [aws_security_group.monitored_vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-monitored-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "monitored_ec2messages" {
  vpc_id              = aws_vpc.monitored.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.monitored_private[*].id
  security_group_ids  = [aws_security_group.monitored_vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-monitored-ec2messages-endpoint"
  }
}

# S3 Gateway Endpoint（AL2023 パッケージリポジトリ用）
resource "aws_vpc_endpoint" "monitored_s3" {
  vpc_id            = aws_vpc.monitored.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.monitored_private.id]

  tags = {
    Name = "${var.project_name}-monitored-s3-endpoint"
  }
}

# ============================================================
# VPC Peering（Zabbix VPC ↔ Monitored VPC）
# ============================================================
resource "aws_vpc_peering_connection" "main" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = aws_vpc.monitored.id
  auto_accept = true

  tags = {
    Name = "${var.project_name}-vpc-peering"
  }
}

# Zabbix VPC private RT → Monitored VPC へのルート
resource "aws_route" "zabbix_to_monitored" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = var.monitored_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
}
