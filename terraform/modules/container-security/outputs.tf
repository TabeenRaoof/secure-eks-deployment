output "frontend_repository_url" {
  description = "ECR repository URL for the frontend image"
  value       = aws_ecr_repository.app["frontend"].repository_url
}

output "backend_repository_url" {
  description = "ECR repository URL for the backend image"
  value       = aws_ecr_repository.app["backend"].repository_url
}

output "repository_arns" {
  description = "ARNs of all ECR repositories"
  value       = { for k, v in aws_ecr_repository.app : k => v.arn }
}
