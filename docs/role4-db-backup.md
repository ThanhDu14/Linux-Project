# TV4 — CSDL & Sao lưu: hướng dẫn cài đặt, demo, vấn đáp

> Người phụ trách: **Nguyễn Đức Duy** (TV4). Kiến trúc chung: [`architecture.md`](architecture.md) mục 7 "Sao lưu".
> Phần báo cáo: [`report/04-csdl-sao-luu.md`](report/04-csdl-sao-luu.md).

## 1. Các file

| File | Đặt trên máy | Vai trò |
|---|---|---|
| `config/postgresql/10-lab.conf` | VM1 `/etc/postgresql/14/main/conf.d/` | `listen_addresses='localhost'`, SCRAM, log kết nối |
| `config/postgresql/pg_hba.conf` | VM1 `/etc/postgresql/14/main/` (640, postgres) | Chỉ `postgres` (peer) và `app_user`→`appdb` từ 127.0.0.1/::1 |
| `config/postgresql/init.sql` | VM1 (Ansible chạy) | Tạo `app_user`, `appdb`, bảng `users` + `todos` (app todo), phân quyền tối thiểu |
| `config/backup/lab-backup.conf` | VM1 + VM2 `/etc/lab-backup.conf` (600, root) | Cấu hình chung cho 3 script |
| `config/backup/authorized_keys.rbackup.example` | VM2 `/home/rbackup/.ssh/authorized_keys` | Khoá key của VM1 bằng `rrsync -wo` |
| `scripts/backup.sh` | VM1 | Kiểm tra đĩa → `pg_dump` → manifest → `.tar.gz` + sha256 → rsync VM2 → retention |
| `scripts/restore.sh` | VM1 | Kiểm tra sha256 → dump an toàn → DROP + `pg_restore --create` → web → so manifest |
| `scripts/backup-offsite.sh` | VM2 | Retention → kiểm tra checksum → `aws s3 sync` |
| `scripts/lib/backup-common.sh` | VM1 + VM2 | log, `trap ERR/EXIT`, cảnh báo msmtp, retention, dấu vân tay DB |
| `config/systemd/lab-backup.{service,timer}` | VM1 | 02:00 hằng ngày |
| `config/systemd/lab-offsite.{service,timer}` | VM2 | 02:30 hằng ngày |

Script được giả định cài ở `/opt/lab-toolkit/scripts/` (đường dẫn trong unit systemd). Nếu role `toolkit` đặt chỗ khác thì sửa `ExecStart`.

## 2. Cài đặt (role Ansible `postgresql`, `backup` — Dự)

### VM1 — `web-app-db-01`
```bash
apt-get install -y postgresql rsync          # Ubuntu 22.04 → PostgreSQL 14, rsync 3.2.7
# Data dir trên EBS /data (đã mount qua fstab bởi role storage)
pg_dropcluster 14 main --stop
pg_createcluster 14 main -d /data/pgdata
install -m 644 config/postgresql/10-lab.conf /etc/postgresql/14/main/conf.d/10-lab.conf
install -o postgres -g postgres -m 640 config/postgresql/pg_hba.conf /etc/postgresql/14/main/pg_hba.conf
systemctl enable --now postgresql@14-main
sudo -u postgres psql -v ON_ERROR_STOP=1 -v app_password="$APP_DB_PASSWORD" -f config/postgresql/init.sql

# Key rsync sang VM2 (public key đưa vào authorized_keys của rbackup trên VM2)
ssh-keygen -t ed25519 -N '' -f /root/.ssh/backup_ed25519 -C root@web-app-db-01
install -m 600 config/backup/lab-backup.conf /etc/lab-backup.conf   # đặt APP_SERVICE, ALERT_TO
cp config/systemd/lab-backup.* /etc/systemd/system/ && systemctl daemon-reload
systemctl enable --now lab-backup.timer
```
- `APP_DB_PASSWORD` để trong Ansible vault. Chuỗi kết nối cho app (TV3, đặt trong `EnvironmentFile`):
  `DATABASE_URL=postgresql://app_user:<mật khẩu>@127.0.0.1:5432/appdb`

### VM2 — `backup-01`
```bash
apt-get install -y rsync awscli
useradd -m -s /bin/bash rbackup
install -d -o rbackup -g rbackup -m 700 /backup/incoming      # /backup là EBS 20 GB
install -d -o rbackup -g rbackup -m 700 /home/rbackup/.ssh
# authorized_keys theo mẫu config/backup/authorized_keys.rbackup.example, thay public key của VM1
install -m 600 config/backup/lab-backup.conf /etc/lab-backup.conf   # đặt S3_BUCKET
cp config/systemd/lab-offsite.* /etc/systemd/system/ && systemctl daemon-reload
systemctl enable --now lab-offsite.timer
```
- `S3_BUCKET` = `terraform -chdir=terraform/environments/shared output -raw backup_bucket_name`. Quyền ghi S3 lấy từ instance profile, không cần access key.

### Phụ thuộc với thành viên khác
| Với ai | Việc |
|---|---|
| **Trân (TV2)** | `AllowUsers` trong sshd của **VM2** phải có `rbackup`. UFW VM2 đã mở 22 từ `10.0.2.10` (architecture 6.5). |
| **TV3** | App dùng `app_user`/`appdb` qua `127.0.0.1:5432`. Bảng `users(id, username, password_hash, created_at)` + `todos(id, user_id, title, done, created_at, updated_at)`; cần bảng khác thì sửa `init.sql` qua PR. Unit systemd: `app.service` (đã điền `APP_SERVICE`). |
| **Hưng (TV5)** | Menu `toolkit.sh` gọi `backup.sh`, `restore.sh -l`, `restore.sh`. Khi `lib/common.sh` xong có thể chuyển `backup-common.sh` sang dùng chung. msmtp: đặt `ALERT_TO` là đủ. |
| **Dự** | Ghi chú: `architecture.md` ghi web ở `/data/www` nhưng Nginx của TV2 phục vụ `/var/www/role2-status` → script sao lưu `WEB_DIR=/var/www` (đổi trong `/etc/lab-backup.conf` nếu chốt khác). |

## 3. Cách dùng

```bash
sudo backup.sh                 # sao lưu đầy đủ + rsync VM2 + retention
sudo backup.sh -n              # chỉ sao lưu cục bộ
sudo restore.sh -l             # liệt kê bản sao lưu
sudo restore.sh                # khôi phục bản mới nhất (hỏi gõ YES)
sudo restore.sh -f /data/backup/lab-backup-20261124-020000.tar.gz -c db -y
sudo backup-offsite.sh         # (VM2) retention + checksum + S3
journalctl -u lab-backup       # log lần chạy theo lịch;  /var/log/lab-backup.log cho lần chạy tay
systemctl list-timers 'lab-*'
```

Nội dung 1 bản sao lưu `lab-backup-YYYYmmdd-HHMMSS.tar.gz`:
```
appdb.dump      pg_dump -Fc (custom, đã nén, khôi phục chọn lọc được)
manifest.txt    mỗi bảng: <tên> <số dòng> <md5 toàn bộ nội dung>   ← dùng để chứng minh toàn vẹn
www/            nội dung web
```

## 4. Kịch bản demo (phút 7–10)

```bash
# 1. DB chỉ nghe localhost
ss -tlnp | grep 5432                     # 127.0.0.1:5432 và [::1]:5432
# 2. Dữ liệu hiện tại
sudo -u postgres psql -d appdb -c "SELECT id, user_id, title, done FROM todos"
# 3. Retention: tạo 1 bản "cũ 10 ngày" để thấy bị xoá
sudo touch -d '10 days ago' /data/backup/lab-backup-20000101-020000.tar.gz
# 4. Sao lưu → file có timestamp, rsync sang VM2, retention xoá bản cũ
sudo /opt/lab-toolkit/scripts/backup.sh
ssh backup-01 'sudo ls -l /backup/incoming'           # bản mới đã có trên VM2
ssh backup-01 'sudo /opt/lab-toolkit/scripts/backup-offsite.sh && aws s3 ls s3://<bucket>/web-app-db-01/'
# 5. PHÁ dữ liệu thật
sudo -u postgres psql -d appdb -c "DELETE FROM todos"   # hoặc: sudo -u postgres dropdb --force appdb
curl -k -H 'Host: app.lab.local' https://127.0.0.1/...   # app thấy dữ liệu mất
# 6. Khôi phục → log in ra "TOÀN VẸN OK", số dòng + md5 khớp manifest
sudo /opt/lab-toolkit/scripts/restore.sh
sudo -u postgres psql -d appdb -c "SELECT id, user_id, title, done FROM todos"
```
Nếu GV hỏi "đĩa đầy thì sao": `echo MIN_FREE_MB=99999999 | sudo tee -a /etc/lab-backup.conf`, chạy `backup.sh` → báo **KHÔNG ĐỦ DUNG LƯỢNG**, exit 1, có mail; xong `sudo sed -i '/MIN_FREE_MB=99999999/d' /etc/lab-backup.conf`.

## 5. Chuẩn bị vấn đáp

1. **"2 giờ sáng đĩa đầy thì sao?"** — Trước khi ghi, script tính `(kích thước DB + web) × 2 + MIN_FREE_MB` và so với `df`; thiếu thì dừng, không ghi gì, exit 1 → systemd ghi unit `failed`, `alert()` gửi mail. Nếu đĩa đầy giữa chừng, `pg_dump`/`tar` lỗi → `set -e` + `trap ERR` bắt, thư mục tạm bị `trap EXIT` xoá. File chính chỉ xuất hiện qua `mv` (nguyên tử) nên không bao giờ có bản dở dang mang tên `lab-backup-*`.
2. **Vì sao `pg_dump -Fc` mà không copy thư mục `pgdata`?** — Copy file khi DB đang chạy cho bản không nhất quán. `pg_dump` chạy trong 1 transaction (snapshot) nên nhất quán mà không cần dừng DB; `-Fc` đã nén, `pg_restore` chọn lọc được.
3. **Restore làm gì với dữ liệu đang có?** — Kiểm sha256 trước; dừng app; dump trạng thái hiện tại ra `pre-restore-*.dump` (lỡ khôi phục nhầm còn quay lại được); `dropdb --force` rồi `pg_restore --create` dựng lại cả DB kèm quyền.
4. **Chứng minh toàn vẹn thế nào?** — Lúc sao lưu ghi `manifest.txt`: mỗi bảng số dòng + md5 của toàn bộ dòng (sắp xếp). Sau khôi phục tính lại và so — khớp 100% mới báo OK. Thêm sha256 cho cả file nén (kiểm ở VM1 khi restore và ở VM2 mỗi đêm).
5. **`rrsync -wo` để làm gì?** — Key của root@VM1 trên VM2 chỉ chạy được rsync, chỉ **ghi** vào `/backup/incoming`. Nếu VM1 bị chiếm, kẻ tấn công không đọc/xoá được bản sao cũ trên VM2 → vẫn khôi phục được (chống ransomware).
6. **Retention làm sao?** — `find -mmin +$((DAYS*1440))` trong script, tính chính xác theo phút. VM1 retention làm **sau** rsync: VM2 hỏng thì script dừng trước, giữ nguyên bản cũ. VM2 giữ 7 ngày; S3 lifecycle (Terraform) giữ 30 ngày → 3 bản ở 3 nơi (quy tắc 3-2-1).
7. **Vì sao `listen_addresses='localhost'` mà vẫn cần `pg_hba.conf`?** — Phòng thủ chiều sâu: lỡ ai đổi listen thì pg_hba vẫn từ chối mọi host ngoài 127.0.0.1/::1, và `app_user` chỉ vào được `appdb`. Ngoài ra SG/NACL/UFW không mở 5432.
8. **Đặc quyền tối thiểu của `app_user`?** — Không superuser/createdb/createrole, không sở hữu DB/bảng; chỉ `CONNECT` appdb + `SELECT/INSERT/UPDATE/DELETE`. Thử `CREATE TABLE` bằng app_user → `permission denied for schema public`.
9. **`set -Eeuo pipefail`?** — `-e` dừng khi lệnh lỗi; `-u` biến chưa đặt là lỗi; `pipefail` lỗi giữa pipe không bị che; `-E` để `trap ERR` có hiệu lực trong hàm. Cứu ở đâu: `pg_dump` lỗi (DB tắt) → dừng ngay, không tạo bản rỗng rồi retention xoá mất bản tốt.
10. **Vì sao timer thay cron?** — Log vào journald (`journalctl -u lab-backup`), `Persistent=true` chạy bù nếu máy tắt lúc 02:00, phụ thuộc `postgresql.service`, xem lịch bằng `systemctl list-timers`.

## 6. Đã kiểm thử

Chạy trong container Ubuntu 22.04 (PostgreSQL 14, rsync 3.2.7, rrsync thật qua sshd):
`shellcheck` sạch cả 4 file; `init.sql` chạy 2 lần không lỗi; 5432 chỉ trên 127.0.0.1/::1; app_user đọc/ghi được, `CREATE TABLE` và vào DB `postgres` bị từ chối; backup + rsync qua rrsync; rrsync chặn đọc và chặn `../`; retention xoá bản 10 ngày ở cả VM1 và VM2; giả lập đĩa đầy → dừng, exit 1; `DELETE FROM notes` + xoá web → restore khớp manifest; `dropdb` → restore; file nén bị sửa → sha256 chặn trước khi đụng dữ liệu.
Chưa chạy trên AWS (đợi Ansible) và chưa chạy `aws s3 sync` thật.
