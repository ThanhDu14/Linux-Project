"""Todo app — API JSON bằng Flask. Giao diện (static/) do Nginx phục vụ, Nginx proxy /api/ và /health về đây.

Chạy (systemd → config/systemd/app.service):
    gunicorn --bind 127.0.0.1:5000 'todo:create_app()'
Cấu hình qua biến môi trường (EnvironmentFile trong /etc/todo-app/, Ansible role app sinh ra):
    SECRET_KEY, DB_PASSWORD (bắt buộc); DB_HOST, DB_PORT, DB_NAME, DB_USER (có mặc định)
"""
import logging
import os
from datetime import timedelta

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.proxy_fix import ProxyFix

from . import auth, db, todos

MUTATING_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


def create_app(config=None):
    app = Flask(__name__, static_folder=None)
    app.config.update(
        SECRET_KEY=os.environ.get("SECRET_KEY"),
        **db.config_from_env(),
        SESSION_COOKIE_NAME="todo_session",
        SESSION_COOKIE_HTTPONLY=True,  # JS không đọc được cookie → XSS không lấy được phiên
        SESSION_COOKIE_SECURE=os.environ.get("SESSION_COOKIE_SECURE", "1") == "1",  # chỉ gửi qua HTTPS
        SESSION_COOKIE_SAMESITE="Lax",
        PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
        MAX_CONTENT_LENGTH=16 * 1024,  # body JSON tối đa 16 KB
        JSON_AS_ASCII=False,
    )
    if config:
        app.config.update(config)
    if not app.config["SECRET_KEY"] or not app.config["DB_PASSWORD"]:
        raise RuntimeError("Thiếu SECRET_KEY hoặc DB_PASSWORD trong biến môi trường")

    # Log ra stderr → journald (journalctl -u app). Có dòng "login failed ... ip=" cho fail2ban.
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    # Sau Nginx: lấy IP client thật + https từ X-Forwarded-For / X-Forwarded-Proto (đúng 1 proxy)
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)

    app.teardown_appcontext(db.close_db)
    app.register_blueprint(auth.bp)
    app.register_blueprint(todos.bp)

    # Chống CSRF: request ghi phải có header tự đặt. Trang web lạ không gửi được header này sang
    # (trình duyệt đòi CORS preflight mà app không cho), còn form HTML thì không đặt được header.
    @app.before_request
    def csrf_guard():
        if request.method in MUTATING_METHODS and request.headers.get("X-Requested-With") != "XMLHttpRequest":
            return jsonify(error="Thiếu header X-Requested-With"), 403
        return None

    # Nginx (status page) và health-check của VM2 gọi /health
    @app.get("/health")
    def health():
        try:
            db.query("SELECT 1")
        except Exception:  # noqa: BLE001 — health-check chỉ cần biết DB có trả lời không
            app.logger.exception("health: không kết nối được PostgreSQL")
            return jsonify(status="error", db="down"), 503
        return jsonify(status="ok", db="up")

    @app.errorhandler(HTTPException)
    def http_error(e):
        return jsonify(error=e.description), e.code

    @app.errorhandler(Exception)
    def internal_error(e):
        app.logger.exception("lỗi không xử lý được")
        return jsonify(error="Lỗi máy chủ"), 500

    return app
