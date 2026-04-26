#!/usr/bin/env bash
# quarantine-pod.sh — isolates a suspicious pod by applying a deny-all NetworkPolicy
# and optionally deleting it after evidence collection.
#
# Usage: quarantine-pod.sh <namespace> <pod-name> <reason>
set -euo pipefail

NAMESPACE="${1:?Usage: $0 <namespace> <pod-name> <reason>}"
POD_NAME="${2:?}"
REASON="${3:-unknown}"
EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/aegis-evidence}"
DELETE_POD="${DELETE_POD:-true}"
KUBECTL="${KUBECTL:-kubectl}"

log() { echo "[$(date -u +%FT%TZ)] QUARANTINE $*"; }
fatal() { log "ERROR: $*"; exit 1; }

mkdir -p "$EVIDENCE_DIR/$NAMESPACE/$POD_NAME"
EVIDENCE="$EVIDENCE_DIR/$NAMESPACE/$POD_NAME"

log "Starting quarantine for $NAMESPACE/$POD_NAME (reason: $REASON)"

# ── 1. Verify pod exists ──────────────────────────────────────────────────────
$KUBECTL get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null \
  || fatal "Pod $NAMESPACE/$POD_NAME not found"

# ── 2. Collect evidence before any action ────────────────────────────────────
log "Collecting evidence..."
$KUBECTL describe pod "$POD_NAME" -n "$NAMESPACE" > "$EVIDENCE/pod-describe.txt" 2>&1 || true
$KUBECTL logs "$POD_NAME" -n "$NAMESPACE" --all-containers=true \
  > "$EVIDENCE/pod-logs.txt" 2>&1 || true
$KUBECTL get events -n "$NAMESPACE" --field-selector \
  "involvedObject.name=$POD_NAME" > "$EVIDENCE/events.txt" 2>&1 || true
$KUBECTL get pod "$POD_NAME" -n "$NAMESPACE" -o json > "$EVIDENCE/pod.json" 2>&1 || true
echo "$REASON" > "$EVIDENCE/quarantine-reason.txt"
echo "$(date -u +%FT%TZ)" > "$EVIDENCE/quarantine-timestamp.txt"

log "Evidence saved to $EVIDENCE"

# ── 3. Apply deny-all NetworkPolicy to isolate pod ───────────────────────────
log "Applying deny-all NetworkPolicy..."
APP_LABEL=$($KUBECTL get pod "$POD_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.metadata.labels.app}' 2>/dev/null || echo "quarantined")

$KUBECTL apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    aegis.io/quarantine: "true"
    aegis.io/reason: "$(echo "$REASON" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 63)"
spec:
  podSelector:
    matchLabels:
      app: ${APP_LABEL}
  policyTypes:
    - Ingress
    - Egress
EOF
log "NetworkPolicy quarantine-${POD_NAME} applied — all traffic blocked"

# ── 4. Label pod for audit trail ─────────────────────────────────────────────
$KUBECTL label pod "$POD_NAME" -n "$NAMESPACE" \
  "aegis.io/quarantined=true" \
  "aegis.io/quarantine-reason=$(echo "$REASON" | tr ' ' '-' | head -c 63)" \
  --overwrite || true

# ── 5. Optionally delete pod ─────────────────────────────────────────────────
if [[ "$DELETE_POD" == "true" ]]; then
  log "Deleting pod $NAMESPACE/$POD_NAME..."
  $KUBECTL delete pod "$POD_NAME" -n "$NAMESPACE" --grace-period=0 --force 2>/dev/null || true
  log "Pod deleted"
fi

log "Quarantine complete for $NAMESPACE/$POD_NAME"
log "Evidence: $EVIDENCE"
