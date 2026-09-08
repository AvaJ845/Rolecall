"""SQLite persistence. One file at data/rolecall.db."""
from __future__ import annotations

import pathlib
import sqlite3
import time

DB_PATH = pathlib.Path(__file__).resolve().parent.parent / "data" / "rolecall.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS postings (
  key                TEXT PRIMARY KEY,       -- company_id|ats|external_id
  company_id         TEXT NOT NULL,
  company_name       TEXT NOT NULL,
  ats                TEXT NOT NULL,
  external_id        TEXT NOT NULL,
  title              TEXT NOT NULL,
  department         TEXT,
  location           TEXT,
  remote             INTEGER,
  url                TEXT NOT NULL,
  role_family        TEXT,
  classify_reason    TEXT,
  first_seen_utc     REAL NOT NULL,
  last_seen_utc      REAL NOT NULL,          -- last time it was present in the ATS feed
  last_verified_utc  REAL,                   -- last successful HTTP liveness check
  http_status        INTEGER,
  verify_flag        TEXT,                   -- NULL = ok, else why the URL check looked wrong
  status             TEXT NOT NULL,          -- live | gone
  gone_utc           REAL
);
CREATE INDEX IF NOT EXISTS idx_status ON postings(status);
CREATE INDEX IF NOT EXISTS idx_verify ON postings(status, last_verified_utc);

CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT, started_utc REAL, finished_utc REAL, note TEXT
);

CREATE TABLE IF NOT EXISTS audit_log (
  ts REAL, posting_key TEXT, machine_status TEXT, human_verdict TEXT, url TEXT
);
"""


def connect():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def now() -> float:
    return time.time()


def upsert_posting(conn, company, row, role_family, reason):
    key = "{}|{}|{}".format(company["id"], company["ats"], row["external_id"])
    ts = now()
    cur = conn.execute("SELECT key, status FROM postings WHERE key = ?", (key,))
    existing = cur.fetchone()
    if existing is None:
        conn.execute(
            """INSERT INTO postings
               (key, company_id, company_name, ats, external_id, title, department,
                location, remote, url, role_family, classify_reason,
                first_seen_utc, last_seen_utc, status)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'live')""",
            (key, company["id"], company["name"], company["ats"], row["external_id"],
             row["title"], row["department"], row["location"],
             None if row["remote"] is None else int(row["remote"]),
             row["url"], role_family, reason, ts, ts),
        )
        return "new"
    conn.execute(
        """UPDATE postings
           SET last_seen_utc = ?, status = 'live', gone_utc = NULL,
               title = ?, department = ?, location = ?, url = ?,
               role_family = ?, classify_reason = ?,
               remote = ?
           WHERE key = ?""",
        (ts, row["title"], row["department"], row["location"], row["url"],
         role_family, reason,
         None if row["remote"] is None else int(row["remote"]),
         key),
    )
    return "seen"


def mark_gone_for_company(conn, company_id: str, seen_keys) -> int:
    """Anything for this company that is still 'live' but was not seen this run is gone."""
    ts = now()
    rows = conn.execute(
        "SELECT key FROM postings WHERE company_id = ? AND status = 'live'",
        (company_id,),
    ).fetchall()
    gone = [r["key"] for r in rows if r["key"] not in seen_keys]
    for k in gone:
        conn.execute(
            "UPDATE postings SET status = 'gone', gone_utc = ? WHERE key = ?", (ts, k)
        )
    return len(gone)


def start_run(conn, kind: str, note: str = "") -> int:
    cur = conn.execute(
        "INSERT INTO runs (kind, started_utc, note) VALUES (?,?,?)", (kind, now(), note)
    )
    conn.commit()
    return cur.lastrowid


def finish_run(conn, run_id: int, note: str = "") -> None:
    conn.execute(
        "UPDATE runs SET finished_utc = ?, note = ? WHERE id = ?", (now(), note, run_id)
    )
    conn.commit()
