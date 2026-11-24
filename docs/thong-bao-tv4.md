# Thông báo từ TV4 (Duy — CSDL & sao lưu) gửi cả nhóm

> Phần TV4 đã xong và chạy thử trong Ubuntu 22.04: PostgreSQL, `init.sql`, `backup.sh`, `restore.sh`, `backup-offsite.sh`, systemd timer.
> Chi tiết cài đặt: [`role4-db-backup.md`](role4-db-backup.md) mục 2. Dưới đây là việc **mỗi bạn cần làm/biết** để phần sao lưu chạy được trên AWS.

## Dự — Hạ tầng / Ansible

- **Role `postgresql` (VM1):** làm theo [`role4-db-backup.md`](role4-db-backup.md) mục 2 "VM1":
  - `pg_createcluster 14 main -d /data/pgdata`, sau khi role `storage` đã mount `/data`.
  - Copy `config/postgresql/10-lab.conf` vào `conf.d/` và `pg_hba.conf` (quyền 640, chủ postgres).
  - Chạy `init.sql` với `-v app_password=...`. Mật khẩu để trong vault, biến gợi ý `vault_app_db_password`.
- **VM1:** tạo key `/root/.ssh/backup_ed25519`, copy `config/backup/lab-backup.conf` → `/etc/lab-backup.conf` (600), cài `lab-backup.{service,timer}` rồi `enable --now lab-backup.timer`.
- **Role `backup_target` (VM2):**
  - Cài `rsync awscli`, tạo user `rbackup`, tạo `/backup/incoming` (700, chủ rbackup).
  - Tạo `authorized_keys` theo `config/backup/authorized_keys.rbackup.example`, trong đó điền public key root của VM1.
  - Copy `/etc/lab-backup.conf` và đặt `S3_BUCKET` = output `backup_bucket_name` của `shared`.
  - Cài `lab-offsite.{service,timer}`.
- **Đường dẫn script:** unit systemd đang gọi `/opt/lab-toolkit/scripts/…`. Nếu role `toolkit` đặt chỗ khác thì báo mình sửa `ExecStart`.
- **Lệch tài liệu:** `architecture.md` mục 7 ghi web ở `/data/www`, nhưng Nginx của Trân phục vụ `/var/www/role2-status`. Script đang sao lưu cả `/var/www` (`WEB_DIR`). Chốt chỗ nào thì sửa một trong hai cho khớp.

## Trân — Nginx & bảo mật host

- **SSH trên VM2:** khi điền `AllowUsers` trong `config/ssh/sshd-hardening.conf` thì **VM2 phải có `rbackup`**, nếu không rsync từ VM1 sẽ bị chặn. Ví dụ VM2: `AllowUsers ubuntu rbackup`. VM1 không cần.
- **fail2ban:** VM1 rsync sang VM2 bằng key mỗi đêm, không dò mật khẩu, nên không bị ban. Có thể thêm `ignoreip = 10.0.2.10` cho jail sshd trên VM2 cho chắc.
- **UFW VM2:** đã có 22/tcp từ `10.0.2.10` (`architecture.md` 6.5), đủ cho backup.
- Không cần mở 5432 ở đâu cả: PostgreSQL chỉ nghe `127.0.0.1`.

## TV3 — Ứng dụng Flask & systemd

- **Kết nối DB**, đặt trong `EnvironmentFile`, không hard-code:
  `DATABASE_URL=postgresql://app_user:<mật khẩu>@127.0.0.1:5432/appdb`
  Mật khẩu chính là `app_password` mà Ansible truyền cho `init.sql`.
- **Bảng có sẵn:** `notes(id bigint identity, title varchar(200), content text, created_at timestamptz)`, đã có 3 dòng mẫu.
  - `app_user` được `SELECT/INSERT/UPDATE/DELETE`, **không** được `CREATE/ALTER TABLE`, nên app **không tự tạo bảng** (không gọi `db.create_all()`).
  - Cần bảng/cột khác thì mở PR sửa `config/postgresql/init.sql`, mình review.
- **`/health`** có thể kiểm DB bằng `SELECT 1`.
- **Báo mình tên unit systemd của app** (vd. `flask-app.service`) để điền `APP_SERVICE`. `restore.sh` sẽ dừng app trong lúc khôi phục rồi bật lại.
- **Báo cáo:** phần của mình ở [`report/04-csdl-sao-luu.md`](report/04-csdl-sao-luu.md). Ảnh chụp (📷) sẽ bổ sung khi hệ thống chạy trên AWS.

## Hưng — Bash toolkit & cảnh báo

- **Menu `toolkit.sh`** gọi được ngay:
  - `scripts/backup.sh` (sao lưu), `scripts/restore.sh -l` (liệt kê), `scripts/restore.sh` (khôi phục, hỏi gõ YES).
  - Cả 3 đều có `--help`, đều cần chạy bằng `sudo`.
  - Mã thoát khác 0 khi lỗi.
- **Shellcheck:** cả 4 file (`backup.sh`, `restore.sh`, `backup-offsite.sh`, `lib/backup-common.sh`) đã sạch với `shellcheck -x`. Nhờ chạy lại trong lượt kiểm toàn bộ `scripts/`.
- **`lib/backup-common.sh`** hiện tự có `log`, `die`, `trap ERR/EXIT`. Khi `lib/common.sh` xong, nếu muốn thống nhất thì mình chuyển sang dùng chung, gửi mình tên hàm.
- **Cảnh báo:** script gửi mail bằng `msmtp` khi đặt `ALERT_TO=` trong `/etc/lab-backup.conf`. Bạn cấu hình msmtp (`/etc/msmtprc`) xong là chạy.
- **Health-check** có thể kiểm thêm `systemctl is-failed lab-backup.service` để cảnh báo khi backup đêm qua lỗi.

## Lịch sao lưu (để ghi chung vào báo cáo / README)

| Máy | Timer | Giờ | Việc |
|---|---|---|---|
| VM1 web-app-db-01 | `lab-backup.timer` | 02:00 hằng ngày | dump DB + web → nén → rsync VM2 → giữ 7 ngày |
| VM2 backup-01 | `lab-offsite.timer` | 02:30 hằng ngày | giữ 7 ngày → kiểm checksum → S3 |
| S3 | lifecycle (Terraform) | — | xoá bản cũ hơn 30 ngày |
