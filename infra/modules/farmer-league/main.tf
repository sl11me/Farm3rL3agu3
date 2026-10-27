# Les configs (schéma SQL, Prometheus, Grafana) sont lues depuis le repo :
# une seule source de vérité pour docker compose et Kubernetes.
locals {
  repo_root = "${path.module}/../../.."
  ns        = kubernetes_namespace_v1.this.metadata[0].name
  secret    = kubernetes_secret_v1.app.metadata[0].name
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "app" {
  metadata {
    name      = "farmer-league"
    namespace = local.ns
  }

  data = {
    POSTGRES_PASSWORD      = var.postgres_password
    GRAFANA_DB_PASSWORD    = var.grafana_db_password
    GRAFANA_ADMIN_PASSWORD = var.grafana_admin_password
    API_FOOTBALL_KEY       = var.api_football_key
    DATABASE_URL           = "postgresql://${var.postgres_user}:${urlencode(var.postgres_password)}@postgres:5432/${var.postgres_db}"
  }
}
