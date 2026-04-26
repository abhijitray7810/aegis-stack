# 🛡️ Aegis Stack

**Production-grade Kubernetes security platform** for zero-trust, policy-driven, continuously monitored EKS clusters.

## What's Inside

| Layer | Tools |
|---|---|
| Infrastructure | Terraform + EKS + VPC |
| Policy Enforcement | OPA Gatekeeper + Kyverno |
| Runtime Security | Falco + Falcosidekick |
| Secret Management | HashiCorp Vault |
| Service Mesh | Istio (mTLS, AuthorizationPolicies) |
| CI/CD | Tekton Pipelines (Trivy + Syft + Cosign + Conftest) |
| Observability | Prometheus + Grafana + Loki |
| GitOps | ArgoCD |
| Certificates | cert-manager (Let's Encrypt) |

## Quick Start

```bash
# 1. Bootstrap infrastructure
cp infrastructure/terraform.tfvars.example infrastructure/terraform.tfvars
# Edit terraform.tfvars with your values
make infra-init
make infra-apply

# 2. Bootstrap cluster
make cluster-bootstrap

# 3. Deploy security stack
make security-deploy

# 4. Verify
make verify
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full system design.

## Security Posture

- **No privileged containers** enforced by Gatekeeper + Kyverno
- **No `latest` image tags** — all images must be pinned and signed (Cosign)
- **mTLS everywhere** via Istio service mesh
- **Secrets** never in Git — Vault + Kubernetes Auth
- **Runtime anomaly detection** via Falco with automated pod quarantine
- **SBOM generation** on every build (Syft), verified on schedule
- **Trivy scanning** in CI — critical/high CVEs block the pipeline

## License

MIT
