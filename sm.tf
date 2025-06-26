# ==============================================================================
# AWS Secrets Manager Terraform 設定
# ==============================================================================

# Terraform プロバイダ設定
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS プロバイダ設定
provider "aws" {
  region = var.aws_region
}

# ==============================================================================
# 変数定義
# ==============================================================================

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト名"
  type        = string
  default     = "myapp"
}

variable "environment" {
  description = "環境名 (dev, staging, prod等)"
  type        = string
  default     = "dev"
}

variable "secrets_list" {
  description = "作成するシークレットのリスト"
  type = list(object({
    name        = string
    description = string
  }))
  default = [
    {
      name        = "database-credentials"
      description = "データベース接続情報"
    },
    {
      name        = "api-keys"
      description = "外部API接続キー"
    },
    {
      name        = "jwt-secret"
      description = "JWT署名用シークレットキー"
    }
  ]
}

variable "trusted_accounts" {
  description = "シークレットアクセスを許可するAWSアカウントIDのリスト"
  type        = list(string)
  default     = []
}

# ==============================================================================
# ローカル値
# ==============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ==============================================================================
# KMS キー (シークレット暗号化用)
# ==============================================================================

resource "aws_kms_key" "secrets_manager" {
  description             = "KMS key for Secrets Manager encryption"
  deletion_window_in_days = 7
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager to use the key"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secrets-kms-key"
  })
}

resource "aws_kms_alias" "secrets_manager" {
  name          = "alias/${local.name_prefix}-secrets-manager"
  target_key_id = aws_kms_key.secrets_manager.key_id
}

# ==============================================================================
# Secrets Manager シークレット
# ==============================================================================

resource "aws_secretsmanager_secret" "secrets" {
  for_each = { for secret in var.secrets_list : secret.name => secret }

  name        = "${local.name_prefix}-${each.value.name}"
  description = each.value.description
  kms_key_id  = aws_kms_key.secrets_manager.arn
  
  # シークレット削除時の復旧期間（日数）
  recovery_window_in_days = 7

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-${each.value.name}"
    SecretType  = each.value.name
  })
}

# ==============================================================================
# IAM ロール (アプリケーション用)
# ==============================================================================

# アプリケーション用IAMロール
resource "aws_iam_role" "application" {
  name = "${local.name_prefix}-application-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com",
            "ecs-tasks.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-application-role"
  })
}

# アプリケーション用IAMポリシー
resource "aws_iam_policy" "secrets_access" {
  name        = "${local.name_prefix}-secrets-access-policy"
  description = "Policy for accessing Secrets Manager secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:BatchGetSecretValue"
        ]
        Resource = [
          for secret in aws_secretsmanager_secret.secrets : secret.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.secrets_manager.arn
        ]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secrets-access-policy"
  })
}

# ポリシーをロールにアタッチ
resource "aws_iam_role_policy_attachment" "application_secrets_access" {
  role       = aws_iam_role.application.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

# EC2インスタンス用のインスタンスプロファイル
resource "aws_iam_instance_profile" "application" {
  name = "${local.name_prefix}-application-profile"
  role = aws_iam_role.application.name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-application-profile"
  })
}

# ==============================================================================
# IAM グループ (管理者用)
# ==============================================================================

# Secrets Manager管理者グループ
resource "aws_iam_group" "secrets_managers" {
  name = "${local.name_prefix}-secrets-managers"
}

# Secrets Manager管理用ポリシー
resource "aws_iam_policy" "secrets_management" {
  name        = "${local.name_prefix}-secrets-management-policy"
  description = "Policy for managing Secrets Manager secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:*"
        ]
        Resource = [
          for secret in aws_secretsmanager_secret.secrets : secret.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = [
          aws_kms_key.secrets_manager.arn
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secrets-management-policy"
  })
}

# グループにポリシーをアタッチ
resource "aws_iam_group_policy_attachment" "secrets_managers" {
  group      = aws_iam_group.secrets_managers.name
  policy_arn = aws_iam_policy.secrets_management.arn
}

# ==============================================================================
# Secrets Manager リソースベースポリシー (必要に応じて)
# ==============================================================================

# クロスアカウントアクセスが必要な場合のリソースポリシー
resource "aws_secretsmanager_secret_policy" "cross_account" {
  for_each = length(var.trusted_accounts) > 0 ? { for secret in var.secrets_list : secret.name => secret } : {}

  secret_arn = aws_secretsmanager_secret.secrets[each.key].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowTrustedAccountsAccess"
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in var.trusted_accounts : 
            "arn:aws:iam::${account_id}:root"
          ]
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:BatchGetSecretValue"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# CloudWatch Log Group (監査ログ用)
# ==============================================================================

resource "aws_cloudwatch_log_group" "secrets_manager" {
  name              = "/aws/secrets-manager/${local.name_prefix}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secrets-manager-logs"
  })
}

# ==============================================================================
# データソース
# ==============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==============================================================================
# 出力値
# ==============================================================================

output "secrets_arns" {
  description = "作成されたシークレットのARN一覧"
  value = {
    for name, secret in aws_secretsmanager_secret.secrets : 
    name => secret.arn
  }
}

output "kms_key_arn" {
  description = "Secrets Manager用KMSキーのARN"
  value       = aws_kms_key.secrets_manager.arn
}

output "kms_key_alias" {
  description = "Secrets Manager用KMSキーのエイリアス"
  value       = aws_kms_alias.secrets_manager.name
}

output "application_role_arn" {
  description = "アプリケーション用IAMロールのARN"
  value       = aws_iam_role.application.arn
}

output "instance_profile_name" {
  description = "EC2インスタンス用プロファイル名"
  value       = aws_iam_instance_profile.application.name
}

output "secrets_managers_group_name" {
  description = "Secrets Manager管理者グループ名"
  value       = aws_iam_group.secrets_managers.name
}

output "secrets_info" {
  description = "作成されたシークレットの詳細情報"
  value = {
    for name, secret in aws_secretsmanager_secret.secrets : 
    name => {
      arn         = secret.arn
      name        = secret.name
      description = secret.description
    }
  }
}

# ==============================================================================
# terraform.tfvars.example の内容（参考）
# ==============================================================================

# AWS設定
# aws_region = "ap-northeast-1"

# プロジェクト設定
# project_name = "myapp"
# environment = "dev"

# 作成するシークレット一覧
# secrets_list = [
#   {
#     name        = "database-credentials"
#     description = "データベース接続情報"
#   },
#   {
#     name        = "api-keys"
#     description = "外部API接続キー"
#   },
#   {
#     name        = "jwt-secret"
#     description = "JWT署名用シークレットキー"
#   }
# ]

# 信頼するAWSアカウント（クロスアカウントアクセス用）
# trusted_accounts = ["123456789012", "987654321098"]
