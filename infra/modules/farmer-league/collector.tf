resource "kubernetes_service_v1" "collector" {
  metadata {
    name      = "collector"
    namespace = local.ns
  }

  spec {
    selector = { app = "collector" }

    port {
      name        = "metrics"
      port        = 8000
      target_port = 8000
    }
  }
}

resource "kubernetes_deployment_v1" "collector" {
  metadata {
    name      = "collector"
    namespace = local.ns
  }

  spec {
    replicas = var.collector_replicas

    # Jamais deux collecteurs en parallèle : le quota API est partagé
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "collector" }
    }

    template {
      metadata {
        labels = { app = "collector" }
      }

      spec {
        enable_service_links = false

        # Équivalent du depends_on: service_healthy de docker compose : sans base,
        # la collecte échouerait puis le collecteur dormirait INTERVAL_HOURS
        init_container {
          name    = "wait-postgres"
          image   = var.postgres_image
          command = ["sh", "-c", "until pg_isready -h postgres -U ${var.postgres_user} -d ${var.postgres_db}; do sleep 2; done"]
        }

        container {
          name              = "collector"
          image             = var.collector_image
          image_pull_policy = "IfNotPresent"

          port {
            name           = "metrics"
            container_port = 8000
          }

          env {
            name  = "SEASONS"
            value = var.seasons
          }
          env {
            name  = "INTERVAL_HOURS"
            value = tostring(var.interval_hours)
          }
          env {
            name  = "REQUEST_DELAY_SECONDS"
            value = tostring(var.request_delay_seconds)
          }
          env {
            name  = "MAX_PAGES"
            value = tostring(var.max_pages)
          }
          env {
            name = "API_FOOTBALL_KEY"
            value_from {
              secret_key_ref {
                name = local.secret
                key  = "API_FOOTBALL_KEY"
              }
            }
          }
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = local.secret
                key  = "DATABASE_URL"
              }
            }
          }

          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { memory = "256Mi" }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_stateful_set_v1.postgres]
}
