data "aws_caller_identity" "current" {}

# ── IRSA role for Vault ────────────────────────────────────────────────────────
resource "aws_iam_role" "vault" {
  name = "${var.cluster_name}-vault-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.eks_oidc_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.eks_oidc_url, "https://", "")}:sub" = "system:serviceaccount:vault:vault"
          "${replace(var.eks_oidc_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# ── KMS key for Vault auto-unseal ─────────────────────────────────────────────
resource "aws_kms_key" "vault" {
  description             = "Vault auto-unseal key for ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.cluster_name}-vault"
  target_key_id = aws_kms_key.vault.key_id
}

# ── Policy: allow Vault to use KMS for auto-unseal ────────────────────────────
resource "aws_iam_role_policy" "vault_kms" {
  name = "vault-kms-unseal"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Encrypt", "kms:Decrypt", "kms:DescribeKey",
        "kms:GenerateDataKey"
      ]
      Resource = aws_kms_key.vault.arn
    }]
  })
}

# ── Helm: Vault ───────────────────────────────────────────────────────────────
resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = var.vault_version
  namespace        = "vault"
  create_namespace = true
  atomic           = true
  timeout          = 600

  values = [templatefile("${path.module}/vault-values.yaml.tpl", {
    kms_key_id = aws_kms_key.vault.key_id
    aws_region = data.aws_caller_identity.current.id
    role_arn   = aws_iam_role.vault.arn
  })]
}
