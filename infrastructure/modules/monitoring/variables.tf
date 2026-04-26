variable "cluster_name"       { type = string }
variable "grafana_admin_pass" { type = string; sensitive = true }
variable "alertmanager_slack" { type = string; sensitive = true; default = "" }
