#!/bin/sh
# Utilisateur lecture seule pour Grafana (principe du moindre privilège)
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v pwd="$GRAFANA_DB_PASSWORD" <<'EOSQL'
CREATE ROLE grafana_reader LOGIN PASSWORD :'pwd';
GRANT CONNECT ON DATABASE :"DBNAME" TO grafana_reader;
GRANT USAGE ON SCHEMA public TO grafana_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_reader;
EOSQL
