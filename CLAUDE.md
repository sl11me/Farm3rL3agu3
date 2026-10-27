# Farm3rL3agu3

Stats Ligue 1 : API-Football → collecteur Python → PostgreSQL → Grafana, avec Prometheus pour superviser le pipeline.
La même stack tourne en docker compose (dev) et sur Kubernetes via Terraform (`infra/`). Voir `README.md` pour l'architecture.

## Commandes

```bash
docker compose up -d --build                 # stack locale (Grafana :3000, Prometheus :9090, collecteur :8000/metrics)
docker compose up -d --build collector       # après une modif de collector/
docker compose logs -f collector
docker compose down -v && docker compose up -d   # réapplique db/init/ — EFFACE les données

cd infra/envs/local && terraform init && terraform apply   # cluster kind + déploiement (Grafana :3001, Prometheus :9091)
terraform apply -var collector_replicas=0                  # suspend la collecte côté k8s
```

Pas de tests automatisés : vérifier une modif du collecteur via ses logs et `/metrics`, une modif SQL ou dashboard dans Grafana.

## Règles

- **Un seul collecteur à la fois** (compose ou k8s) : le quota API-Football gratuit (100 req/jour, 10/min) est partagé.
  Ne pas relancer le collecteur en boucle pour tester, chaque cycle coûte ~35 requêtes par saison.
- Les stats sont relationnelles → PostgreSQL. Prometheus ne sert qu'aux métriques du pipeline (`farmer_*`), jamais aux stats de foot.
- Une seule source de config : `db/init/`, `prometheus/` et `grafana/` sont lus à la fois par compose et par le module Terraform.
  Le module les charge avec `file()`/`fileset()` : modifier ces fichiers, ne jamais recopier leur contenu en dur dans les `.tf`.
- Schéma SQL : `db/init/001_schema.sql` (tables `teams`, `players`, `standings`, `player_season_stats`, vue `v_player_stats`).
  Les scripts `db/init/` ne tournent qu'à la création du volume : une migration sur une base existante se fait à la main avec `psql`.
- Grafana lit la base avec un utilisateur lecture seule (`002_grafana_reader.sh`) ; les dashboards sont versionnés en JSON dans `grafana/dashboards/`.
- Secrets dans `.env` et `infra/envs/*/terraform.tfvars` (ignorés par git). Ne jamais lire ni afficher leurs valeurs ; partir des `.example`.
- `backups/` contient des dumps SQL locaux, ignorés par git.
