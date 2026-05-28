# ============================================================
# Terraform State 管理用 Bootstrap
# main モジュールを apply する前に先にここを apply する
# ============================================================
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================
# AWS Provider
# ============================================================
provider "aws" {
  region = var.aws_region
}

# ============================================================
# 変数・データソース
# ============================================================
variable "aws_region" {
  default = "ap-northeast-1"
}

variable "project_name" {
  default = "zabbix"
}

data "aws_caller_identity" "current" {}

# ============================================================
# S3 Bucket（Terraform State 保存用）
# ============================================================
resource "aws_s3_bucket" "tfstate" {
  bucket        = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name      = "${var.project_name}-tfstate"
    ManagedBy = "bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================
# DynamoDB（State ロック用）
# ============================================================
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.project_name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST" # ステートロック用途はアクセス頻度が低いため従量課金が適切
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "${var.project_name}-tfstate-lock"
    ManagedBy = "bootstrap"
  }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.tfstate.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tfstate_lock.name
}

output "backend_config" {
  description = "terraform/main.tf の backend ブロックに貼り付ける設定"
  value       = <<-EOT
    backend "s3" {
      bucket         = "${aws_s3_bucket.tfstate.id}"
      key            = "zabbix/terraform.tfstate"
      region         = "${var.aws_region}"
      encrypt        = true
      dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"
    }
  EOT
}
