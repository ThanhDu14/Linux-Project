-- init.sql — Khởi tạo CSDL + role ứng dụng (TV4). Chạy lại nhiều lần vẫn an toàn (idempotent).
--
-- Cách chạy (Ansible gọi, mật khẩu lấy từ vault, KHÔNG ghi vào file này):
--   sudo -u postgres psql -v ON_ERROR_STOP=1 -v app_password='<mật khẩu>' -f init.sql
--
-- Nguyên tắc đặc quyền tối thiểu:
--   - DB appdb thuộc postgres; app_user KHÔNG phải owner, không superuser, không tạo DB/role.
--   - app_user chỉ được CONNECT appdb + SELECT/INSERT/UPDATE/DELETE trên bảng, không được
--     CREATE/DROP/ALTER bảng (schema do script này quản lý).

\set ON_ERROR_STOP on

-- 1. Role ứng dụng
SELECT 'CREATE ROLE app_user LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user')\gexec

ALTER ROLE app_user WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
    CONNECTION LIMIT 20 PASSWORD :'app_password';

-- 2. CSDL riêng
SELECT 'CREATE DATABASE appdb OWNER postgres ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'appdb')\gexec

REVOKE ALL ON DATABASE appdb FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE appdb TO app_user;

\connect appdb

-- 3. Schema: PG14 mặc định cho PUBLIC quyền CREATE trên schema public → thu hồi
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_user;

-- 4. Bảng của app todo (app/ — đăng ký, đăng nhập, CRUD todo)
-- Người dùng tự đăng ký trên web; tài khoản demo do Ansible tạo (role app → python3 -m todo.manage set-password).
-- Mật khẩu chỉ lưu dạng hash (werkzeug: pbkdf2-sha256 + salt), không bao giờ lưu bản rõ.
CREATE TABLE IF NOT EXISTS users (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username      varchar(50) NOT NULL UNIQUE,
    password_hash text        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- Mỗi todo thuộc 1 user; xoá user thì xoá luôn todo của họ
CREATE TABLE IF NOT EXISTS todos (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint       NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title      varchar(200) NOT NULL CHECK (btrim(title) <> ''),
    done       boolean      NOT NULL DEFAULT false,
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS todos_user_id_idx ON todos (user_id);

-- 5. Quyền của app_user (cả bảng hiện có lẫn bảng tạo sau này bởi postgres)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO app_user;
