variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for ECR encryption"
  type        = string
}

variable "force_delete" {
  description = "Force-delete repositories that still contain images (useful for dev/demo)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
