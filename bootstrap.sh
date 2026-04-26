#!/usr/bin/env bash
# =============================================================================
# Aegis Stack — One-Shot Bootstrap Script
# Usage: bash bootstrap.sh [--dry-run] [--skip-infra] [--skip-cluster] [--destroy]
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}\n"; }

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
SKIP_INFRA=false
SKIP_CLUSTER=false
DESTROY=false

for arg in "$@"; do
  case $arg in
    --dry-run)      DRY_RUN=true ;;
    --skip-infra)   SKIP_INFRA=true ;;
    --skip-cluster) SKIP_CLUSTER=true ;;
    --destroy)      DESTROY=true ;;
    --help)
      echo "Usage: bash bootstrap.sh [--dry-run] [--skip-infra] [--skip-cluster] [--destroy]"
      echo "  --dry-run       Print steps without executing"
      echo "  --skip-infra    Skip Terraform (use existing cluster)"
      echo "  --skip-cluster  Skip cluster bootstrap (already done)"
      echo "  --destroy       Tear down everything"
      exit 0 ;;
  esac
done

run() {
  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
  else
    eval "$@"
  fi
}

# ── Configuration — edit these or export before running ───────────────────────
: "${AWS_REGION:=us-east-1}"
: "${CLUSTER_NAME:=aegis-production}"
: "${TF_VARS_FILE:=infrastructure/terraform.tfvars}"
: "${GRAFANA_ADMIN_PASSWORD:=}"
: "${SLACK_WEBHOOK_URL:=}"

# ── Derived ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# DESTROY MODE
# =============================================================================
if $DESTROY; then
  header "DESTROY — Tearing down Aegis Stack"
  warn "This will DELETE the entire cluster and all infrastructure."
  read -r -p "Type 'yes-destroy' to confirm: " CONFIRM
  [[ "$CONFIRM" == "yes-destroy" ]] || error "Aborted."

  info "Destroying Terraform infrastructure..."
  run "cd infrastructure && terraform destroy -var-file=../terraform.tfvars -auto-approve; cd .."
  success "Infrastructure destroyed."
  exit 0
fi

# =============================================================================
# STEP 0 — Preflight: check required tools
# =============================================================================
header "Step 0 — Preflight Checks"

check_tool() {
  local tool=$1 version_cmd=${2:-"$1 --version"}
  if command -v "$tool" &>/dev/null; then
    local ver
    ver=$(eval "$version_cmd" 2>&1 | head -1 || true)
    success "$tool  →  $ver"
  else
    error "$tool not found. Install it and re-run.\n  See: docs/setup.md"
  fi
}

check_tool terraform "terraform version | head -1"
check_tool kubectl   "kubectl version --client --short 2>/dev/null | head -1"
check_tool helm      "helm version --short"
check_tool aws       "aws --version 2>&1 | head -1"
check_tool jq        "jq --version"
check_tool cosign    "cosign version 2>&1 | grep -i version | head -1"
check_tool syft      "syft version | head -1"
check_tool opa       "opa version | head -1"
check_tool conftest  "conftest --version"

# Check AWS credentials
info "Checking AWS credentials..."
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || error "AWS credentials not configured. Run: aws configure"
AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
success "AWS Account: $AWS_ACCOUNT"
success "AWS Identity: $AWS_USER"

# Check tfvars exists
if [[ ! -f "$TF_VARS_FILE" ]]; then
  warn "terraform.tfvars not found — creating from example..."
  run "cp infrastructure/terraform.tfvars.example $TF_VARS_FILE"
  echo ""
  warn "Please fill in $TF_VARS_FILE before continuing."
  warn "Required values:"
  warn "  - grafana_admin_password (strong password)"
  warn "  - slack_webhook_url      (optional, for alerts)"
  echo ""
  if ! $DRY_RUN; then
    read -r -p "Press ENTER once you've edited $TF_VARS_FILE, or Ctrl+C to abort: "
  fi
fi

# Check passwords are set in tfvars
if grep -q 'CHANGE_ME' "$TF_VARS_FILE" 2>/dev/null; then
  error "terraform.tfvars still has placeholder values. Edit $TF_VARS_FILE first."
fi

success "Preflight checks passed."

# =============================================================================
# STEP 1 — S3 State Backend (idempotent)
# =============================================================================
header "Step 1 — Terraform State Backend"

STATE_BUCKET="aegis-terraform-state-${AWS_ACCOUNT}"
LOCK_TABLE="aegis-terraform-locks"

info "Ensuring S3 state bucket: $STATE_BUCKET"
if ! aws s3 ls "s3://$STATE_BUCKET" &>/dev/null; then
  run "aws s3 mb s3://$STATE_BUCKET --region $AWS_REGION"
  run "aws s3api put-bucket-versioning \
    --bucket $STATE_BUCKET \
    --versioning-configuration Status=Enabled"
  run "aws s3api put-bucket-encryption \
    --bucket $STATE_BUCKET \
    --server-side-encryption-configuration \
    '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'"
  run "aws s3api put-public-access-block \
    --bucket $STATE_BUCKET \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'"
  success "State bucket created: $STATE_BUCKET"
else
  success "State bucket already exists: $STATE_BUCKET"
fi

info "Ensuring DynamoDB lock table: $LOCK_TABLE"
if ! aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$AWS_REGION" &>/dev/null; then
  run "aws dynamodb create-table \
    --table-name $LOCK_TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $AWS_REGION"
  success "DynamoDB lock table created."
else
  success "DynamoDB lock table already exists."
fi

# Patch backend bucket name into main.tf if needed
if grep -q 'aegis-terraform-state"' infrastructure/main.tf; then
  run "sed -i 's|bucket.*=.*\"aegis-terraform-state\"|bucket = \"$STATE_BUCKET\"|' infrastructure/main.tf"
fi

# =============================================================================
# STEP 2 — Run OPA / Conftest policy tests
# =============================================================================
header "Step 2 — Policy & Linting Checks"

info "Running OPA policy unit tests..."
run "opa test policies/ infrastructure/policies/ -v"
success "OPA tests passed."

info "Running Conftest on Kubernetes manifests..."
run "conftest test clusters/ --policy policies/ --all-namespaces --output table" || {
  warn "Conftest found policy issues — review above before deploying."
  if ! $DRY_RUN; then
    read -r -p "Continue anyway? [y/N]: " ANS
    [[ "$ANS" =~ ^[Yy]$ ]] || exit 1
  fi
}

info "Checking Terraform formatting..."
run "cd infrastructure && terraform fmt -check -recursive; cd .."

success "Policy checks passed."

# =============================================================================
# STEP 3 — Terraform: provision EKS + VPC + Vault + Monitoring
# =============================================================================
if ! $SKIP_INFRA; then
  header "Step 3 — Infrastructure (Terraform)"

  info "Initialising Terraform..."
  run "cd infrastructure && terraform init -upgrade -reconfigure \
    -backend-config=\"bucket=$STATE_BUCKET\" \
    -backend-config=\"region=$AWS_REGION\"; cd .."

  info "Planning Terraform changes..."
  run "cd infrastructure && terraform plan -var-file=../terraform.tfvars -out=tfplan; cd .."

  echo ""
  warn "Review the plan above."
  if ! $DRY_RUN; then
    read -r -p "Apply Terraform plan? [y/N]: " ANS
    [[ "$ANS" =~ ^[Yy]$ ]] || error "Aborted at Terraform apply."
  fi

  info "Applying Terraform (this takes ~15-20 minutes)..."
  run "cd infrastructure && terraform apply tfplan; cd .."
  success "Infrastructure provisioned."
else
  warn "Skipping Terraform (--skip-infra flag set)."
fi

# =============================================================================
# STEP 4 — Update kubeconfig
# =============================================================================
header "Step 4 — Kubeconfig"

info "Updating kubeconfig for cluster: $CLUSTER_NAME"
run "aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION"

info "Verifying cluster connectivity..."
run "kubectl cluster-info"
run "kubectl get nodes"
success "Cluster accessible."

# =============================================================================
# STEP 5 — Bootstrap cluster (namespaces + ArgoCD)
# =============================================================================
if ! $SKIP_CLUSTER; then
  header "Step 5 — Cluster Bootstrap (Namespaces + ArgoCD)"

  info "Applying namespaces..."
  run "kubectl apply -f clusters/production/base/namespaces.yaml"

  info "Installing ArgoCD..."
  run "kubectl apply -k clusters/production/base/argocd/"

  info "Waiting for ArgoCD to be ready (up to 5 minutes)..."
  run "kubectl wait --for=condition=available deployment/argocd-server \
    -n argocd --timeout=300s"
  success "ArgoCD ready."

  ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "unavailable")
  echo ""
  echo -e "  ${BOLD}ArgoCD URL:${NC}      https://argocd.aegis.internal"
  echo -e "  ${BOLD}ArgoCD user:${NC}     admin"
  echo -e "  ${BOLD}ArgoCD password:${NC} $ARGOCD_PASS"
  echo ""
fi

# =============================================================================
# STEP 6 — Security stack (cert-manager → Vault → Gatekeeper → Kyverno → Falco → Istio)
# =============================================================================
header "Step 6 — Security Stack"

wait_ready() {
  local ns=$1 label=$2 timeout=${3:-300}
  info "Waiting for $label in $ns (timeout: ${timeout}s)..."
  if ! $DRY_RUN; then
    kubectl wait --for=condition=available deployment \
      -n "$ns" -l "$label" --timeout="${timeout}s" 2>/dev/null || \
    kubectl wait --for=condition=ready pod \
      -n "$ns" -l "$label" --timeout="${timeout}s" 2>/dev/null || \
    warn "Timeout waiting for $label in $ns — continuing anyway"
  fi
}

info "Deploying cert-manager..."
run "kubectl apply -k clusters/production/apps/security/cert-manager/"
wait_ready cert-manager "app.kubernetes.io/instance=cert-manager"

info "Deploying Vault..."
run "kubectl apply -k clusters/production/apps/security/vault/"
wait_ready vault "app.kubernetes.io/name=vault" 600

info "Deploying OPA Gatekeeper..."
run "kubectl apply -k clusters/production/apps/security/gatekeeper/"
wait_ready gatekeeper-system "control-plane=controller-manager"

info "Deploying Kyverno..."
run "kubectl apply -k clusters/production/apps/security/kyverno/"
wait_ready kyverno "app.kubernetes.io/name=kyverno"

info "Deploying Falco..."
run "kubectl apply -k clusters/production/apps/security/falco/"
wait_ready falco "app.kubernetes.io/name=falco" 300

info "Deploying Istio..."
run "kubectl apply -k clusters/production/apps/istio/"
wait_ready istio-system "app=istiod"

success "Security stack deployed."

# =============================================================================
# STEP 7 — Monitoring (Prometheus + Grafana + Loki)
# =============================================================================
header "Step 7 — Monitoring Stack"

info "Deploying monitoring..."
run "kubectl apply -k clusters/production/apps/monitoring/"
run "kubectl apply -f monitoring/prometheus-rules/falco-alerts.yaml"
run "kubectl apply -f monitoring/prometheus-rules/gatekeeper-metrics.yaml"
wait_ready monitoring "app.kubernetes.io/name=grafana" 300
success "Monitoring deployed."

# =============================================================================
# STEP 8 — Vault Initialisation
# =============================================================================
header "Step 8 — Vault Init & Configure"

if ! $DRY_RUN; then
  VAULT_STATUS=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null \
    | jq -r '.initialized' 2>/dev/null || echo "false")
else
  VAULT_STATUS="false"
fi

if [[ "$VAULT_STATUS" == "false" ]]; then
  warn "Vault is not initialised — initialising now..."
  run "kubectl exec -n vault vault-0 -- vault operator init \
    -key-shares=5 -key-threshold=3 -format=json > vault/init-keys.json"
  success "Vault initialised. Keys saved to vault/init-keys.json"
  error "STOP — Move vault/init-keys.json to OFFLINE secure storage NOW, then re-run with --skip-infra --skip-cluster."
else
  info "Vault already initialised (KMS auto-unseal active)."
fi

info "Configuring Vault Kubernetes auth..."
run "kubectl apply -f vault/kubernetes-auth-config.yaml"
success "Vault configured."

# =============================================================================
# STEP 9 — Workloads
# =============================================================================
header "Step 9 — Workloads"

info "Deploying secure-api..."
run "kubectl apply -k clusters/production/apps/workloads/secure-api/"
info "Deploying sbom-verifier..."
run "kubectl apply -k clusters/production/apps/workloads/sbom-verifier/"
success "Workloads deployed."

# =============================================================================
# STEP 10 — Tekton CI/CD
# =============================================================================
header "Step 10 — Tekton Pipelines"

info "Installing Tekton Pipelines + Triggers..."
run "kubectl apply --filename \
  https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml"
run "kubectl apply --filename \
  https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml"

info "Waiting for Tekton..."
run "kubectl wait --for=condition=available deployment/tekton-pipelines-controller \
  -n tekton-pipelines --timeout=300s"

info "Applying Tekton tasks, pipeline, and trigger..."
run "kubectl apply -f cicd/tekton/tasks/"
run "kubectl apply -f cicd/tekton/pipelines/"
run "kubectl apply -f cicd/tekton/triggers/"
success "Tekton ready."

# =============================================================================
# STEP 11 — Final verification
# =============================================================================
header "Step 11 — Verification"

run "bash tests/compliance/mock-scan.sh" || warn "Some compliance checks failed — review output above."

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  ✅  Aegis Stack Bootstrap Complete!${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "  1. Port-forward Grafana:    kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
echo -e "     Open:                    http://localhost:3000  (admin / your-password)"
echo -e ""
echo -e "  2. Port-forward ArgoCD UI:  kubectl port-forward svc/argocd-server 8080:443 -n argocd"
echo -e "     Open:                    https://localhost:8080"
echo -e ""
echo -e "  3. Watch Falco alerts:      kubectl logs -n falco -l app=falco -f | jq ."
echo -e ""
echo -e "  4. Run chaos test:          kubectl apply -f tests/chaos/falco-injection.yaml"
echo -e ""
echo -e "  5. Run compliance scan:     bash tests/compliance/mock-scan.sh"
echo -e ""
echo -e "  ${BOLD}${RED}IMPORTANT:${NC} If vault/init-keys.json was created, move it offline NOW."
echo ""
