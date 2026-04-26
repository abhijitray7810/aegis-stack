#!/usr/bin/env bash
# falco-alert-handler.sh — routes Falco events, triggers quarantine on CRITICAL
set -euo pipefail

PORT="${PORT:-8080}"
LOG_FILE="${LOG_FILE:-/var/log/falco-alerts.log}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
QUARANTINE_SCRIPT="$(dirname "$0")/quarantine-pod.sh"

log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$LOG_FILE"; }

route_event() {
  local payload="$1"
  local priority rule namespace pod
  priority=$(echo "$payload"  | jq -r '.priority // "unknown"')
  rule=$(echo "$payload"      | jq -r '.rule     // "unknown"')
  namespace=$(echo "$payload" | jq -r '.output_fields["k8s.ns.name"]  // "unknown"')
  pod=$(echo "$payload"       | jq -r '.output_fields["k8s.pod.name"] // "unknown"')

  log "EVENT priority=$priority rule='$rule' ns=$namespace pod=$pod"

  if [[ "$priority" == "CRITICAL" ]]; then
    log "AUTO-QUARANTINE: $namespace/$pod"
    [[ -x "$QUARANTINE_SCRIPT" ]] && "$QUARANTINE_SCRIPT" "$namespace" "$pod" "$rule" || true

    if [[ -n "$SLACK_WEBHOOK" ]]; then
      curl -s -X POST "$SLACK_WEBHOOK" \
        -H 'Content-type: application/json' \
        -d "{\"text\":\":rotating_light: *CRITICAL* rule=\`$rule\` pod=\`$namespace/$pod\` — quarantine initiated\"}" || true
    fi
  fi
}

log "Falco alert handler started on port $PORT"
while true; do
  PAYLOAD=$(echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" \
    | nc -l -p "$PORT" -q1 | sed -n '/^\s*{/,/^\s*}/p' | head -100)
  [[ -n "$PAYLOAD" ]] && route_event "$PAYLOAD" &
done
