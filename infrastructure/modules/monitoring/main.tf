resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "55.5.0"
  namespace        = "monitoring"
  create_namespace = true
  atomic           = true
  timeout          = 600

  set { name = "grafana.adminPassword"; value = var.grafana_admin_pass }
  set { name = "grafana.persistence.enabled"; value = "true" }
  set { name = "grafana.persistence.size"; value = "10Gi" }
  set { name = "prometheus.prometheusSpec.retention"; value = "30d" }
  set { name = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"; value = "50Gi" }
  set { name = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage"; value = "10Gi" }

  values = [
    templatefile("${path.module}/alertmanager-values.yaml.tpl", {
      slack_webhook = var.alertmanager_slack
    })
  ]
}

resource "helm_release" "loki_stack" {
  name             = "loki-stack"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  version          = "2.10.1"
  namespace        = "monitoring"
  create_namespace = false
  atomic           = true

  set { name = "loki.persistence.enabled"; value = "true" }
  set { name = "loki.persistence.size"; value = "20Gi" }
  set { name = "promtail.enabled"; value = "true" }
  set { name = "grafana.enabled"; value = "false" }  # use kube-prometheus-stack's Grafana

  depends_on = [helm_release.kube_prometheus_stack]
}
