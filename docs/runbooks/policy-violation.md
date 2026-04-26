# Runbook — Gatekeeper / Kyverno Policy Violation

## Alert: `GatekeeperViolationDetected` / `KyvernoPolicyFailure`

---

## 1. Identify the Violation

```bash
# List all Gatekeeper violations
kubectl get constraints -o json | jq '
  .items[] | {
    constraint: .metadata.name,
    violations: .status.totalViolations,
    details: .status.violations
  } | select(.violations > 0)'

# Kyverno policy reports
kubectl get policyreport -A
kubectl get clusterpolicyreport
```

---

## 2. Common Violations & Fixes

### `deny-latest-tag` — Image uses `:latest`

```bash
# Find offending resource
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].image | endswith(":latest")) | {ns: .metadata.namespace, pod: .metadata.name}'

# Fix: update deployment to use a pinned tag
kubectl set image deployment/<name> <container>=<image>:<tag> -n <namespace>
```

### `deny-privileged-containers` — Privileged container

```bash
# Patch the deployment
kubectl patch deployment <name> -n <namespace> --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/privileged", "value": false},
  {"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/allowPrivilegeEscalation", "value": false}
]'
```

### `require-security-context` — Missing securityContext

```yaml
# Add to container spec:
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

### `require-workload-labels` — Missing required labels

```bash
kubectl label deployment <name> -n <namespace> \
  app=<name> version=<ver> environment=production owner=<team>
```

---

## 3. Audit Mode vs Enforce Mode

Gatekeeper constraints can be switched to `warn` during rollout:

```bash
kubectl patch constraint deny-privileged-containers \
  --type=merge -p '{"spec":{"enforcementAction":"warn"}}'
```

**Do not leave in warn mode** — revert to `deny` after the violation is fixed.

---

## 4. Policy Exemptions (use sparingly)

If a workload legitimately needs an exemption (e.g., Falco needs privileged access):

```yaml
# In the Constraint spec, add to excludedNamespaces:
spec:
  match:
    excludedNamespaces:
      - falco
```

All exemptions must be reviewed and approved — open a PR with justification.

---

## 5. Verify Fix

```bash
# Re-check violations after fix
kubectl get constraint deny-privileged-containers -o json | jq '.status.totalViolations'

# Force Gatekeeper audit re-run
kubectl annotate --overwrite constraint deny-privileged-containers \
  "gatekeeper.sh/force-audit=$(date +%s)"
```
