# Environnement local : cluster kind (Kubernetes dans Docker) sur la machine, 0 $.
locals {
  collector_src = "${path.module}/../../../collector"
  collector_files = sort(concat(
    tolist(fileset(local.collector_src, "*.py")),
    ["Dockerfile", "requirements.txt"],
  ))
  # Tag = hash des sources : un changement du code reconstruit l'image et redéploie le pod
  collector_hash  = substr(sha1(join("", [for f in local.collector_files : filesha1("${local.collector_src}/${f}")])), 0, 12)
  collector_image = "farmer-league-collector:${local.collector_hash}"
}

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true
  # Fichier dédié pour ne pas toucher à ~/.kube/config
  kubeconfig_path = abspath("${path.module}/kubeconfig")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # NodePorts du module -> ports de la machine
      extra_port_mappings {
        container_port = 30000
        host_port      = var.grafana_port
        listen_address = "127.0.0.1"
      }
      extra_port_mappings {
        container_port = 30090
        host_port      = var.prometheus_port
        listen_address = "127.0.0.1"
      }
    }
  }
}

provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

# Pas de registry : l'image est construite localement puis chargée dans le nœud kind
resource "terraform_data" "collector_image" {
  input            = local.collector_image
  triggers_replace = [local.collector_image, kind_cluster.this.id]

  provisioner "local-exec" {
    command = "docker build -t ${local.collector_image} ${local.collector_src} && kind load docker-image ${local.collector_image} --name ${kind_cluster.this.name}"
  }
}

module "farmer_league" {
  source = "../../modules/farmer-league"

  collector_image    = terraform_data.collector_image.output
  collector_replicas = var.collector_replicas

  postgres_db         = var.postgres_db
  postgres_user       = var.postgres_user
  postgres_password   = var.postgres_password
  grafana_db_password = var.grafana_db_password

  api_football_key = var.api_football_key
  seasons          = var.seasons

  grafana_admin_user     = var.grafana_admin_user
  grafana_admin_password = var.grafana_admin_password
}
