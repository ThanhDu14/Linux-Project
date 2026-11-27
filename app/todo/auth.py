"""Đăng ký / đăng nhập / đăng xuất. Phiên = cookie đã ký bằng SECRET_KEY, chỉ chứa user id."""
import functools
import logging
import re

import psycopg2.errors

from flask import Blueprint, g, jsonify, request, session
from werkzeug.security import check_password_hash, generate_password_hash

from .db import get_db, query

bp = Blueprint("auth", __name__, url_prefix="/api")
log = logging.getLogger("todo.auth")

# User không tồn tại vẫn kiểm tra với hash giả → thời gian trả lời như nhau, không dò được tên user
_DUMMY_HASH = generate_password_hash("khong-phai-mat-khau-that")

# Tên đăng nhập: 3–50 ký tự chữ không dấu, số, . _ -  (khớp users.username varchar(50))
USERNAME_RE = re.compile(r"^[A-Za-z0-9._-]{3,50}$")
PASSWORD_MIN = 8
PASSWORD_MAX = 128


def _start_session(user):
    session.clear()  # phiên mới hoàn toàn sau khi đăng nhập (chống session fixation)
    session.permanent = True
    session["uid"] = user["id"]


def login_required(view):
    @functools.wraps(view)
    def wrapped(*args, **kwargs):
        uid = session.get("uid")
        user = query("SELECT id, username FROM users WHERE id = %s", (uid,), one=True) if uid else None
        if user is None:  # chưa đăng nhập, hoặc user đã bị xoá
            session.clear()
            return jsonify(error="Chưa đăng nhập"), 401
        g.user = user
        return view(*args, **kwargs)

    return wrapped


@bp.post("/login")
def login():
    data = request.get_json(silent=True) or {}
    username, password = data.get("username"), data.get("password")
    if not isinstance(username, str) or not isinstance(password, str) or not username.strip() or not password:
        return jsonify(error="Cần nhập tên đăng nhập và mật khẩu"), 400

    username = username.strip()
    user = query("SELECT id, username, password_hash FROM users WHERE username = %s", (username,), one=True)
    ok = check_password_hash(user["password_hash"] if user else _DUMMY_HASH, password)
    if not user or not ok:
        log.warning("login failed user=%r ip=%s", username[:50], request.remote_addr)
        return jsonify(error="Sai tên đăng nhập hoặc mật khẩu"), 401

    _start_session(user)
    log.info("login ok user=%s ip=%s", user["username"], request.remote_addr)
    return jsonify(username=user["username"])


@bp.post("/register")
def register():
    data = request.get_json(silent=True) or {}
    username, password = data.get("username"), data.get("password")
    if not isinstance(username, str) or not USERNAME_RE.match(username.strip()):
        return jsonify(error="Tên đăng nhập 3–50 ký tự, chỉ gồm chữ không dấu, số và . _ -"), 400
    if not isinstance(password, str) or not PASSWORD_MIN <= len(password) <= PASSWORD_MAX:
        return jsonify(error=f"Mật khẩu phải dài {PASSWORD_MIN}–{PASSWORD_MAX} ký tự"), 400

    username = username.strip()
    try:
        user = query(
            "INSERT INTO users (username, password_hash) VALUES (%s, %s) RETURNING id, username",
            (username, generate_password_hash(password)),
            one=True,
            commit=True,
        )
    except psycopg2.errors.UniqueViolation:  # UNIQUE(username) — kể cả 2 người đăng ký cùng lúc
        get_db().rollback()
        return jsonify(error="Tên đăng nhập đã có người dùng"), 409

    _start_session(user)  # đăng ký xong vào luôn, không phải đăng nhập lại
    log.info("register ok user=%s ip=%s", user["username"], request.remote_addr)
    return jsonify(username=user["username"]), 201


@bp.post("/logout")
def logout():
    session.clear()
    return "", 204


@bp.get("/me")
@login_required
def me():
    return jsonify(username=g.user["username"])
