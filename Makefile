.PHONY: all infra-init infra-plan infra-apply infra-destroy \
        cluster-bootstrap security-deploy monitoring-deploy \
        verify lint test clean help

CLUSTER_NAME ?= aegis-production
AWS_REGION   ?= us-east-1
TF_DIR       := infrastructure

##@ Infrastructure

infra-init: ## Initialise Terraform
	cd $(TF_DIR) && terraform init -upgrade

infra-plan: ## Plan Terraform changes
	cd $(TF_DIR) && terraform plan -var-file=terraform.tfvars -out=tfplan

infra-apply: ## Apply Terraform (prompts for confirmation)
	cd $(TF_DIR) && terraform apply tfplan

infra-destroy: ## Destroy infrastructure (DANGER)
	cd $(TF_DIR) && terraform destroy -var-file=terraform.tfvars

##@ Cluster Bootstrap

kubeconfig: ## Update local kubeconfig
	aws eks update-kubeconfig --name $(CLUSTER_NAME) --region $(AWS_REGION)

cluster-bootstrap: kubeconfig ## Bootstrap ArgoCD + namespaces
	kubectl apply -f clusters/production/base/namespaces.yaml
	kubectl apply -k clusters/production/base/argocd/

argocd-password: ## Print initial ArgoCD admin password
	kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath="{.data.password}" | base64 -d && echo

##@ Security Stack

security-deploy: ## Deploy full security stack via ArgoCD / kustomize
	kubectl apply -k clusters/production/apps/security/cert-manager/
	kubectl apply -k clusters/production/apps/security/vault/
	kubectl apply -k clusters/production/apps/security/gatekeeper/
	kubectl apply -k clusters/production/apps/security/kyverno/
	kubectl apply -k clusters/production/apps/security/falco/
	kubectl apply -k clusters/production/apps/istio/
	kubectl apply -k clusters/production/apps/monitoring/

workloads-deploy: ## Deploy example secure workloads
	kubectl apply -k clusters/production/apps/workloads/secure-api/
	kubectl apply -k clusters/production/apps/workloads/sbom-verifier/

##@ Tekton CI/CD

tekton-install: ## Install Tekton Pipelines + Triggers
	kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
	kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

tekton-tasks: ## Apply Tekton tasks and pipeline
	kubectl apply -f cicd/tekton/tasks/
	kubectl apply -f cicd/tekton/pipelines/
	kubectl apply -f cicd/tekton/triggers/

##@ Observability

monitoring-deploy: ## Deploy Prometheus + Grafana + Loki
	kubectl apply -k clusters/production/apps/monitoring/

##@ Vault

vault-init: ## Initialise Vault (run once after deploy)
	kubectl exec -n vault vault-0 -- vault operator init \
	  -key-shares=5 -key-threshold=3 -format=json > vault/init-keys.json
	@echo "⚠️  Store vault/init-keys.json in a secure offline location!"

vault-unseal: ## Unseal Vault using keys from init-keys.json
	@for key in $$(jq -r '.unseal_keys_b64[]' vault/init-keys.json | head -3); do \
	  kubectl exec -n vault vault-0 -- vault operator unseal $$key; \
	done

vault-configure: ## Apply Vault policies and Kubernetes auth
	kubectl exec -n vault vault-0 -- vault auth enable kubernetes || true
	kubectl apply -f vault/kubernetes-auth-config.yaml
	kubectl exec -n vault vault-0 -- vault policy write aegis-policy /vault/policies/vault-policy.hcl

##@ Testing & Linting

lint: ## Run all linters (terraform fmt, rego fmt, yaml lint)
	cd $(TF_DIR) && terraform fmt -check -recursive
	find policies -name '*.rego' -exec opa fmt --fail {} \;
	yamllint clusters/ cicd/ falco/ vault/ monitoring/

test: ## Run all tests
	$(MAKE) test-opa
	$(MAKE) test-terra

test-opa: ## Run OPA/Conftest policy tests
	conftest test infrastructure/ --policy infrastructure/policies/
	conftest test clusters/ --policy policies/

test-terra: ## Run Terratest (requires Go)
	cd tests/terratest && go test -v -timeout 30m ./...

chaos: ## Run chaos injection test (Falco detection)
	kubectl apply -f tests/chaos/falco-injection.yaml
	@echo "Watch Falco alerts: kubectl logs -n falco -l app=falco -f"

compliance-scan: ## Run mock compliance scan
	bash tests/compliance/mock-scan.sh

##@ Utilities

verify: ## Verify all components are healthy
	@echo "=== Nodes ===" && kubectl get nodes
	@echo "=== ArgoCD ===" && kubectl get pods -n argocd
	@echo "=== Vault ===" && kubectl get pods -n vault
	@echo "=== Falco ===" && kubectl get pods -n falco
	@echo "=== Gatekeeper ===" && kubectl get pods -n gatekeeper-system
	@echo "=== Kyverno ===" && kubectl get pods -n kyverno
	@echo "=== Istio ===" && kubectl get pods -n istio-system
	@echo "=== Monitoring ===" && kubectl get pods -n monitoring

clean: ## Remove generated files
	rm -f $(TF_DIR)/tfplan
	rm -f vault/init-keys.json

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
	  /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
