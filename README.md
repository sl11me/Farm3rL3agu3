# Farm3rL3agu3

Dashboard complet des statistiques des joueurs et des clubs de **Ligue 1 McDonald's**.

## Architecture

```
API-Football ──► collector (Python) ──► PostgreSQL ──► Grafana (dashboards Ligue 1)
                     │ /metrics
                     ▼
                 Prometheus ─────────────────────────► Grafana (dashboard pipeline)
```

| Service      | Rôle                                                          | URL locale             |
|--------------|---------------------------------------------------------------|------------------------|
| `postgres`   | Stockage des clubs, classements et stats joueurs par saison   | `localhost:5432`       |
| `collector`  | Collecte API-Football, écrit en base, expose ses métriques    | `localhost:8000/metrics` |
| `prometheus` | Supervision du pipeline (quota API, erreurs, fraîcheur)       | `localhost:9090`       |
| `grafana`    | Dashboards (datasources et dashboards provisionnés en code)   | `localhost:3000`       |

**Pourquoi PostgreSQL pour les stats, et pas Prometheus ?** Prometheus est une base de séries
temporelles faite pour des métriques échantillonnées en continu. Des stats de football sont des
données relationnelles (joueur ↔ club ↔ saison ↔ match) qu'on veut filtrer, joindre et classer.
On les stocke donc en SQL, et Prometheus sert à superviser la plateforme elle-même. C'est aussi
ce qui nous permettra de migrer vers **Azure Database for PostgreSQL** plus tard.

## Démarrage

```bash
cp .env.example .env       # puis remplir les mots de passe et API_FOOTBALL_KEY
docker compose up -d --build
```

1. Créer une clé gratuite sur https://dashboard.api-football.com et la mettre dans `API_FOOTBALL_KEY`.
2. Relancer le collecteur : `docker compose up -d collector`, puis suivre `docker compose logs -f collector`.
3. Ouvrir Grafana sur http://localhost:3000 → dossier **Farmer League**.

Le plan gratuit offre 100 requêtes/jour et 10/minute. Une saison complète coûte environ 35 requêtes,
soit 1 pour les clubs, 1 pour le classement et une par page de 20 joueurs. Toutes les saisons ne
sont pas forcément accessibles en gratuit : si les logs montrent une erreur de plan, essayer une
saison plus ancienne dans `SEASONS`.

## Déploiement Kubernetes (Terraform)

La même stack est décrite en Terraform dans `infra/` : un module réutilisable
(`infra/modules/farmer-league`) qui déploie l'application sur n'importe quel cluster Kubernetes,
et un dossier par environnement dans `infra/envs/`. Les configs (schéma SQL, Prometheus, Grafana)
sont lues depuis le repo : docker compose et Kubernetes partagent la même source.

Environnement `local` : cluster [kind](https://kind.sigs.k8s.io) (Kubernetes dans Docker), 0 $.

```bash
cd infra/envs/local
cp terraform.tfvars.example terraform.tfvars   # puis remplir (mêmes valeurs que .env)
terraform init
terraform apply                                 # crée le cluster, construit l'image du collecteur, déploie
export KUBECONFIG=$(terraform output -raw kubeconfig)
kubectl -n farmer-league get pods
```

Grafana : http://localhost:3001, Prometheus : http://localhost:9091 (ports décalés pour cohabiter
avec docker compose). `terraform apply -var collector_replicas=0` suspend la collecte, et
`terraform destroy` supprime le cluster et ses données.

> Un seul collecteur doit tourner à la fois (compose **ou** Kubernetes) : le quota API est partagé.

## Dashboards

- **Ligue 1 - Joueurs & Clubs** : classement, tops (buts, passes D., note, G+A/90, passes clés/90,
  tacles+interceptions/90, dribbles, duels, arrêts) et tableau complet des joueurs. Filtres disponibles :
  saison, club, poste et minutes minimum pour les ratios.
- **Farmer League - Pipeline de données** : état du collecteur, quota API restant, fraîcheur des
  données, erreurs.

## Structure

```
collector/            Collecteur Python (API-Football → PostgreSQL + métriques Prometheus)
db/init/              Schéma SQL, vue d'analyse v_player_stats, utilisateur lecture seule Grafana
prometheus/           Configuration de scrape
grafana/provisioning/ Datasources et provider de dashboards
grafana/dashboards/   Dashboards JSON (versionnés)
infra/modules/        Module Terraform : la stack sur Kubernetes
infra/envs/           Environnements Terraform (local = kind)
```

> Les scripts de `db/init/` ne s'exécutent qu'à la création du volume. Pour réappliquer le schéma :
> `docker compose down -v && docker compose up -d` (⚠️ efface les données).

## Roadmap

- [x] Sprint 0 : stack locale Docker (PostgreSQL, Prometheus, Grafana, collecteur)
- [x] Sprint 1 : stack sur Kubernetes en Terraform (cluster kind local)
- [ ] Environnement cloud 0 $ : Oracle Cloud Always Free (OKE + nœuds ARM) avec le même module
- [ ] Stats par match (`/fixtures/players`) pour les courbes de forme et l'historique
- [ ] Données avancées (xG/xA, actions progressives) via une 2e source
- [ ] Alerting Grafana (collecte en échec, quota épuisé)
- [ ] CI Azure DevOps Pipelines (lint, build image, push vers Azure Container Registry)
- [ ] Infra Azure en IaC (Terraform/Bicep) : Azure Database for PostgreSQL, VM ou Container Apps, Managed Grafana
- [ ] Agents IA : analyse et scouting en langage naturel sur la base
