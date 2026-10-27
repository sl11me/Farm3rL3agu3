# --- Général ---
variable "namespace" {
  description = "Namespace Kubernetes de l'application"
  type        = string
  default     = "farmer-league"
}

variable "storage_class_name" {
  description = "StorageClass des volumes (null = classe par défaut du cluster)"
  type        = string
  default     = null
}

variable "expose_node_ports" {
  description = "Expose Grafana (30000) et Prometheus (30090) en NodePort"
  type        = bool
  default     = true
}

# --- Images ---
variable "collector_image" {
  description = "Image du collecteur (construite depuis collector/)"
  type        = string
}

variable "postgres_image" {
  type    = string
  default = "postgres:17-alpine"
}

variable "prometheus_image" {
  type    = string
  default = "prom/prometheus:v3.15.0"
}

variable "grafana_image" {
  type    = string
  default = "grafana/grafana:13.2.3"
}

# --- PostgreSQL ---
variable "postgres_db" {
  type    = string
  default = "farmerleague"
}

variable "postgres_user" {
  type    = string
  default = "farmer"
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "grafana_db_password" {
  description = "Mot de passe de l'utilisateur lecture seule grafana_reader"
  type        = string
  sensitive   = true
}

variable "postgres_storage" {
  type    = string
  default = "5Gi"
}

# --- Collecteur ---
variable "api_football_key" {
  type      = string
  sensitive = true
}

variable "seasons" {
  description = "Saisons à collecter, séparées par des virgules (2023 = saison 2023/24)"
  type        = string
  default     = "2023"
}

variable "interval_hours" {
  type    = number
  default = 24
}

variable "request_delay_seconds" {
  type    = number
  default = 7
}

variable "max_pages" {
  description = "Valeur max du paramètre page autorisée par le plan API-Football"
  type        = number
  default     = 3
}

variable "collector_replicas" {
  description = "0 pour suspendre la collecte (ex. pendant une restauration de données)"
  type        = number
  default     = 1
}

# --- Prometheus / Grafana ---
variable "prometheus_storage" {
  type    = string
  default = "2Gi"
}

variable "prometheus_retention" {
  type    = string
  default = "90d"
}

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "grafana_storage" {
  type    = string
  default = "1Gi"
}
