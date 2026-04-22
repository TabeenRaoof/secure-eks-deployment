variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "fintech-secure"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "endpoint_public_access" {
  description = "Enable public access to the EKS API endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public EKS API endpoint (restrict to your team's IPs)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for security auditing"
  type        = bool
  default     = true
}

variable "app_secrets_name" {
  description = "Optional override for the application Secrets Manager secret name"
  type        = string
  default     = ""
}

variable "ecr_force_delete" {
  description = "Allow Terraform to delete ECR repositories that still contain images (useful for dev/demo)"
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email address subscribed to the alarms SNS topic (leave empty to skip subscription)"
  type        = string
  default     = ""
}

variable "enable_container_insights" {
  description = "Install the CloudWatch Container Insights EKS add-on"
  type        = bool
  default     = true
}
