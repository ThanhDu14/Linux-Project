# 4. Cơ sở dữ liệu, Sao lưu & Khôi phục

*Phụ trách: Nguyễn Đức Duy (TV4). File cấu hình thật: `config/postgresql/`, `config/backup/`, `config/systemd/lab-*.{service,timer}`; script: `scripts/backup.sh`, `scripts/restore.sh`, `scripts/backup-offsite.sh`, `scripts/lib/backup-common.sh`.*

## 4.1 PostgreSQL

**Phiên bản & vị trí dữ liệu.** PostgreSQL 14 (gói mặc định của Ubuntu 22.04) chạy trên VM1 `web-app-db-01`. Cluster được tạo bằng `pg_createcluster 14 main -d /data/pgdata`, tức thư mục dữ liệu nằm trên ổ EBS riêng mount ở `/data` qua `/etc/fstab` (UUID, `nofail`). Lợi ích: dữ liệu tách khỏi ổ hệ điều hành, và ổ này vẫn còn sau khi thay máy.

**Chỉ nghe trên localhost.** `config/postgresql/10-lab.conf` đặt `listen_addresses = 'localhost'`. Ứng dụng Flask chạy cùng máy, nên không có lý do gì để mở 5432 ra mạng. Cổng 5432 cũng không có trong bất kỳ Security Group, NACL hay luật UFW nào.

> 📷 *Hình 4.1 — `ss -tlnp | grep 5432`: chỉ `127.0.0.1:5432` và `[::1]:5432`.*

**Xác thực (`pg_hba.conf`).** PostgreSQL dùng dòng khớp đầu tiên:

| Loại | DB | User | Nguồn | Phương thức | Ý nghĩa |
|---|---|---|---|---|---|
| local | all | postgres | socket | peer | Chỉ user HĐH `postgres` quản trị được (`sudo -u postgres psql`) |
| host | appdb | app_user | 127.0.0.1/32, ::1/128 | scram-sha-256 | App chỉ vào đúng DB của mình, có mật khẩu |
| local/host | all | all | mọi nơi | reject | Từ chối tường minh mọi kết nối khác |

Mật khẩu được băm bằng `scram-sha-256` (`password_encryption`) thay cho md5. Kết nối và ngắt kết nối đều được ghi log (`log_connections`, `log_disconnections`) để truy vết.

**Đặc quyền tối thiểu.** `config/postgresql/init.sql` (Ansible chạy, chạy lại nhiều lần vẫn an toàn) tạo:
- DB `appdb` do `postgres` sở hữu. Thu hồi `ALL` của `PUBLIC` trên DB và trên schema `public`, vì PG14 mặc định cho mọi user quyền `CREATE` trong `public`.
- Role `app_user`: `LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION`, giới hạn 20 kết nối. Role chỉ có `CONNECT` trên `appdb` và `SELECT/INSERT/UPDATE/DELETE` trên bảng, không sở hữu đối tượng nào nên không `CREATE/ALTER/DROP` được.
- Mật khẩu của `app_user` truyền vào bằng `psql -v app_password=...` từ Ansible vault. Nó không nằm trong mã nguồn, và app đọc nó từ `EnvironmentFile` (mục 3).

> 📷 *Hình 4.2 — đăng nhập bằng `app_user` rồi thử `CREATE TABLE` → `permission denied for schema public`; kết nối tới DB `postgres` → `pg_hba.conf rejects connection`.*

## 4.2 Chiến lược sao lưu

| | Giá trị |
|---|---|
| Sao lưu cái gì | DB `appdb` (`pg_dump -Fc`) + nội dung web `/var/www` |
| Định dạng | `lab-backup-YYYYmmdd-HHMMSS.tar.gz` + `.sha256`, bên trong có `appdb.dump`, `manifest.txt`, `www/` |
| Lịch | `lab-backup.timer` trên VM1: **02:00 hằng ngày**; `lab-offsite.timer` trên VM2: **02:30 hằng ngày**; cả hai `Persistent=true` (máy tắt lúc tới giờ thì chạy bù khi bật lại) |
| Nơi lưu (3-2-1) | VM1 `/data/backup` → VM2 `/backup/incoming` (EBS riêng) → S3 (đa AZ, mã hoá AES256, versioning) |
| Lưu giữ | VM1: 7 ngày · VM2: 7 ngày (trong script) · S3: 30 ngày (lifecycle Terraform) |

> 📷 *Hình 4.3 — `systemctl list-timers 'lab-*'` trên VM1 và VM2.*

**Luồng `backup.sh` (VM1):**
1. **Kiểm tra dung lượng trước khi ghi.** Script ước lượng `(kích thước DB + web) × 2 + MIN_FREE_MB` rồi so với `df`. Nếu thiếu, nó dừng ngay (exit 1), không ghi gì và gửi cảnh báo.
2. **`pg_dump -Fc`.** Lệnh chạy trong một snapshot giao dịch nên bản dump nhất quán mà không phải dừng DB. Định dạng custom đã được nén và cho phép khôi phục chọn lọc.
3. **Manifest.** Với mỗi bảng, script ghi số dòng và md5 của toàn bộ nội dung (các dòng sắp theo thứ tự). Đây là căn cứ để chứng minh toàn vẹn khi khôi phục.
4. **Nén thành một file gắn timestamp** trong thư mục tạm, rồi `mv` (thao tác nguyên tử) sang tên chính thức. Nhờ vậy không bao giờ tồn tại bản dở dang mang tên `lab-backup-*`. Script tạo kèm `sha256sum`, và file có quyền 600.
5. **rsync sang VM2** bằng key riêng. Ở VM2, key bị khoá bằng `command="rrsync -wo /backup/incoming",restrict`: chỉ được *ghi* vào đúng thư mục đó, không đọc, liệt kê hay xoá được bản cũ. Nếu VM1 bị chiếm, kẻ tấn công cũng không phá được bản sao trên VM2.
6. **Retention:** `find -mmin +$((7*1440))` xoá bản cũ hơn 7 ngày. Bước này chạy *sau* rsync: nếu VM2 lỗi, script đã dừng ở bước 5 và các bản cũ được giữ nguyên.

**`backup-offsite.sh` (VM2):** áp retention 7 ngày → kiểm `sha256sum -c` mọi bản đang giữ → `aws s3 sync` lên S3 qua S3 Gateway Endpoint. Quyền ghi S3 lấy từ IAM instance profile, không có access key trên máy.

> 📷 *Hình 4.4 — chạy `backup.sh`: log từng bước, file mới trong `/data/backup`, dòng `retention: đã xoá ... lab-backup-20000101-...`.*
> 📷 *Hình 4.5 — `ls -l /backup/incoming` trên VM2 và `aws s3 ls s3://<bucket>/web-app-db-01/`.*

**Xử lý lỗi.** Mọi script dùng `set -Eeuo pipefail`, `trap ERR` (ghi log lệnh và dòng gây lỗi, gửi mail qua msmtp nếu đặt `ALERT_TO`) và `trap EXIT` (xoá thư mục tạm). Log ghi vào journald (`journalctl -u lab-backup`) và `/var/log/lab-backup.log`. Các tham số dùng `getopts`, có `--help`. Cả 4 file qua `shellcheck` sạch.

## 4.3 Quy trình khôi phục

```bash
sudo restore.sh -l                      # liệt kê các bản
sudo restore.sh                         # bản mới nhất, hỏi gõ YES
sudo restore.sh -f <file> -c db|web|all -y
```
1. Kiểm sha256. Nếu file hỏng thì dừng **trước khi** đụng vào dữ liệu đang chạy.
2. Xác nhận: phải gõ `YES`, hoặc dùng `-y` khi chạy trong script.
3. Dừng service app để không còn kết nối giữ DB.
4. **Lưới an toàn:** dump DB hiện tại ra `pre-restore-<timestamp>.dump` (lỡ khôi phục nhầm vẫn quay lại được).
5. `dropdb --force` rồi `pg_restore --create`, dựng lại toàn bộ DB kèm quyền của `app_user`. Cách này chạy được cả khi chỉ mất vài dòng lẫn khi mất cả DB.
6. Khôi phục web bằng `rsync -a --delete`.
7. Tính lại số dòng và md5 từng bảng rồi so với `manifest.txt`. Chỉ khi khớp 100% mới in **TOÀN VẸN OK**, ngược lại exit 1.
8. Bật lại app (ở `trap EXIT`, nên app vẫn được bật lại kể cả khi khôi phục lỗi giữa chừng).

Nếu VM1 mất cả bản cục bộ: quản trị viên chép bản từ VM2 (`/backup/incoming`) hoặc S3 về rồi chạy `restore.sh -f <file>`.

## 4.4 Bằng chứng kiểm thử

| Kịch bản | Kết quả |
|---|---|
| `DELETE FROM notes` + xoá thư mục web → `restore.sh` | Khôi phục đủ 4 dòng, md5 khớp manifest, web trở lại |
| `dropdb appdb` → `restore.sh -c db` | DB được dựng lại, `app_user` đọc/ghi được ngay |
| Sửa 1 byte file sao lưu → `restore.sh` | `sha256 KHÔNG KHỚP`, dừng, dữ liệu không bị đụng |
| Đặt `MIN_FREE_MB` rất lớn (giả lập đĩa đầy) → `backup.sh` | `KHÔNG ĐỦ DUNG LƯỢNG`, exit 1, không tạo file |
| Bản "cũ 10 ngày" (`touch -d '10 days ago'`) | Bị retention xoá trên VM1 và VM2 |
| Dùng key backup để đọc/liệt kê VM2 hoặc ghi ra `../` | rrsync từ chối |

> 📷 *Hình 4.6 — demo phá dữ liệu: `SELECT count(*)` trước, `DELETE`, chạy `restore.sh` với dòng "TOÀN VẸN OK", `SELECT` sau.*
