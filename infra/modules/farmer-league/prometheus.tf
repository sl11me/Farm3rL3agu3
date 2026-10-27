resource "kubernetes_config_map_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = local.ns
  }

  data = {
    "prometheus.yml" = file("${local.repo_root}/prometheus/prometheus.yml")
  }
}

resource "kubernetes_persistent_volume_claim_v1" "prometheus" {
  metadata {
    name      = "prometheus-data"
    namespace = local.ns
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = { storage = var.prometheus_storage }
    }
  }

  # Les StorageClass en WaitForFirstConsumer ne lient le volume qu'au démarrage du pod
  wait_until_bound = false
}

resource "kubernetes_service_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = local.ns
  }

  spec {
    type     = var.expose_node_ports ? "NodePort" : "ClusterIP"
    selector = { app = "prometheus" }

    port {
      port        = 9090
      target_port = 9090
      node_port   = var.expose_node_ports ? 30090 : null
    }
  }
}

resource "kubernetes_deployment_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = local.ns
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "prometheus" }
    }

    template {
      metadata {
        labels = { app = "prometheus" }
        # Redémarre le pod quand la config change
        annotations = {
          "checksum/config" = sha1(kubernetes_config_map_v1.prometheus.data["prometheus.yml"])
        }
      }

      spec {
        enable_service_links = false

        security_context {
          run_as_user     = 65534
          run_as_non_root = true
          fs_group        = 65534
        }

        container {
          name  = "prometheus"
          image = var.prometheus_image
          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--storage.tsdb.retention.time=${var.prometheus_retention}",
          ]

          port {
            container_port = 9090
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9090
            }
            period_seconds = 10
          }

          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { memory = "512Mi" }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/prometheus"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.prometheus.metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.prometheus.metadata[0].name
          }
        }
      }
    }
  }
}
