"""Kết nối PostgreSQL: mỗi request một kết nối (DB cùng máy, 127.0.0.1), đóng khi request xong."""
import os

import psycopg2
import psycopg2.extras
from flask import current_app, g


def config_from_env():
    return {
        "DB_HOST": os.environ.get("DB_HOST", "127.0.0.1"),
        "DB_PORT": int(os.environ.get("DB_PORT", "5432")),
        "DB_NAME": os.environ.get("DB_NAME", "appdb"),
        "DB_USER": os.environ.get("DB_USER", "app_user"),
        "DB_PASSWORD": os.environ.get("DB_PASSWORD"),
    }


def connect(cfg):
    return psycopg2.connect(
        host=cfg["DB_HOST"],
        port=cfg["DB_PORT"],
        dbname=cfg["DB_NAME"],
        user=cfg["DB_USER"],
        password=cfg["DB_PASSWORD"],
        connect_timeout=5,
        application_name="todo-app",
    )


def get_db():
    if "db" not in g:
        g.db = connect(current_app.config)
    return g.db


def close_db(_exc=None):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()  # chưa commit → rollback


def query(sql, params=(), one=False, commit=False):
    """Chạy SQL có tham số (%s — psycopg2 tự escape, không ghép chuỗi). Trả về list dict, hoặc 1 dict/None."""
    conn = get_db()
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall() if cur.description else []
    if commit:
        conn.commit()
    if one:
        return rows[0] if rows else None
    return rows
