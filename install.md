Here’s a clean, professional **`install.md`** file you can put in your repo 👇

---

# 📦 Aegis Stack — Tool Installation Guide

This guide sets up all required CLI tools for running the **Aegis Stack (DevSecOps Kubernetes Platform)** on **WSL / Ubuntu / Linux**.

---

## 🚀 1. System Preparation

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget unzip git jq
```

---

## 🔧 2. Install Core DevOps Tools

### 🔹 Terraform

```bash
wget https://releases.hashicorp.com/terraform/1.14.9/terraform_1.14.9_linux_amd64.zip
unzip terraform_1.14.9_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform -v
```

---

### 🔹 kubectl

```bash
curl -LO https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

---

### 🔹 Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

---

### 🔹 AWS CLI

```bash
sudo apt install -y awscli
aws --version
```

---

## 🔐 3. Security & DevSecOps Tools

### 🔹 Cosign (Image Signing)

```bash
curl -O -L https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
cosign version
```

---

### 🔹 Syft (SBOM Generator)

```bash
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh
sudo mv ./bin/syft /usr/local/bin/
syft version
```

---

### 🔹 OPA (Policy Engine) ⚠️ Compatible Version

```bash
curl -L -o opa https://openpolicyagent.org/downloads/v0.56.0/opa_linux_amd64
chmod +x opa
sudo mv opa /usr/local/bin/
opa version
```

---

### 🔹 Conftest (Policy Testing)

```bash
wget https://github.com/open-policy-agent/conftest/releases/download/v0.45.0/conftest_0.45.0_Linux_x86_64.tar.gz
tar xzf conftest_0.45.0_Linux_x86_64.tar.gz
sudo mv conftest /usr/local/bin/
conftest --version
```

---

## ✅ 4. Verification

Run all commands to confirm installation:

```bash
terraform -v
kubectl version --client
helm version
aws --version
cosign version
syft version
opa version
conftest --version
```

---

## ⚙️ 5. AWS Setup

```bash
aws configure
```

Provide:

* AWS Access Key
* Secret Key
* Region (e.g., ap-south-1)

---

## 🧠 Notes

* ⚠️ Use **OPA v0.56.0** for compatibility with Conftest
* ✔ Terraform ≥ 1.14 recommended
* ✔ Works best on **WSL2 / Ubuntu 22.04+**
* ❌ `brew` is not required

---

## 🎯 Next Step

Proceed to:

👉 `terraform init → plan → apply`
👉 EKS cluster bootstrap
👉 Security stack deployment (Gatekeeper, Kyverno, Falco, Vault, Istio)

---

## 🔥 Tip

If anything fails:

```bash
which terraform kubectl helm
```

Ensure binaries exist in:

```
/usr/local/bin/
```

