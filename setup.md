Here’s a clean, **step-by-step `setup.md`** you can directly add to your repo 👇

---

# ⚙️ Aegis Stack — Setup Guide

This guide walks you through deploying the **Aegis Stack (DevSecOps Kubernetes Platform)** end-to-end on AWS.

---

## 📌 Prerequisites

Make sure you’ve completed:

* ✔ Tools installed (`install.md`)
* ✔ AWS account with programmatic access
* ✔ IAM permissions (EKS, EC2, IAM, S3, KMS, CloudWatch)

---

## 🔐 1. Configure AWS

```bash id="aws-setup"
aws configure
```

Provide:

* Access Key
* Secret Key
* Region (recommended: `ap-south-1`)

---

## 🗄️ 2. Create Terraform Backend

Terraform requires remote state storage.

### Create S3 bucket

```bash id="s3-backend"
aws s3 mb s3://aegis-terraform-state-<your-unique-id>
```

### Create DynamoDB table (state lock)

```bash id="dynamodb-backend"
aws dynamodb create-table \
  --table-name aegis-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

---

## ☁️ 3. Deploy Infrastructure (Terraform)

```bash id="tf-init"
terraform init
```

```bash id="tf-plan"
terraform plan
```

```bash id="tf-apply"
terraform apply
```

⏱️ Takes ~15–25 minutes
Creates:

* VPC (multi-AZ)
* Private EKS cluster
* KMS encryption
* IRSA roles
* Base monitoring stack

---

## 🔗 4. Configure kubectl

```bash id="kubeconfig"
aws eks update-kubeconfig \
  --region <your-region> \
  --name <cluster-name>
```

Verify:

```bash id="verify-nodes"
kubectl get nodes
```

---

## 🚀 5. Cluster Bootstrap

```bash id="bootstrap"
kubectl apply -f bootstrap/
```

This sets up:

* Namespaces
* ArgoCD
* Base configs

---

## 🛡️ 6. Deploy Security Stack

### OPA Gatekeeper

```bash id="gatekeeper"
kubectl apply -f gatekeeper/
```

### Kyverno

```bash id="kyverno"
kubectl apply -f kyverno/
```

### Falco

```bash id="falco"
kubectl apply -f falco/
```

Verify:

```bash id="verify-security"
kubectl get pods -A
```

---

## 🔐 7. Deploy Vault (Secrets Management)

```bash id="vault"
kubectl apply -f vault/
```

After deployment:

* Initialize Vault
* Unseal (auto via KMS)
* Configure Kubernetes auth

---

## 🌐 8. Deploy Istio (Service Mesh)

```bash id="istio"
kubectl apply -f istio/
```

This enables:

* STRICT mTLS
* Zero-trust networking
* Authorization policies

---

## 📊 9. Deploy Observability Stack

```bash id="monitoring"
kubectl apply -f monitoring/
```

Includes:

* Prometheus
* Grafana
* Loki

---

## 🔁 10. Setup CI/CD Pipeline

```bash id="cicd"
kubectl apply -f tekton/
```

Pipeline includes:

* Trivy → Syft → OPA → Cosign

---

## 📦 11. Deploy Workloads

```bash id="workloads"
kubectl apply -f workloads/
```

Includes:

* Secure API
* SBOM verifier CronJob

---

## 🧪 12. Verification & Testing

### Run compliance checks

```bash id="compliance"
bash tests/compliance/mock-scan.sh
```

### Optional: Trigger runtime attack (Falco)

```bash id="chaos"
kubectl apply -f tests/chaos/falco-injection.yaml
```

---

## ✅ 13. Validate System

Check:

```bash id="validation"
kubectl get pods -A
kubectl get svc -A
kubectl get events -A
```

Ensure:

* No privileged containers
* All pods running
* Vault healthy
* Policies enforced

---

## 🚨 Troubleshooting

### Common Issues

**❌ EKS not accessible**

```bash id="fix-kube"
aws eks update-kubeconfig --region <region> --name <cluster>
```

**❌ Pods stuck in Pending**

```bash id="describe-pod"
kubectl describe pod <pod-name>
```

**❌ Policy blocking deployment**

```bash id="gatekeeper-check"
kubectl get constraint
```

---

## 🔄 Full Deployment Order (Quick View)

```id="flow"
1. AWS configure
2. Terraform backend (S3 + DynamoDB)
3. Terraform apply (EKS + infra)
4. kubeconfig setup
5. Bootstrap cluster
6. Security stack (Gatekeeper, Kyverno, Falco)
7. Vault
8. Istio
9. Monitoring
10. CI/CD
11. Workloads
12. Verification
```

---

## 🎯 Next Steps

* Access Grafana dashboards
* Monitor Falco alerts
* Trigger CI/CD pipeline
* Test policy enforcement

---

## 🔥 Tip

Deploy step-by-step — don’t apply everything at once.

---

This file is **ready to commit** as:

```bash id="file-name"
setup.md
```

---

