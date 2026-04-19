provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name       = "${var.project_name}-${var.environment}"
  app_secret_name    = var.app_secrets_name != "" ? var.app_secrets_name : "${var.project_name}-${var.environment}-backend"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Phase 6: Application Secret Container in AWS Secrets Manager
# Secret values are written manually or via CI; Terraform only manages the
# encrypted secret object and IAM access boundaries.
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app_backend" {
  name                    = local.app_secret_name
  description             = "Backend application secret bundle"
  kms_key_id              = module.security.kms_key_arn
  recovery_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = local.app_secret_name
  })
}

# -----------------------------------------------------------------------------
# Phase 2a: VPC — Network foundation with public/private subnet separation
# -----------------------------------------------------------------------------

module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.availability_zones
  cluster_name       = local.cluster_name
  enable_flow_logs   = var.enable_flow_logs
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# Phase 2b: IAM — Least-privilege roles for cluster and nodes
# -----------------------------------------------------------------------------

module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}

# -----------------------------------------------------------------------------
# Phase 2c: Security — Security groups, NACLs, and KMS encryption key
# -----------------------------------------------------------------------------

module "security" {
  source = "./modules/security"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  vpc_cidr_block     = module.vpc.vpc_cidr_block
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# Phase 2d: EKS — Kubernetes cluster with managed node group
# -----------------------------------------------------------------------------

module "eks" {
  source = "./modules/eks"

  project_name              = var.project_name
  environment               = var.environment
  cluster_version           = var.cluster_version
  private_subnet_ids        = module.vpc.private_subnet_ids
  cluster_role_arn          = module.iam.eks_cluster_role_arn
  node_role_arn             = module.iam.eks_node_group_role_arn
  cluster_security_group_id = module.security.eks_cluster_security_group_id
  node_security_group_id    = module.security.eks_nodes_security_group_id
  kms_key_arn               = module.security.kms_key_arn
  node_instance_types       = var.node_instance_types
  node_desired_size         = var.node_desired_size
  node_min_size             = var.node_min_size
  node_max_size             = var.node_max_size
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  tags                      = local.common_tags
}

# -----------------------------------------------------------------------------
# IRSA: Workload IAM Role for application pods
# Created after EKS so we can reference the OIDC provider.
# Scoped to a specific Kubernetes service account (app-backend).
# -----------------------------------------------------------------------------

resource "aws_iam_role" "app_workload" {
  name = "${var.project_name}-${var.environment}-app-workload-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:default:app-backend"
            "${replace(module.eks.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-app-workload-role"
  })
}

resource "aws_iam_role_policy" "app_workload_secrets" {
  name = "${var.project_name}-${var.environment}-secrets-read"
  role = aws_iam_role.app_workload.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.app_backend.arn,
          "${aws_secretsmanager_secret.app_backend.arn}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = module.security.kms_key_arn
      }
    ]
  })
}
