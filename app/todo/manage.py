"""Quản lý tài khoản từ dòng lệnh (đặt/đổi mật khẩu; Ansible dùng để tạo tài khoản demo).

    echo 'mat-khau' | DB_PASSWORD=... python3 -m todo.manage set-password <username>

Đọc mật khẩu từ stdin (không để trên dòng lệnh — ai cũng xem được qua ps).
In ra: created | updated | unchanged (Ansible dựa vào đây để báo changed).
"""
import sys

from werkzeug.security import check_password_hash, generate_password_hash

from . import db

USERNAME_MAX = 50
PASSWORD_MIN = 8


def set_password(conn, username, password):
    with conn.cursor() as cur:
        cur.execute("SELECT password_hash FROM users WHERE username = %s", (username,))
        row = cur.fetchone()
        if row and check_password_hash(row[0], password):
            return "unchanged"
        pw_hash = generate_password_hash(password)
        if row:
            cur.execute("UPDATE users SET password_hash = %s WHERE username = %s", (pw_hash, username))
            result = "updated"
        else:
            cur.execute("INSERT INTO users (username, password_hash) VALUES (%s, %s)", (username, pw_hash))
            result = "created"
    conn.commit()
    return result


def main(argv):
    if len(argv) != 2 or argv[0] != "set-password":
        print(__doc__, file=sys.stderr)
        return 2
    username = argv[1].strip()
    password = sys.stdin.readline().rstrip("\n")
    if not 0 < len(username) <= USERNAME_MAX:
        print(f"username phải dài 1–{USERNAME_MAX} ký tự", file=sys.stderr)
        return 1
    if len(password) < PASSWORD_MIN:
        print(f"mật khẩu phải có ít nhất {PASSWORD_MIN} ký tự", file=sys.stderr)
        return 1
    cfg = db.config_from_env()
    if not cfg["DB_PASSWORD"]:
        print("thiếu DB_PASSWORD trong biến môi trường", file=sys.stderr)
        return 1
    conn = db.connect(cfg)
    try:
        print(set_password(conn, username, password))
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
