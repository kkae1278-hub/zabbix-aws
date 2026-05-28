# ============================================================
# Monitored VPC - AP Server ALB
# ============================================================
resource "aws_lb" "monitored" {
  name               = "${var.project_name}-monitored-alb"
  internal           = true # 監視対象 VPC 内のみアクセス可能（インターネット非公開）
  load_balancer_type = "application"
  security_groups    = [aws_security_group.monitored_alb.id]
  subnets            = aws_subnet.monitored_private[*].id

  enable_deletion_protection = false # 学習用：本番では true に設定

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "monitored-alb"
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-monitored-alb"
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "monitored" {
  name     = "${var.project_name}-monitored-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.monitored.id

  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-monitored-tg"
  }
}

resource "aws_lb_target_group_attachment" "monitored" {
  count            = 2
  target_group_arn = aws_lb_target_group.monitored.arn
  target_id        = aws_instance.monitored_target[count.index].id
  port             = 80
}

# 学習用：本番では HTTPS（443）リスナーを使用し、HTTP → HTTPS リダイレクトを設定する
resource "aws_lb_listener" "monitored_http" {
  load_balancer_arn = aws_lb.monitored.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.monitored.arn
  }
}

data "aws_elb_service_account" "main" {}
data "aws_caller_identity" "current" {}

# ============================================================
# ALB アクセスログ用 S3 バケット
# ============================================================
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project_name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # 学習用：本番では false に設定（誤削除防止）

  tags = {
    Name = "${var.project_name}-alb-logs"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/monitored-alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
