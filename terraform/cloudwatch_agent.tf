# ============================================================
# CloudWatch Agent 設定（SSM Parameter Store）
# ============================================================
resource "aws_ssm_parameter" "cw_agent_config" {
  name = "/${var.project_name}/cloudwatch-agent/config"
  type = "String"

  value = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path         = "/var/log/zabbix/zabbix_server.log"
              log_group_name    = "/zabbix/server"
              log_stream_name   = "{instance_id}/zabbix_server"
              retention_in_days = 30
            },
            {
              file_path         = "/var/log/zabbix-setup.log"
              log_group_name    = "/zabbix/server"
              log_stream_name   = "{instance_id}/setup"
              retention_in_days = 7
            }
          ]
        }
      }
    }
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      metrics_collected = {
        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        disk = {
          measurement                 = ["disk_used_percent"]
          resources                   = ["/"]
          metrics_collection_interval = 60
          ignore_file_system_types    = ["sysfs", "devtmpfs", "tmpfs"]
        }
        cpu = {
          measurement                 = ["cpu_usage_user", "cpu_usage_system", "cpu_usage_idle"]
          metrics_collection_interval = 60
          totalcpu                    = true
        }
      }
    }
  })

  tags = {
    Name = "${var.project_name}-cw-agent-config"
  }
}

# ============================================================
# SSM Association: CloudWatch Agent インストール（全 EC2）
# ============================================================
resource "aws_ssm_association" "install_cw_agent" {
  name             = "AWS-ConfigureAWSPackage"
  association_name = "${var.project_name}-install-cw-agent"

  targets {
    key    = "tag:Project"
    values = [var.project_name]
  }

  parameters = {
    action  = "Install"
    name    = "AmazonCloudWatchAgent"
    version = "latest"
  }

  apply_only_at_cron_interval = false # 新規インスタンスが対象タグを持つと即時実行
}

# ============================================================
# SSM Association: CloudWatch Agent 設定・起動（全 EC2）
# ============================================================
resource "aws_ssm_association" "configure_cw_agent" {
  name             = "AmazonCloudWatch-ManageAgent"
  association_name = "${var.project_name}-configure-cw-agent"
  depends_on       = [aws_ssm_association.install_cw_agent]

  targets {
    key    = "tag:Project"
    values = [var.project_name]
  }

  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cw_agent_config.name
    optionalRestart               = "yes"
  }

  apply_only_at_cron_interval = false # 設定変更時に対象インスタンスへ即時適用
}
