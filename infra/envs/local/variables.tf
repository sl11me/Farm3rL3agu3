variable "cluster_name" {
  type    = string
  default = "farmer-league"
}

# 3001/9091 par défaut pour cohabiter avec la stack docker compose (3000/9090)
variable "grafana_port" {
  type    = number
  default = 3001
}

variable "prometheus_port" {
  type    = number
  default = 9091
}

variable "collector_replicas" {
  type    = number
  default = 1
}

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
  type      = string
  sensitive = true
}

variable "api_football_key" {
  type      = string
  sensitive = true
}

variable "seasons" {
  type    = string
  default = "2023"
}

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}
