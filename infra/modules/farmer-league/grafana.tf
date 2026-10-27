locals {
  grafana_dir = "${local.repo_root}/grafana"
}

resource "kubernetes_config_map_v1" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = local.ns
  }

  data = {
    "datasources.yml" = file("${local.grafana_dir}/provisioning/datasources/datasources.yml")
  }
}

resource "kubernetes_config_map_v1" "grafana_dashboard_providers" {
  metadata {
    name      = "grafana-dashboard-providers"
    namespace = local.ns
  }

  data = {
    "dashboards.yml" = file("${local.grafana_dir}/provisioning/dashboards/dashboards.yml")
  }
}

resource "kubernetes_config_map_v1" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = local.ns
  }

  data = {
    for f in fileset("${local.grafana_dir}/dashboards", "*.json") : f => file("${local.grafana_dir}/dashboards/${f}")
  }
}

resource "kubernetes_persistent_volume_claim_v1" "grafana" {
  metadata {
    name      = "grafana-data"
    namespace = local.ns
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = { storage = var.grafana_storage }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_service_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = local.ns
  }

  spec {
    type     = var.expose_node_ports ? "NodePort" : "ClusterIP"
    selector = { app = "grafana" }

    port {
      port        = 3000
      target_port = 3000
      node_port   = var.expose_node_ports ? 30000 : null
    }
  }
}

resource "kubernetes_deployment_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = local.ns
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "grafana" }
    }

    template {
      metadata {
        labels = { app = "grafana" }
        annotations = {
          "checksum/config" = sha1(jsonencode([
            kubernetes_config_map_v1.grafana_datasources.data,
            kubernetes_config_map_v1.grafana_dashboard_providers.data,
            kubernetes_config_map_v1.grafana_dashboards.data,
          ]))
        }
      }

      spec {
        enable_service_links = false

        security_context {
          fs_group = 472
        }

        container {
          name  = "grafana"
          image = var.grafana_image

          port {
            container_port = 3000
          }

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = var.grafana_admin_user
          }
          env {
            name = "GF_SECURITY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.secret
                key  = "GRAFANA_ADMIN_PASSWORD"
              }
            }
          }
          env {
            name  = "GF_USERS_DEFAULT_LANGUAGE"
            value = "fr-FR"
          }
          # Variables interpolées dans datasources.yml
          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
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

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            period_seconds = 10
          }

          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { memory = "512Mi" }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/grafana"
          }
          volume_mount {
            name       = "datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
            read_only  = true
          }
          volume_mount {
            name       = "dashboard-providers"
            mount_path = "/etc/grafana/provisioning/dashboards"
            read_only  = true
          }
          volume_mount {
            name       = "dashboards"
            mount_path = "/var/lib/grafana/dashboards"
            read_only  = true
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.grafana.metadata[0].name
          }
        }
        volume {
          name = "datasources"
          config_map {
            name = kubernetes_config_map_v1.grafana_datasources.metadata[0].name
          }
        }
        volume {
          name = "dashboard-providers"
          config_map {
            name = kubernetes_config_map_v1.grafana_dashboard_providers.metadata[0].name
          }
        }
        volume {
          name = "dashboards"
          config_map {
            name = kubernetes_config_map_v1.grafana_dashboards.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_stateful_set_v1.postgres]
}
