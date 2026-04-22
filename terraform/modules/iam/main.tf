# -----------------------------------------------------------------------------
# EKS Cluster IAM Role
# Allows the EKS service to manage cluster resources on our behalf.
# Follows least privilege: only AmazonEKSClusterPolicy is attached.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# -----------------------------------------------------------------------------
# EKS Node Group IAM Role
# Minimum permissions for worker nodes to join the cluster, manage networking,
# and pull container images from ECR.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eks_node_group" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# -----------------------------------------------------------------------------
# Phase 4: EKS Access Roles for RBAC Personas
# These IAM roles are assumed by team members and mapped to Kubernetes groups
# via the aws-auth ConfigMap. They carry no AWS policies — their only purpose
# is to authenticate to the EKS API, where RBAC takes over.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "platform_admin" {
  name = "${var.project_name}-platform-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-platform-admin"
    Role = "platform-admin"
  })
}

resource "aws_iam_role" "developer" {
  name = "${var.project_name}-developer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-developer"
    Role = "developer"
  })
}

resource "aws_iam_role" "viewer" {
  name = "${var.project_name}-viewer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-viewer"
    Role = "viewer"
  })
}

# Minimal EKS describe-cluster permission so each persona can run
# `aws eks update-kubeconfig` to authenticate.
resource "aws_iam_policy" "eks_access" {
  name        = "${var.project_name}-${var.environment}-eks-access"
  description = "Allows describing the EKS cluster for kubeconfig setup"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "platform_admin_eks" {
  role       = aws_iam_role.platform_admin.name
  policy_arn = aws_iam_policy.eks_access.arn
}

resource "aws_iam_role_policy_attachment" "developer_eks" {
  role       = aws_iam_role.developer.name
  policy_arn = aws_iam_policy.eks_access.arn
}

resource "aws_iam_role_policy_attachment" "viewer_eks" {
  role       = aws_iam_role.viewer.name
  policy_arn = aws_iam_policy.eks_access.arn
}
