output "grafana_url" {
  value = "http://localhost:${var.grafana_port}"
}

output "prometheus_url" {
  value = "http://localhost:${var.prometheus_port}"
}

output "kubeconfig" {
  description = "export KUBECONFIG=<valeur> pour utiliser kubectl sur ce cluster"
  value       = kind_cluster.this.kubeconfig_path
}
