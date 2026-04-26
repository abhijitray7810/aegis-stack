# Aegis Stack — Architecture

## Overview

Aegis Stack is a defence-in-depth Kubernetes security platform on AWS EKS.
Every layer enforces controls independently so a bypass of one layer does not compromise the whole system.

## Security Layers

### Layer 1 — Supply Chain (CI/CD)
- **Trivy** scans images for CVEs; CRITICAL/HIGH blocks the pipeline
- **Syft** generates SPDX SBOMs attached to each image as OCI artifact
- **Cosign** signs every image using keyless OIDC (no long-lived keys)
- **Conftest/OPA** validates all Kubernetes manifests and Terraform plans

### Layer 2 — Admission Control
- **OPA Gatekeeper**: no privileged containers, no `latest` tags, required labels, no hostPath
- **Kyverno**: runAsNonRoot, drop ALL capabilities, readOnlyRootFilesystem, digest pinning in secure-apps
- Both operate independently — admission requires passing both

### Layer 3 — Network / Service Mesh
- **Istio** with STRICT mTLS across all namespaces (TLS 1.3 minimum)
- Default-deny AuthorizationPolicies; explicit allow-listing per service pair
- All ingress via `istio-ingressgateway` only

### Layer 4 — Secret Management
- **Vault** HA Raft cluster (3 replicas), AWS KMS auto-unseal, IRSA
- Short-lived tokens (1h TTL) via Kubernetes auth
- Dynamic DB credentials via Vault Database engine
- Vault Agent Injector — secrets written to tmpfs, never to Kubernetes Secrets

### Layer 5 — Runtime Detection & Response
- **Falco** eBPF: detects shell spawns, crypto miners, sensitive file writes, privilege escalation
- **Falcosidekick**: routes alerts to Slack, Alertmanager, Loki
- Automated quarantine on CRITICAL: deny-all NetworkPolicy + evidence collection + pod deletion

### Layer 6 — Observability
- Prometheus + Grafana + Loki + Alertmanager
- Dashboards: Falco Events, Security Posture
- Alert rules for Falco, Gatekeeper, Kyverno, Vault, cert-manager

## Infrastructure

- VPC: 3 AZs, private subnets for nodes
- EKS: private endpoint, KMS envelope encryption, IMDSv2 required
- Node groups: ON_DEMAND system (m5.xlarge), SPOT workload (m5.2xlarge)
- Terraform state: S3 + DynamoDB locking, SSE encryption
