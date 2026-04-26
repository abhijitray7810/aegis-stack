# ============================================================
# Aegis Stack — Vault Policy
# ============================================================

# ── Application secrets (read-only) ───────────────────────────────────────────
path "secret/data/aegis/+/config" {
  capabilities = ["read"]
}

path "secret/data/aegis/+/credentials" {
  capabilities = ["read"]
}

# ── Database credentials via dynamic secrets ──────────────────────────────────
path "database/creds/aegis-readonly" {
  capabilities = ["read"]
}

path "database/creds/aegis-readwrite" {
  capabilities = ["read"]
}

# ── PKI: issue certificates for internal services ────────────────────────────
path "pki_int/issue/aegis-internal" {
  capabilities = ["create", "update"]
}

path "pki/cert/ca" {
  capabilities = ["read"]
}

# ── Kubernetes auth: allow self-lookup ────────────────────────────────────────
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# ── Deny everything else ──────────────────────────────────────────────────────
path "*" {
  capabilities = ["deny"]
}
