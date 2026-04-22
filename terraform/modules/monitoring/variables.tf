variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "eks_log_group_name" {
  description = "Name of the CloudWatch log group for EKS control plane logs"
  type        = string
}

variable "node_autoscaling_group_name" {
  description = "Name of the EKS node auto scaling group"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS key ARN for SNS encryption"
  type        = string
}

variable "alarm_email" {
  description = "Email address for alarm notifications (optional)"
  type        = string
  default     = ""
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights add-on"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
