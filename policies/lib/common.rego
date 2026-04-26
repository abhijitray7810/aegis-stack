package lib.common

import future.keywords.in
import future.keywords.if

# ── Trusted registries ────────────────────────────────────────────────────────
trusted_registries := {
  "602401143452.dkr.ecr.us-east-1.amazonaws.com",
  "123456789.dkr.ecr.us-east-1.amazonaws.com",
  "public.ecr.aws/eks-distro",
  "registry.k8s.io",
  "quay.io/prometheus",
  "grafana",
}

# ── System namespaces exempt from most policies ───────────────────────────────
system_namespaces := {
  "kube-system",
  "kube-public",
  "kube-node-lease",
  "gatekeeper-system",
  "kyverno",
  "falco",
  "cert-manager",
}

# ── Required labels for workload resources ────────────────────────────────────
required_labels := {"app", "version", "environment", "owner"}

# ── Helpers ───────────────────────────────────────────────────────────────────
is_system_namespace(ns) if ns in system_namespaces

image_registry(image) := reg if {
  parts := split(image, "/")
  count(parts) > 1
  reg := parts[0]
}

image_tag(image) := tag if {
  parts := split(image, ":")
  count(parts) == 2
  tag := parts[1]
}

image_tag(image) := "latest" if {
  not contains(image, ":")
}

has_digest(image) if {
  contains(image, "@sha256:")
}

from_trusted_registry(image) if {
  reg := image_registry(image)
  reg in trusted_registries
}
