"""Farmer League collector.

Récupère les données Ligue 1 (clubs, classement, stats joueurs) depuis API-Football,
les écrit dans PostgreSQL et expose ses propres métriques à Prometheus sur :8000.
"""
import logging
import os
import sys
import time

import psycopg
import requests
from prometheus_client import Counter, Gauge, start_http_server

API_URL = "https://v3.football.api-sports.io"
LIGUE1_ID = 61

API_KEY = os.environ.get("API_FOOTBALL_KEY", "")
DATABASE_URL = os.environ["DATABASE_URL"]
SEASONS = [int(s) for s in os.environ.get("SEASONS", "2024").split(",") if s.strip()]
INTERVAL_HOURS = float(os.environ.get("INTERVAL_HOURS", "24"))
REQUEST_DELAY = float(os.environ.get("REQUEST_DELAY_SECONDS", "7"))
# Valeur max du paramètre "page" autorisée par le plan API-Football (3 en gratuit)
MAX_PAGES = int(os.environ.get("MAX_PAGES", "3"))

log = logging.getLogger("collector")

API_REQUESTS = Counter("farmer_api_requests_total", "Appels à API-Football", ["endpoint", "status"])
API_QUOTA_REMAINING = Gauge("farmer_api_quota_remaining", "Requêtes restantes aujourd'hui sur API-Football")
ROWS_UPSERTED = Counter("farmer_rows_upserted_total", "Lignes insérées/mises à jour", ["table"])
INGEST_ERRORS = Counter("farmer_ingest_errors_total", "Erreurs pendant une collecte", ["stage"])
LAST_SUCCESS = Gauge("farmer_last_success_timestamp_seconds", "Fin de la dernière collecte réussie", ["season"])
INGEST_DURATION = Gauge("farmer_ingest_duration_seconds", "Durée de la dernière collecte", ["season"])


class ApiError(Exception):
    pass


def api_get(endpoint, **params):
    resp = requests.get(
        f"{API_URL}/{endpoint}",
        headers={"x-apisports-key": API_KEY},
        params=params,
        timeout=30,
    )
    API_REQUESTS.labels(endpoint, str(resp.status_code)).inc()
    remaining = resp.headers.get("x-ratelimit-requests-remaining")
    if remaining is not None:
        API_QUOTA_REMAINING.set(int(remaining))
    resp.raise_for_status()
    body = resp.json()
    # API-Football renvoie HTTP 200 même en cas d'erreur métier (clé, plan, quota...)
    if body.get("errors"):
        raise ApiError(f"{endpoint} {params}: {body['errors']}")
    time.sleep(REQUEST_DELAY)
    return body


def upsert_teams(cur, season):
    rows = []
    for item in api_get("teams", league=LIGUE1_ID, season=season)["response"]:
        team, venue = item["team"], item.get("venue") or {}
        rows.append((team["id"], team["name"], team.get("code"), team.get("founded"), team.get("logo"),
                     venue.get("name"), venue.get("city"), venue.get("capacity")))
    cur.executemany(
        """
        INSERT INTO teams (id, name, code, founded, logo, venue_name, venue_city, venue_capacity)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name, code = EXCLUDED.code, founded = EXCLUDED.founded, logo = EXCLUDED.logo,
            venue_name = EXCLUDED.venue_name, venue_city = EXCLUDED.venue_city,
            venue_capacity = EXCLUDED.venue_capacity, updated_at = now()
        """,
        rows,
    )
    ROWS_UPSERTED.labels("teams").inc(len(rows))
    return len(rows)


def upsert_standings(cur, season):
    response = api_get("standings", league=LIGUE1_ID, season=season)["response"]
    if not response:
        return 0
    rows = []
    for s in response[0]["league"]["standings"][0]:
        played = s["all"]
        rows.append((season, s["team"]["id"], s["rank"], s["points"], played["played"], played["win"],
                     played["draw"], played["lose"], played["goals"]["for"], played["goals"]["against"],
                     s["goalsDiff"], s.get("form")))
    cur.executemany(
        """
        INSERT INTO standings (season, team_id, rank, points, played, win, draw, lose,
                               goals_for, goals_against, goals_diff, form)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (season, team_id) DO UPDATE SET
            rank = EXCLUDED.rank, points = EXCLUDED.points, played = EXCLUDED.played,
            win = EXCLUDED.win, draw = EXCLUDED.draw, lose = EXCLUDED.lose,
            goals_for = EXCLUDED.goals_for, goals_against = EXCLUDED.goals_against,
            goals_diff = EXCLUDED.goals_diff, form = EXCLUDED.form, updated_at = now()
        """,
        rows,
    )
    ROWS_UPSERTED.labels("standings").inc(len(rows))
    return len(rows)


PLAYER_SQL = """
    INSERT INTO players (id, name, firstname, lastname, birth_date, nationality, height, weight, photo)
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name, firstname = EXCLUDED.firstname, lastname = EXCLUDED.lastname,
        birth_date = EXCLUDED.birth_date, nationality = EXCLUDED.nationality, height = EXCLUDED.height,
        weight = EXCLUDED.weight, photo = EXCLUDED.photo, updated_at = now()
"""

STATS_COLUMNS = [
    "position", "shirt_number", "captain", "rating", "appearances", "lineups", "minutes",
    "sub_in", "sub_out", "bench", "goals", "assists", "goals_conceded", "saves",
    "shots_total", "shots_on", "passes_total", "passes_key", "passes_accuracy",
    "tackles_total", "blocks", "interceptions", "duels_total", "duels_won",
    "dribbles_attempts", "dribbles_success", "dribbled_past", "fouls_drawn", "fouls_committed",
    "yellow_cards", "yellowred_cards", "red_cards", "penalty_won", "penalty_committed",
    "penalty_scored", "penalty_missed", "penalty_saved",
]

STATS_SQL = f"""
    INSERT INTO player_season_stats (player_id, team_id, season, {", ".join(STATS_COLUMNS)})
    VALUES (%s, %s, %s, {", ".join(["%s"] * len(STATS_COLUMNS))})
    ON CONFLICT (player_id, team_id, season) DO UPDATE SET
        {", ".join(f"{c} = EXCLUDED.{c}" for c in STATS_COLUMNS)}, updated_at = now()
"""


def stats_row(player_id, season, st):
    g, sub, goals, pen = st["games"], st["substitutes"], st["goals"], st["penalty"]
    return (
        player_id, st["team"]["id"], season,
        g.get("position"), g.get("number"), g.get("captain"),
        float(g["rating"]) if g.get("rating") else None,
        g.get("appearences"), g.get("lineups"), g.get("minutes"),  # sic : "appearences" côté API
        sub.get("in"), sub.get("out"), sub.get("bench"),
        goals.get("total"), goals.get("assists"), goals.get("conceded"), goals.get("saves"),
        st["shots"].get("total"), st["shots"].get("on"),
        st["passes"].get("total"), st["passes"].get("key"), st["passes"].get("accuracy"),
        st["tackles"].get("total"), st["tackles"].get("blocks"), st["tackles"].get("interceptions"),
        st["duels"].get("total"), st["duels"].get("won"),
        st["dribbles"].get("attempts"), st["dribbles"].get("success"), st["dribbles"].get("past"),
        st["fouls"].get("drawn"), st["fouls"].get("committed"),
        st["cards"].get("yellow"), st["cards"].get("yellowred"), st["cards"].get("red"),
        pen.get("won"), pen.get("commited"), pen.get("scored"), pen.get("missed"), pen.get("saved"),  # sic
    )


def upsert_players(cur, season):
    known_teams = {r[0] for r in cur.execute("SELECT id FROM teams")}
    # Les clubs de la saison viennent du classement ; à défaut, tous les clubs connus
    season_teams = [r[0] for r in cur.execute("SELECT team_id FROM standings WHERE season = %s", (season,))]
    n_players, n_stats = 0, 0
    # Plan gratuit : page <= 3, donc on pagine club par club plutôt que sur toute la ligue
    for team_id in season_teams or sorted(known_teams):
        p, s = upsert_team_players(cur, season, team_id, known_teams)
        cur.connection.commit()
        n_players += p
        n_stats += s
    return n_players, n_stats


def upsert_team_players(cur, season, team_id, known_teams):
    page, total_pages, n_players, n_stats = 1, 1, 0, 0
    while page <= total_pages:
        body = api_get("players", league=LIGUE1_ID, team=team_id, season=season, page=page)
        total_pages = body["paging"]["total"]
        if total_pages > MAX_PAGES:
            log.warning("season %s team %s: %s pages, limité à %s par le plan", season, team_id, total_pages, MAX_PAGES)
            total_pages = MAX_PAGES
        players, stats = [], []
        for item in body["response"]:
            p = item["player"]
            players.append((p["id"], p["name"], p.get("firstname"), p.get("lastname"),
                            (p.get("birth") or {}).get("date"), p.get("nationality"),
                            p.get("height"), p.get("weight"), p.get("photo")))
            for st in item["statistics"]:
                # On ne garde que les lignes Ligue 1 de clubs connus (pas de coupe, pas de prêt hors L1)
                if st["league"]["id"] == LIGUE1_ID and st["team"]["id"] in known_teams:
                    stats.append(stats_row(p["id"], season, st))
        cur.executemany(PLAYER_SQL, players)
        cur.executemany(STATS_SQL, stats)
        ROWS_UPSERTED.labels("players").inc(len(players))
        ROWS_UPSERTED.labels("player_season_stats").inc(len(stats))
        n_players += len(players)
        n_stats += len(stats)
        log.info("season %s team %s: page %s/%s", season, team_id, page, total_pages)
        page += 1
    return n_players, n_stats


def collect_season(season):
    start = time.time()
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        for stage, fn in (("teams", upsert_teams), ("standings", upsert_standings), ("players", upsert_players)):
            try:
                result = fn(cur, season)
                conn.commit()
                log.info("season %s: %s -> %s", season, stage, result)
            except Exception:
                conn.rollback()
                INGEST_ERRORS.labels(stage).inc()
                raise
    INGEST_DURATION.labels(str(season)).set(time.time() - start)
    LAST_SUCCESS.labels(str(season)).set(time.time())


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    start_http_server(8000)
    log.info("metrics on :8000, seasons=%s, interval=%sh", SEASONS, INTERVAL_HOURS)
    if not API_KEY:
        log.error("API_FOOTBALL_KEY absent : renseigne-le dans .env puis relance le collecteur")
        INGEST_ERRORS.labels("config").inc()
    while True:
        if API_KEY:
            for season in SEASONS:
                try:
                    collect_season(season)
                except Exception as exc:
                    log.error("season %s: collecte échouée: %s", season, exc)
        time.sleep(INTERVAL_HOURS * 3600)


if __name__ == "__main__":
    sys.exit(main())
