# -----------------------------------------------------------------------------
# Phase 8: Monitoring & Logging
# - AWS GuardDuty with EKS protection
# - CloudWatch alarms on EKS control plane, node CPU/memory, and failed auth
# - SNS topic for alarm notifications
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# GuardDuty detector with EKS audit log + runtime monitoring
# -----------------------------------------------------------------------------

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-guardduty"
  })
}

# -----------------------------------------------------------------------------
# SNS topic for critical alarms
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name              = "${var.project_name}-${var.environment}-alarms"
  kms_master_key_id = var.kms_key_arn

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------

# Alarm: EKS cluster failed authentications (possible brute force / misconfig)
resource "aws_cloudwatch_log_metric_filter" "failed_auth" {
  name           = "${var.project_name}-${var.environment}-failed-auth"
  pattern        = "{ $.verb = \"create\" && $.responseStatus.code >= 401 && $.responseStatus.code < 500 }"
  log_group_name = var.eks_log_group_name

  metric_transformation {
    name      = "FailedAuthCount"
    namespace = "EKS/${var.project_name}"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "failed_auth" {
  alarm_name          = "${var.project_name}-${var.environment}-failed-auth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedAuthCount"
  namespace           = "EKS/${var.project_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Triggered when more than 10 failed auth attempts occur in a 5-minute window"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# Alarm: High CPU on worker nodes
resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-node-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Worker node CPU above 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = var.node_autoscaling_group_name
  }

  tags = var.tags
}

# Alarm: GuardDuty findings
resource "aws_cloudwatch_metric_alarm" "guardduty_findings" {
  alarm_name          = "${var.project_name}-${var.environment}-guardduty-findings"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FindingCount"
  namespace           = "AWS/GuardDuty"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "GuardDuty has detected new security findings"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Container Insights
# Enabled via EKS add-on so worker nodes send container-level metrics
# and logs (CPU, memory, disk, restarts) to CloudWatch.
# -----------------------------------------------------------------------------

resource "aws_eks_addon" "cloudwatch_observability" {
  count        = var.enable_container_insights ? 1 : 0
  cluster_name = var.cluster_name
  addon_name   = "amazon-cloudwatch-observability"

  tags = var.tags
}
