variable "project_name" {
  description = "プロジェクト名（リソース名のプレフィックスに使用）"
  type        = string
  default     = "zabbix"
}

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "vpc_cidr" {
  description = "VPC の CIDR ブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "zabbix_instance_type" {
  description = "Zabbix Server の EC2 インスタンスタイプ"
  type        = string
  default     = "t3.micro"
}

variable "rds_instance_class" {
  description = "RDS インスタンスクラス"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_db_name" {
  description = "Zabbix 用 DB 名"
  type        = string
  default     = "zabbix"
}

variable "rds_username" {
  description = "RDS マスターユーザー名"
  type        = string
  default     = "zabbix"
}

variable "zabbix_version" {
  description = "Zabbix バージョン"
  type        = string
  default     = "7.0"
}

variable "monitored_vpc_cidr" {
  description = "監視対象 VPC の CIDR ブロック"
  type        = string
  default     = "10.1.0.0/16"
}

variable "sns_email" {
  description = "アラート通知先メールアドレス"
  type        = string
  default     = ""
}
