# ============================================================
# SNS トピック（アラート通知）
# ============================================================
resource "aws_sns_topic" "zabbix_alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name = "${var.project_name}-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.sns_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.zabbix_alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# ============================================================
# CloudWatch Alarms（EC2 Zabbix Server）
# ============================================================
resource "aws_cloudwatch_metric_alarm" "zabbix_cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Zabbix Server CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.zabbix_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.zabbix_server.id
  }

  tags = {
    Name = "${var.project_name}-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "zabbix_status_check" {
  alarm_name          = "${var.project_name}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Zabbix Server status check failed"
  alarm_actions       = [aws_sns_topic.zabbix_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.zabbix_server.id
  }

  tags = {
    Name = "${var.project_name}-status-alarm"
  }
}

# ============================================================
# CloudWatch Alarms（RDS）
# ============================================================
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.project_name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.zabbix_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.zabbix.identifier
  }

  tags = {
    Name = "${var.project_name}-rds-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.project_name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5GB
  alarm_description   = "RDS free storage is low"
  alarm_actions       = [aws_sns_topic.zabbix_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.zabbix.identifier
  }

  tags = {
    Name = "${var.project_name}-rds-storage-alarm"
  }
}

# ============================================================
# CloudWatch Alarms（ALB）
# ============================================================
resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  alarm_name          = "${var.project_name}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_description   = "ALB 5XX errors too high"
  alarm_actions       = [aws_sns_topic.zabbix_alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.monitored.arn_suffix
  }

  tags = {
    Name = "${var.project_name}-alb-5xx-alarm"
  }
}

# ============================================================
# CloudWatch Dashboard
# ============================================================
resource "aws_cloudwatch_dashboard" "zabbix" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ── Row 1: EC2 CPU / RDS CPU ──────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Zabbix Server CPU 使用率 (%)"
          region  = var.aws_region
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.zabbix_server.id]]
          period  = 300
          stat    = "Average"
          view    = "timeSeries"
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "RDS CPU 使用率 (%)"
          region  = var.aws_region
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.zabbix.identifier]]
          period  = 300
          stat    = "Average"
          view    = "timeSeries"
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      # ── Row 2: EC2 Network / EC2 Status Check ─────────────
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Zabbix Server ネットワーク (bytes)"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.zabbix_server.id, { label = "NetworkIn" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.zabbix_server.id, { label = "NetworkOut" }]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Zabbix Server ステータスチェック"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.zabbix_server.id, { label = "StatusCheckFailed" }],
            ["AWS/EC2", "StatusCheckFailed_Instance", "InstanceId", aws_instance.zabbix_server.id, { label = "Instance" }],
            ["AWS/EC2", "StatusCheckFailed_System", "InstanceId", aws_instance.zabbix_server.id, { label = "System" }]
          ]
          period = 60
          stat   = "Maximum"
          view   = "timeSeries"
          yAxis  = { left = { min = 0, max = 1 } }
        }
      },
      # ── Row 3: RDS Storage / RDS Connections ──────────────
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "RDS 空きストレージ (bytes)"
          region  = var.aws_region
          metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.zabbix.identifier]]
          period  = 300
          stat    = "Average"
          view    = "timeSeries"
          annotations = {
            horizontal = [{ label = "5GB 警告ライン", value = 5368709120, color = "#ff6961" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "RDS DB 接続数 / 空きメモリ"
          region = var.aws_region
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.zabbix.identifier, { label = "Connections", yAxis = "left" }],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", aws_db_instance.zabbix.identifier, { label = "FreeableMemory(bytes)", yAxis = "right" }]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      # ── Row 4: メモリ使用率 / ディスク使用率 ─────────────
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "メモリ使用率 (%) ※CloudWatch Agent"
          region = var.aws_region
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.zabbix_server.id, { label = "Zabbix Server" }],
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.monitored_target[0].id, { label = "AP Server 1" }],
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.monitored_target[1].id, { label = "AP Server 2" }]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          yAxis  = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "ディスク使用率 (%) ※CloudWatch Agent"
          region = var.aws_region
          metrics = [
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.zabbix_server.id, "path", "/", { label = "Zabbix Server" }],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.monitored_target[0].id, "path", "/", { label = "AP Server 1" }],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.monitored_target[1].id, "path", "/", { label = "AP Server 2" }]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          yAxis  = { left = { min = 0, max = 100 } }
        }
      },
      # ── Row 5: ALB リクエスト数 / レスポンスタイム ────────
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 12
        height = 6
        properties = {
          title  = "ALB リクエスト数"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.monitored.arn_suffix, { label = "RequestCount", stat = "Sum" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", aws_lb.monitored.arn_suffix, { label = "2xx", stat = "Sum" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.monitored.arn_suffix, { label = "4xx", stat = "Sum" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.monitored.arn_suffix, { label = "5xx", stat = "Sum" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 24
        width  = 12
        height = 6
        properties = {
          title  = "ALB レスポンスタイム (秒)"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.monitored.arn_suffix, { label = "ResponseTime(avg)", stat = "Average" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.monitored.arn_suffix, { label = "ResponseTime(p99)", stat = "p99" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      }
    ]
  })
}
