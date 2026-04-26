# Runbook — Falco CRITICAL Alert

## Alert: `FalcoCriticalEventFired`

### Severity: CRITICAL

---

## 1. Immediate Triage (< 2 minutes)

```bash
# Identify the offending pod
kubectl logs -n falco -l app=falco --since=5m | jq 'select(.priority=="CRITICAL")'

# Check if auto-quarantine fired
kubectl get networkpolicies -A -l aegis.io/quarantine=true
kubectl get pods -A -l aegis.io/quarantined=true
```

Check Grafana → **Aegis — Falco Security Events** dashboard for context.

---

## 2. Assess Blast Radius

```bash
# What is the pod doing?
NAMESPACE=<ns>
POD=<pod>

kubectl describe pod $POD -n $NAMESPACE
kubectl logs $POD -n $NAMESPACE --all-containers --previous 2>/dev/null || true
kubectl get events -n $NAMESPACE --field-selector involvedObject.name=$POD

# What does the pod have access to?
kubectl get rolebindings,clusterrolebindings -A \
  -o json | jq --arg sa "system:serviceaccount:$NAMESPACE:$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.serviceAccountName}')" \
  '[.items[] | select(.subjects[]?.name == $sa)]'
```

---

## 3. Contain

If auto-quarantine did **not** fire:

```bash
# Manual quarantine
bash cicd/scripts/quarantine-pod.sh $NAMESPACE $POD "manual-triage-$(date +%s)"
```

If the deployment is actively serving traffic:

```bash
# Scale down deployment (stops new pods spawning)
kubectl scale deployment <deployment-name> -n $NAMESPACE --replicas=0
```

---

## 4. Investigate

```bash
# Check evidence directory on the node (if quarantine ran)
ls /tmp/aegis-evidence/$NAMESPACE/$POD/

# Inspect network connections the pod made (if still running)
kubectl exec $POD -n $NAMESPACE -- ss -tnp 2>/dev/null || true

# Check for lateral movement — any other pods affected?
kubectl get pods -A -l aegis.io/quarantined=true
```

Correlate with Loki logs in Grafana:
```logql
{app="falco"} | json | namespace="<ns>" | pod="<pod>"
```

---

## 5. Remediate

| Rule Fired | Likely Cause | Action |
|---|---|---|
| Shell Spawned in Container | RCE / debug session left open | Patch app; remove debug tooling |
| Privileged Container Started | Misconfigured deployment | Fix securityContext; check Gatekeeper policy |
| Crypto Miner Detected | Compromised image/dependency | Rotate all secrets; rebuild from clean base |
| Write to Sensitive File | Container escape attempt | Immediate IR; escalate |

---

## 6. Post-Incident

1. Remove quarantine NetworkPolicy: `kubectl delete networkpolicy quarantine-$POD -n $NAMESPACE`
2. File incident report with timeline and affected scope
3. Update Falco rules if false positive
4. Review Gatekeeper/Kyverno policies for gaps that allowed the workload
5. Rotate any secrets the pod had access to via Vault

---

## Escalation

- **Severity CRITICAL + data exfiltration suspected**: Page on-call security lead immediately
- **Severity CRITICAL + contained**: Async Slack `#security-critical` + incident ticket within 30 min
