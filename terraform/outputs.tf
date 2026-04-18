output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL for the EKS API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority" {
  description = "Base64 encoded CA data for cluster authentication"
  value       = module.eks.cluster_certificate_authority
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "node_group_role_arn" {
  description = "ARN of the node group IAM role (needed for aws-auth ConfigMap)"
  value       = module.iam.eks_node_group_role_arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "app_workload_role_arn" {
  description = "ARN of the IRSA workload role for app pods"
  value       = aws_iam_role.app_workload.arn
}

output "app_backend_secret_name" {
  description = "Secrets Manager secret name for backend app config"
  value       = aws_secretsmanager_secret.app_backend.name
}

output "app_backend_secret_arn" {
  description = "Secrets Manager secret ARN for backend app config"
  value       = aws_secretsmanager_secret.app_backend.arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
