#!/usr/bin/env bash
# mock-scan.sh — lightweight compliance check without a full CIS tool.
set -euo pipefail
PASS=0; FAIL=0; WARN=0
NS="${TARGET_NS:-secure-apps}"
pass() { echo "  [PASS] $*"; ((PASS++)) || true; }
fail() { echo "  [FAIL] $*"; ((FAIL++)) || true; }
warn() { echo "  [WARN] $*"; ((WARN++)) || true; }
header() { echo; echo "=== $* ==="; }

header "1. NetworkPolicies"
kubectl get networkpolicies -n "$NS" --no-headers 2>/dev/null | grep -q . \
  && pass "NetworkPolicies exist in $NS" || fail "No NetworkPolicies in $NS"

header "2. Privileged Containers"
PRIV=$(kubectl get pods -n "$NS" -o json 2>/dev/null \
  | jq '[.items[].spec.containers[].securityContext.privileged//false]|map(select(.==true))|length')
[ "$PRIV" -eq 0 ] && pass "No privileged containers in $NS" || fail "$PRIV privileged container(s)"

header "3. runAsNonRoot"
ROOT=$(kubectl get pods -n "$NS" -o json 2>/dev/null \
  | jq '[.items[]|select(.spec.securityContext.runAsNonRoot!=true)]|length')
[ "$ROOT" -eq 0 ] && pass "All pods set runAsNonRoot" || warn "$ROOT pod(s) missing runAsNonRoot"

header "4. Vault Running"
kubectl get pods -n vault --no-headers 2>/dev/null | grep -q Running \
  && pass "Vault pods Running" || fail "Vault not running"

header "5. Gatekeeper Violations"
VIOLS=$(kubectl get constraints -o json 2>/dev/null \
  | jq '[.items[].status.totalViolations//0]|add//0')
[ "$VIOLS" -eq 0 ] && pass "No Gatekeeper violations" || fail "$VIOLS violation(s)"

header "6. Falco Running"
kubectl get pods -n falco --no-headers 2>/dev/null | grep -q Running \
  && pass "Falco Running" || fail "Falco not running"

header "7. Expired Certificates"
EXPIRED=$(kubectl get certificates -A -o json 2>/dev/null \
  | jq '[.items[]|select(.status.conditions[]?|select(.type=="Ready" and .status=="False"))]|length')
[ "$EXPIRED" -eq 0 ] && pass "No expired certs" || fail "$EXPIRED cert(s) not Ready"

echo; echo "=== Summary: PASS=$PASS WARN=$WARN FAIL=$FAIL ==="
[ "$FAIL" -gt 0 ] && echo "Result: FAILED" && exit 1 || echo "Result: PASSED"
