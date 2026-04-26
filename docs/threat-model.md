# Aegis Stack — Threat Model

## Assets

| Asset | Classification | Protection |
|---|---|---|
| Application secrets | Critical | Vault KV + dynamic creds |
| Container images | High | Cosign signatures + Trivy scans |
| Kubernetes API | Critical | Private endpoint + RBAC + audit logs |
| Cluster nodes | High | IMDSv2 + SSM + encrypted EBS |
| Network traffic | High | Istio mTLS (TLS 1.3) |
| Audit / security logs | High | Loki (tamper-evident) + CloudWatch |

## Threat Actors

1. **External attacker** — no direct cluster access; must compromise a workload first
2. **Compromised workload** — most common pivot point; Falco + NetworkPolicy limits blast radius
3. **Malicious image** — supply chain attack; Cosign + Trivy + Gatekeeper blocks unsigned/vulnerable images
4. **Insider threat** — RBAC + Vault audit logs + Falco k8s-audit rules detect unusual API access
5. **Dependency compromise** — SBOM + Trivy nightly scans surface vulnerable libraries

## Attack Surface & Controls

### Container Escape
- **Threat**: privileged container, hostPath mount, kernel exploit
- **Controls**: Gatekeeper + Kyverno block privileged/hostPath; Falco detects exploit patterns; seccomp RuntimeDefault

### Secret Exfiltration
- **Threat**: attacker reads Kubernetes Secrets or environment variables
- **Controls**: Vault Agent (secrets on tmpfs); Falco k8s-audit rule fires on Secret API reads; no secrets in Git

### Lateral Movement
- **Threat**: compromised pod accesses other services
- **Controls**: Istio default-deny AuthorizationPolicies; NetworkPolicies as backup; Falco detects unexpected outbound

### Supply Chain
- **Threat**: malicious dependency or image injected
- **Controls**: Cosign keyless signing + verify on deploy; Trivy in CI; Kyverno enforces digest pinning in prod

### Privilege Escalation
- **Threat**: container process gains root or extra capabilities
- **Controls**: Kyverno blocks missing securityContext; Gatekeeper denies allowPrivilegeEscalation; Falco detects uid=0

## Residual Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Zero-day kernel exploit | Low | Critical | Falco eBPF + node auto-patching |
| Falco bypass via kernel bug | Very Low | High | Gatekeeper + NetworkPolicy as defence-in-depth |
| Vault unseal key compromise | Very Low | Critical | KMS auto-unseal; 5-of-3 threshold; HSM option available |
| CI secret exfiltration | Low | High | OIDC keyless signing; GitHub secret scanning; branch protection |
