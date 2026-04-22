# -----------------------------------------------------------------------------
# Phase 7: Container Security
# Amazon ECR repositories for frontend and backend with:
#   - Enhanced scanning (continuous CVE scanning via Inspector)
#   - KMS encryption at rest
#   - Immutable tags (prevents overwrite of deployed image tags)
#   - Lifecycle policy to clean up untagged / old images
# -----------------------------------------------------------------------------

locals {
  repositories = toset(["frontend", "backend"])
}

resource "aws_ecr_repository" "app" {
  for_each = local.repositories

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${each.key}"
    Tier = each.key
  })
}

# Enable continuous (enhanced) scanning at the registry level.
resource "aws_ecr_registry_scanning_configuration" "enhanced" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "${var.project_name}/*"
      filter_type = "WILDCARD"
    }
  }
}

# Lifecycle policy: keep the 10 most recent tagged images, expire
# untagged images after 1 day.
resource "aws_ecr_lifecycle_policy" "app" {
  for_each = aws_ecr_repository.app

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the 10 most recent tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
