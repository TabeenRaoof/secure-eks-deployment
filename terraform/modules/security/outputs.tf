output "eks_cluster_security_group_id" {
  description = "Security group ID for the EKS cluster control plane"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_security_group_id" {
  description = "Security group ID for the EKS worker nodes"
  value       = aws_security_group.eks_nodes.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.arn
}

output "kms_key_id" {
  description = "ID of the KMS key for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.key_id
}
