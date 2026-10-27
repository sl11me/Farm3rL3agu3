# Les scripts de db/init ne s'exécutent qu'à la création du volume (comme en docker compose)
resource "kubernetes_config_map_v1" "db_init" {
  metadata {
    name      = "db-init"
    namespace = local.ns
  }

  data = {
    for f in fileset("${local.repo_root}/db/init", "*") : f => file("${local.repo_root}/db/init/${f}")
  }
}

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = local.ns
  }

  spec {
    selector = { app = "postgres" }

    port {
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_stateful_set_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = local.ns
  }

  spec {
    service_name = kubernetes_service_v1.postgres.metadata[0].name
    replicas     = 1

    selector {
      match_labels = { app = "postgres" }
    }

    template {
      metadata {
        labels = { app = "postgres" }
      }

      spec {
        enable_service_links = false

        container {
          name  = "postgres"
          image = var.postgres_image

          port {
            container_port = 5432
          }

          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }
          env {
            name  = "POSTGRES_USER"
            value = var.postgres_user
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.secret
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "GRAFANA_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.secret
                key  = "GRAFANA_DB_PASSWORD"
              }
            }
          }
          # Sous-dossier : un volume fraîchement monté peut contenir lost+found
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          # Via TCP : échoue tant que les scripts d'init tournent (serveur temporaire sur socket Unix)
          readiness_probe {
            exec {
              command = ["pg_isready", "-h", "127.0.0.1", "-U", var.postgres_user, "-d", var.postgres_db]
            }
            period_seconds = 5
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
          volume_mount {
            name       = "init"
            mount_path = "/docker-entrypoint-initdb.d"
            read_only  = true
          }
        }

        volume {
          name = "init"
          config_map {
            name         = kubernetes_config_map_v1.db_init.metadata[0].name
            default_mode = "0555"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.storage_class_name

        resources {
          requests = { storage = var.postgres_storage }
        }
      }
    }
  }
}
