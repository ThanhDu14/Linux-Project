"""Test API với PostgreSQL thật (schema từ config/postgresql/init.sql).

Cần: PostgreSQL đang chạy, đã chạy init.sql, và biến DB_PASSWORD (+ DB_HOST/DB_PORT nếu khác mặc định)
của app_user. Chạy:  cd app && python3 -m pytest -q
"""
import os

import psycopg2
import pytest

from todo import create_app, db
from todo.manage import set_password

H = {"X-Requested-With": "XMLHttpRequest"}


@pytest.fixture()
def app():
    cfg = db.config_from_env()
    conn = db.connect(cfg)
    with conn.cursor() as cur:
        cur.execute("DELETE FROM users")  # todos xoá theo (ON DELETE CASCADE)
    conn.commit()
    assert set_password(conn, "alice", "alice-pass-123") == "created"
    assert set_password(conn, "bob", "bob-pass-123") == "created"
    conn.close()
    return create_app({"TESTING": True, "SECRET_KEY": "test", "SESSION_COOKIE_SECURE": False})


@pytest.fixture()
def client(app):
    return app.test_client()


def login(client, user="alice", pw="alice-pass-123"):
    return client.post("/api/login", json={"username": user, "password": pw}, headers=H)


# ---------- health ----------
def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.get_json() == {"status": "ok", "db": "up"}


# ---------- đăng nhập ----------
def test_login_ok_and_me(client):
    r = login(client)
    assert r.status_code == 200 and r.get_json() == {"username": "alice"}
    assert client.get("/api/me").get_json() == {"username": "alice"}


def test_session_cookie_flags(app):
    c = app.test_client()
    app.config["SESSION_COOKIE_SECURE"] = True
    r = login(c)
    cookie = r.headers["Set-Cookie"]
    assert "HttpOnly" in cookie and "Secure" in cookie and "SameSite=Lax" in cookie


@pytest.mark.parametrize("user,pw", [("alice", "sai-mat-khau"), ("khong-co", "alice-pass-123")])
def test_login_wrong(client, user, pw):
    r = login(client, user, pw)
    assert r.status_code == 401
    assert r.get_json()["error"] == "Sai tên đăng nhập hoặc mật khẩu"  # không lộ user có tồn tại hay không
    assert client.get("/api/me").status_code == 401


def test_login_missing_fields(client):
    assert client.post("/api/login", json={"username": "alice"}, headers=H).status_code == 400
    assert client.post("/api/login", data="x", headers=H).status_code == 400


def test_logout(client):
    login(client)
    assert client.post("/api/logout", headers=H).status_code == 204
    assert client.get("/api/me").status_code == 401


def test_requires_login(client):
    assert client.get("/api/todos").status_code == 401
    assert client.post("/api/todos", json={"title": "x"}, headers=H).status_code == 401


def test_csrf_header_required(client):
    login(client)
    r = client.post("/api/todos", json={"title": "x"})  # thiếu X-Requested-With
    assert r.status_code == 403
    assert client.post("/api/login", json={"username": "alice", "password": "alice-pass-123"}).status_code == 403


# ---------- đăng ký ----------
def register(client, user="carol", pw="carol-pass-123"):
    return client.post("/api/register", json={"username": user, "password": pw}, headers=H)


def test_register_logs_in(client):
    r = register(client)
    assert r.status_code == 201 and r.get_json() == {"username": "carol"}
    assert client.get("/api/me").get_json() == {"username": "carol"}
    assert client.get("/api/todos").get_json() == []


def test_register_then_login(app):
    register(app.test_client())
    assert login(app.test_client(), "carol", "carol-pass-123").status_code == 200


def test_register_duplicate(client):
    r = register(client, "alice")
    assert r.status_code == 409 and "đã có" in r.get_json()["error"]
    # mật khẩu cũ của alice không bị ghi đè
    assert login(client).status_code == 200


@pytest.mark.parametrize(
    "user,pw",
    [("ab", "carol-pass-123"), ("có dấu", "carol-pass-123"), ("a b c", "carol-pass-123"),
     ("x" * 51, "carol-pass-123"), ("carol", "short"), ("carol", "x" * 129), (None, "carol-pass-123")],
)
def test_register_invalid(client, user, pw):
    r = client.post("/api/register", json={"username": user, "password": pw}, headers=H)
    assert r.status_code == 400
    assert client.get("/api/me").status_code == 401


def test_register_needs_csrf_header(client):
    assert client.post("/api/register", json={"username": "carol", "password": "carol-pass-123"}).status_code == 403


# ---------- CRUD ----------
def test_crud(client):
    login(client)
    assert client.get("/api/todos").get_json() == []

    r = client.post("/api/todos", json={"title": "  Mua sữa  "}, headers=H)
    assert r.status_code == 201
    todo = r.get_json()
    assert todo["title"] == "Mua sữa" and todo["done"] is False

    r = client.patch(f"/api/todos/{todo['id']}", json={"done": True}, headers=H)
    assert r.status_code == 200 and r.get_json()["done"] is True

    r = client.patch(f"/api/todos/{todo['id']}", json={"title": "Mua 2 hộp sữa"}, headers=H)
    assert r.get_json()["title"] == "Mua 2 hộp sữa"

    items = client.get("/api/todos").get_json()
    assert [t["title"] for t in items] == ["Mua 2 hộp sữa"]

    assert client.delete(f"/api/todos/{todo['id']}", headers=H).status_code == 204
    assert client.get("/api/todos").get_json() == []
    assert client.delete(f"/api/todos/{todo['id']}", headers=H).status_code == 404


def test_order_undone_first(client):
    login(client)
    a = client.post("/api/todos", json={"title": "A"}, headers=H).get_json()
    client.post("/api/todos", json={"title": "B"}, headers=H)
    client.patch(f"/api/todos/{a['id']}", json={"done": True}, headers=H)
    assert [t["title"] for t in client.get("/api/todos").get_json()] == ["B", "A"]


@pytest.mark.parametrize("body", [{}, {"title": ""}, {"title": "   "}, {"title": 123}, {"title": "x" * 201}])
def test_create_invalid(client, body):
    login(client)
    assert client.post("/api/todos", json=body, headers=H).status_code == 400


@pytest.mark.parametrize("body", [{}, {"done": "yes"}, {"title": ""}, {"other": 1}])
def test_update_invalid(client, body):
    login(client)
    t = client.post("/api/todos", json={"title": "x"}, headers=H).get_json()
    assert client.patch(f"/api/todos/{t['id']}", json=body, headers=H).status_code == 400


def test_user_isolation(app):
    alice, bob = app.test_client(), app.test_client()
    login(alice)
    login(bob, "bob", "bob-pass-123")
    t = alice.post("/api/todos", json={"title": "của alice"}, headers=H).get_json()

    assert bob.get("/api/todos").get_json() == []
    assert bob.patch(f"/api/todos/{t['id']}", json={"done": True}, headers=H).status_code == 404
    assert bob.delete(f"/api/todos/{t['id']}", headers=H).status_code == 404
    assert alice.get("/api/todos").get_json()[0]["done"] is False


def test_sql_injection_is_data(client):
    login(client)
    evil = "x'); DROP TABLE todos; --"
    client.post("/api/todos", json={"title": evil}, headers=H)
    assert client.get("/api/todos").get_json()[0]["title"] == evil


def test_deleted_user_session_invalid(app, client):
    login(client)
    conn = db.connect(db.config_from_env())
    with conn.cursor() as cur:
        cur.execute("DELETE FROM users WHERE username = 'alice'")
    conn.commit()
    conn.close()
    assert client.get("/api/todos").status_code == 401


def test_unknown_route_json(client):
    r = client.get("/api/khong-co")
    assert r.status_code == 404 and "error" in r.get_json()


# ---------- quản lý tài khoản ----------
def test_set_password_idempotent(app):
    conn = db.connect(db.config_from_env())
    assert set_password(conn, "alice", "alice-pass-123") == "unchanged"
    assert set_password(conn, "alice", "mat-khau-moi-1") == "updated"
    with conn.cursor() as cur:
        cur.execute("SELECT password_hash FROM users WHERE username = 'alice'")
        assert not cur.fetchone()[0].startswith("mat-khau")  # chỉ lưu hash
    conn.close()


# ---------- quyền DB: app_user không sửa được schema ----------
def test_app_user_cannot_ddl(app):
    conn = db.connect(db.config_from_env())
    with pytest.raises(psycopg2.errors.InsufficientPrivilege):
        with conn.cursor() as cur:
            cur.execute("DROP TABLE todos")
    conn.close()
