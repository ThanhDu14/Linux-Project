"""CRUD todo. Mọi câu SQL đều lọc theo user_id của phiên → không đụng được todo của người khác."""
from flask import Blueprint, g, jsonify, request

from .auth import login_required
from .db import query

bp = Blueprint("todos", __name__, url_prefix="/api/todos")

COLUMNS = "id, title, done, created_at, updated_at"
TITLE_MAX = 200


def _to_json(row):
    return {
        "id": row["id"],
        "title": row["title"],
        "done": row["done"],
        "created_at": row["created_at"].isoformat(),
        "updated_at": row["updated_at"].isoformat(),
    }


def _clean_title(value):
    if not isinstance(value, str):
        return None
    value = value.strip()
    return value if 0 < len(value) <= TITLE_MAX else None


def _body():
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else None


@bp.get("")
@login_required
def list_todos():
    rows = query(f"SELECT {COLUMNS} FROM todos WHERE user_id = %s ORDER BY done, id DESC", (g.user["id"],))
    return jsonify([_to_json(r) for r in rows])


@bp.post("")
@login_required
def create_todo():
    data = _body()
    title = _clean_title(data.get("title")) if data else None
    if title is None:
        return jsonify(error=f"title phải là chuỗi 1–{TITLE_MAX} ký tự"), 400
    row = query(
        f"INSERT INTO todos (user_id, title) VALUES (%s, %s) RETURNING {COLUMNS}",
        (g.user["id"], title),
        one=True,
        commit=True,
    )
    return jsonify(_to_json(row)), 201


@bp.patch("/<int:todo_id>")
@login_required
def update_todo(todo_id):
    data = _body()
    if not data or not ({"title", "done"} & data.keys()):
        return jsonify(error="Cần ít nhất một trong: title, done"), 400

    sets, params = [], []
    if "title" in data:
        title = _clean_title(data["title"])
        if title is None:
            return jsonify(error=f"title phải là chuỗi 1–{TITLE_MAX} ký tự"), 400
        sets.append("title = %s")
        params.append(title)
    if "done" in data:
        if not isinstance(data["done"], bool):
            return jsonify(error="done phải là true/false"), 400
        sets.append("done = %s")
        params.append(data["done"])

    # Tên cột cố định trong code, giá trị đi qua tham số %s
    row = query(
        f"UPDATE todos SET {', '.join(sets)}, updated_at = now() WHERE id = %s AND user_id = %s RETURNING {COLUMNS}",
        (*params, todo_id, g.user["id"]),
        one=True,
        commit=True,
    )
    if row is None:
        return jsonify(error="Không tìm thấy todo"), 404
    return jsonify(_to_json(row))


@bp.delete("/<int:todo_id>")
@login_required
def delete_todo(todo_id):
    row = query(
        "DELETE FROM todos WHERE id = %s AND user_id = %s RETURNING id", (todo_id, g.user["id"]), one=True, commit=True
    )
    if row is None:
        return jsonify(error="Không tìm thấy todo"), 404
    return "", 204
