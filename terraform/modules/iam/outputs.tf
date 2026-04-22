output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_cluster_role_name" {
  description = "Name of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.name
}

output "eks_node_group_role_arn" {
  description = "ARN of the EKS node group IAM role"
  value       = aws_iam_role.eks_node_group.arn
}

output "eks_node_group_role_name" {
  description = "Name of the EKS node group IAM role"
  value       = aws_iam_role.eks_node_group.name
}

output "platform_admin_role_arn" {
  description = "ARN of the platform-admin IAM role (maps to platform-admins K8s group)"
  value       = aws_iam_role.platform_admin.arn
}

output "developer_role_arn" {
  description = "ARN of the developer IAM role (maps to developers K8s group)"
  value       = aws_iam_role.developer.arn
}

output "viewer_role_arn" {
  description = "ARN of the viewer IAM role (maps to viewers K8s group)"
  value       = aws_iam_role.viewer.arn
}
