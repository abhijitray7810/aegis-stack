# Aegis Stack — Setup Guide

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.6 | `brew install terraform` |
| kubectl | >= 1.28 | `brew install kubectl` |
| Helm | >= 3.13 | `brew install helm` |
| AWS CLI | >= 2.15 | `brew install awscli` |
| jq | >= 1.6 | `brew install jq` |
| cosign | >= 2.2 | `brew install cosign` |
| syft | >= 1.0 | `brew install syft` |
| opa | >= 0.59 | `brew install opa` |
| conftest | >= 0.47 | `brew install conftest` |

## Step 1 — AWS Setup

```bash
# Configure AWS credentials
aws configure

# Create S3 bucket + DynamoDB table for Terraform state
aws s3 mb s3://aegis-terraform-state --region us-east-1
aws s3api put-bucket-versioning \
  --bucket aegis-terraform-state \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption \
  --bucket aegis-terraform-state \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws dynamodb create-table \
  --table-name aegis-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Step 2 — Infrastructure

```bash
cp infrastructure/terraform.tfvars.example infrastructure/terraform.tfvars
# Edit terraform.tfvars — set your values

make infra-init
make infra-plan   # review carefully
make infra-apply
```

## Step 3 — Cluster Bootstrap

```bash
make kubeconfig
make cluster-bootstrap   # applies namespaces + ArgoCD

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Get initial ArgoCD password
make argocd-password
```

## Step 4 — Security Stack

```bash
# Deploy in order (dependencies matter)
make security-deploy

# Verify each component
kubectl get pods -n cert-manager
kubectl get pods -n vault
kubectl get pods -n gatekeeper-system
kubectl get pods -n kyverno
kubectl get pods -n falco
kubectl get pods -n istio-system
kubectl get pods -n monitoring
```

## Step 5 — Vault Initialisation (first time only)

```bash
make vault-init      # generates init-keys.json — store securely offline!
make vault-unseal    # uses first 3 keys from init-keys.json
make vault-configure # applies Kubernetes auth + policies
```

> **CRITICAL**: After `vault-init`, move `vault/init-keys.json` to offline secure storage immediately and delete the local copy.

## Step 6 — Deploy Workloads

```bash
make workloads-deploy
make tekton-install
make tekton-tasks
```

## Step 7 — Verify

```bash
make verify
make compliance-scan
```

## Ongoing Operations

```bash
# Run compliance scan
make compliance-scan

# Chaos test (triggers Falco alert)
make chaos

# Watch Falco alerts live
kubectl logs -n falco -l app=falco -f | jq .

# Run policy tests
make test-opa

# Rotate: re-run sign job
cosign sign --yes <IMAGE@DIGEST>
```
