-- Farmer League : schéma Ligue 1
-- IDs = identifiants API-Football (league 61 = Ligue 1)

CREATE TABLE IF NOT EXISTS teams (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    code            TEXT,
    founded         INTEGER,
    logo            TEXT,
    venue_name      TEXT,
    venue_city      TEXT,
    venue_capacity  INTEGER,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS players (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    firstname       TEXT,
    lastname        TEXT,
    birth_date      DATE,
    nationality     TEXT,
    height          TEXT,
    weight          TEXT,
    photo           TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Classement : une ligne par club et par saison
CREATE TABLE IF NOT EXISTS standings (
    season          INTEGER NOT NULL,
    team_id         INTEGER NOT NULL REFERENCES teams(id),
    rank            INTEGER,
    points          INTEGER,
    played          INTEGER,
    win             INTEGER,
    draw            INTEGER,
    lose            INTEGER,
    goals_for       INTEGER,
    goals_against   INTEGER,
    goals_diff      INTEGER,
    form            TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (season, team_id)
);

-- Stats cumulées d'un joueur pour un club sur une saison (un joueur transféré a 2 lignes)
CREATE TABLE IF NOT EXISTS player_season_stats (
    player_id           INTEGER NOT NULL REFERENCES players(id),
    team_id             INTEGER NOT NULL REFERENCES teams(id),
    season              INTEGER NOT NULL,
    position            TEXT,
    shirt_number        INTEGER,
    captain             BOOLEAN,
    rating              NUMERIC(4,2),
    appearances         INTEGER,
    lineups             INTEGER,
    minutes             INTEGER,
    sub_in              INTEGER,
    sub_out             INTEGER,
    bench               INTEGER,
    goals               INTEGER,
    assists             INTEGER,
    goals_conceded      INTEGER,
    saves               INTEGER,
    shots_total         INTEGER,
    shots_on            INTEGER,
    passes_total        INTEGER,
    passes_key          INTEGER,
    passes_accuracy     INTEGER,
    tackles_total       INTEGER,
    blocks              INTEGER,
    interceptions       INTEGER,
    duels_total         INTEGER,
    duels_won           INTEGER,
    dribbles_attempts   INTEGER,
    dribbles_success    INTEGER,
    dribbled_past       INTEGER,
    fouls_drawn         INTEGER,
    fouls_committed     INTEGER,
    yellow_cards        INTEGER,
    yellowred_cards     INTEGER,
    red_cards           INTEGER,
    penalty_won         INTEGER,
    penalty_committed   INTEGER,
    penalty_scored      INTEGER,
    penalty_missed      INTEGER,
    penalty_saved       INTEGER,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (player_id, team_id, season)
);

CREATE INDEX IF NOT EXISTS idx_pss_season_team ON player_season_stats (season, team_id);

-- Vue d'analyse : stats brutes + ratios "par 90 minutes" et taux de réussite
CREATE OR REPLACE VIEW v_player_stats AS
SELECT
    p.name              AS player,
    p.nationality,
    date_part('year', age(p.birth_date))::int AS age,
    p.photo,
    t.name              AS team,
    t.code              AS team_code,
    s.*,
    round(s.goals   * 90.0 / NULLIF(s.minutes, 0), 2)                         AS goals_p90,
    round(s.assists * 90.0 / NULLIF(s.minutes, 0), 2)                         AS assists_p90,
    round((coalesce(s.goals, 0) + coalesce(s.assists, 0)) * 90.0 / NULLIF(s.minutes, 0), 2) AS ga_p90,
    round(s.shots_total * 90.0 / NULLIF(s.minutes, 0), 2)                     AS shots_p90,
    round(s.passes_key  * 90.0 / NULLIF(s.minutes, 0), 2)                     AS key_passes_p90,
    round((coalesce(s.tackles_total, 0) + coalesce(s.interceptions, 0)) * 90.0 / NULLIF(s.minutes, 0), 2) AS tkl_int_p90,
    round(100.0 * s.shots_on / NULLIF(s.shots_total, 0), 1)                   AS shot_accuracy_pct,
    round(100.0 * s.goals / NULLIF(s.shots_total, 0), 1)                      AS conversion_pct,
    round(100.0 * s.duels_won / NULLIF(s.duels_total, 0), 1)                  AS duels_won_pct,
    round(100.0 * s.dribbles_success / NULLIF(s.dribbles_attempts, 0), 1)     AS dribbles_success_pct
FROM player_season_stats s
JOIN players p ON p.id = s.player_id
JOIN teams   t ON t.id = s.team_id;
