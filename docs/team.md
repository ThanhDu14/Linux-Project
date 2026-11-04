# Phân công nhóm

> Nhóm 5 người, ánh xạ theo 5 vai gợi ý ở mục 1.2 của đề. Kiến trúc: xem `docs/architecture.md`.
> Đề chấm **điểm cá nhân**: mỗi người phải bảo vệ được phần mình VÀ hiểu tổng thể hệ thống.
> Điền họ tên + MSSV vào bảng dưới khi chốt.

---

## 1. Tổng quan

| # | Thành viên | MSSV | Vai | Tiêu chí chính |
|---|---|---|---|---|
| 1 | **Dự** | | Hạ tầng AWS — Terraform + Ansible | Hệ thống (30%) |
| 2 | **Trân** | | Reverse proxy & bảo mật host | Bảo mật (20%) |
| 3 | Thành viên 3 | | Ứng dụng & systemd, ghép báo cáo | Hệ thống (30%), Báo cáo (15%) |
| 4 | Thành viên 4 | | CSDL & sao lưu | Sao lưu (20%) |
| 5 | Thành viên 5 | | Bash toolkit & cảnh báo | Tự động hóa (15%) |

---

## 2. Chi tiết từng vai

### 2.1 Dự — Hạ tầng AWS (Terraform + Ansible)

**Phụ trách**
- **Terraform** (`terraform/`, cùng khuôn repo NT548 — chi tiết ở `architecture.md` mục 8):
  - `bootstrap/`: S3 bucket chứa tfstate (versioning, mã hoá, chặn public, `prevent_destroy`).
  - `modules/vpc`: VPC, 2 subnet, IGW, NAT Gateway (`enable_nat`), route table, S3 Gateway Endpoint.
  - `modules/nacl`, `modules/security-group`: 2 NACL + 4 SG đúng bảng ở `architecture.md` mục 6.
  - `modules/ec2`: EC2 Ubuntu 22.04 + EBS, gọi 3 lần cho 3 máy.
  - `modules/nlb`: NLB (`enable_nlb`), listener 80/443, target group, health check.
  - `modules/s3`, `modules/iam`: S3 backup + lifecycle, role/instance profile cho VM2.
  - `environments/shared`: S3 backup + IAM (sống lâu). `environments/lab`: VPC, NACL, SG, EC2, NLB (dựng/huỷ), đọc `shared` qua `terraform_remote_state`, sinh `ansible/inventory/hosts.ini`.
  - `.checkov.yml` quét bảo mật; AWS Budget cảnh báo chi phí; IAM user + MFA cho từng thành viên.
- **Ansible** (`ansible/`):
  - `inventory/` + `group_vars/` (ProxyJump qua Bastion, vault cho bí mật).
  - Roles: `common` (hostname, user sudo, SSH key, package), `storage` (EBS + fstab), và **phần triển khai** của các role `ssh_hardening`, `firewall`, `fail2ban`, `auditd`, `nginx`, `postgresql`, `app`, `backup_target`, `toolkit`.
  - `site.yml` điều phối toàn bộ.
- **Nguyên tắc**: role chỉ **copy** file từ `config/` (do thành viên khác sở hữu), không tự sửa nội dung. Muốn sửa → mở PR cho chủ file review.

**Sản phẩm nộp**: `terraform/`, `ansible/`, sơ đồ kiến trúc, phần README "Cách tái tạo hệ thống".

**Demo**: trình bày sơ đồ; đi qua SG/NACL/route table; SSH qua Bastion bằng ProxyJump; (tuỳ chọn) chạy `ansible-playbook --check` cho thấy hệ thống đúng trạng thái mong muốn.

**Báo cáo**: Tổng quan hệ thống, sơ đồ, mạng & tường lửa lớp AWS, cách tái tạo.

**Câu hỏi vấn đáp cần chuẩn bị**
- Route table khác Security Group / NACL thế nào? Hai subnet nói chuyện với nhau nhờ đâu?
- Vì sao `nacl-private` phải mở 80/443 từ `0.0.0.0/0`?
- Vì sao chọn NLB thay ALB, NAT Gateway thay NAT instance?
- Tắt NAT thì cái gì còn chạy, cái gì không?
- Vì sao bootstrap tách riêng? Mất file tfstate thì sao? Vì sao backend dùng partial config?
- Vì sao tách `shared` và `lab`? Destroy `lab` thì backup còn không?
- Terraform, Ansible, Bash — mỗi công cụ lo phần nào, vì sao không dùng Ansible để deploy?

---

### 2.2 Thành viên 2 — Reverse proxy & bảo mật host

**Phụ trách**
- Nginx: 2 vhost (`app.lab.local`, `status.lab.local`), `proxy_pass` + header (`Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`).
- TLS tự ký bằng `openssl`, chuyển hướng 80 → 443 (301).
- UFW trên cả 3 máy (bảng ở `architecture.md` mục 6.5), giải thích lý do mở từng cổng.
- Gia cố SSH: tắt root, chỉ dùng khoá, `AllowUsers`.
- fail2ban: jail `sshd` (bắt buộc), jail cho Nginx (khuyến khích).
- auditd: theo dõi `/etc/passwd`, `/etc/shadow`.
- Chạy Lynis: ghi điểm trước/sau, khắc phục ≥ 3 mục.

**Sở hữu**: `config/nginx/`, `config/ssh/`, `config/ufw/`, `config/fail2ban/`, `config/audit/`, chứng chỉ TLS.

**Demo**: curl 2 vhost, 80 → 443; ban fail2ban trực tiếp; `ausearch` thấy truy cập `/etc/shadow`.

**Báo cáo**: Bảo mật (phần hệ điều hành), Lynis, TLS.

---

### 2.3 Thành viên 3 — Ứng dụng & systemd (+ ghép báo cáo)

**Phụ trách**
- Ứng dụng Flask (chạy bằng gunicorn): ≥ 1 endpoint đọc, ≥ 1 endpoint ghi, `/health` có kiểm tra kết nối DB.
- Lắng nghe `127.0.0.1:5000`, log ra stdout/stderr → journald.
- systemd unit: `Restart=on-failure`, `EnvironmentFile` (quyền `600`, chủ là user app), chạy bằng user riêng không phải root.
- Không hard-code bí mật.
- **Ghép báo cáo**: thống nhất định dạng, mục lục, README.

**Sở hữu**: `app/`, `config/systemd/`, `README.md`, file báo cáo tổng.

**Demo**: gọi end-to-end (curl → Nginx → app → DB); `systemctl status`; `kill -9` app → systemd khởi động lại, xem `journalctl`.

**Báo cáo**: Ứng dụng & systemd; ghép toàn bộ.

---

### 2.4 Thành viên 4 — CSDL & sao lưu

**Phụ trách**
- PostgreSQL: DB riêng, role ứng dụng quyền tối thiểu, `listen_addresses = 'localhost'`, `pg_hba.conf` chặt; data dir trên `/data`.
- Script SQL khởi tạo schema + role (Ansible gọi).
- Script **backup**: `pg_dump` + tar nội dung web → nén, gắn timestamp → kiểm tra dung lượng đĩa trước khi chạy → rsync sang VM2 (key giới hạn bằng `rrsync`).
- **Retention** trong script (xoá bản > 7 ngày) trên cả VM1 và VM2.
- VM2 đẩy lên S3 (`aws s3 sync`); lifecycle do Dự tạo bằng Terraform.
- Lịch chạy bằng systemd timer (hoặc cron), ghi lịch vào báo cáo.
- Script **restore** từ bản do chính bộ công cụ tạo ra.

**Sở hữu**: `config/postgresql/`, `scripts/backup.sh`, `scripts/restore.sh`, timer của backup.

**Demo**: `ss -tlnp` thấy 5432 chỉ trên `127.0.0.1`; chạy backup → file nén có timestamp xuất hiện trên VM2 + S3, retention xoá bản cũ; **xoá dữ liệu thật rồi restore**, chứng minh toàn vẹn.

**Báo cáo**: CSDL, Sao lưu & khôi phục.

---

### 2.5 Thành viên 5 — Bash toolkit & cảnh báo

**Phụ trách**
- `scripts/lib/common.sh`: log, `set -euo pipefail`, `trap` ERR/EXIT, hàm `usage`/`--help` dùng chung.
- `scripts/toolkit.sh`: menu CLI điều phối mọi công cụ, xử lý nhập sai.
- `deploy.sh`: test (`nginx -t`) → reload → xác nhận (curl) → **rollback** nếu lỗi.
- `healthcheck.sh`: CPU, RAM, disk, port, service so với ngưỡng cấu hình được; chạy trên VM1 **và** bản kiểm tra chéo từ VM2.
- `logrotate.sh`: xoay + nén log, giữ N thế hệ.
- Cảnh báo qua msmtp (Gmail 587).
- Đảm bảo **toàn bộ** `scripts/` qua `shellcheck` sạch (kể cả script của thành viên 4).

**Sở hữu**: `scripts/` (trừ backup/restore), cấu hình msmtp, timer health-check.

**Demo**: menu; deploy cấu hình cố tình lỗi → rollback; dừng một service → mail cảnh báo; chạy shellcheck trực tiếp.

**Báo cáo**: Tự động hóa + output shellcheck.

---

## 3. Ranh giới & phụ thuộc

```
              ┌──────────────── Dự: Terraform tạo máy ────────────────┐
              ▼                                                        │
     Dự: Ansible common/storage ─► TV4: PostgreSQL ─► TV3: Flask ─► TV2: Nginx/TLS
                                        │                                │
                                        └─► TV4: backup/restore ◄── TV5: toolkit/menu/alert
```

| Giao điểm | Bên giao | Bên nhận | Quy ước |
|---|---|---|---|
| IP, hostname, inventory | Dự | Tất cả | Output Terraform, `architecture.md` mục 4 |
| File cấu hình | TV2, TV3, TV4 | Dự (Ansible copy) | Nằm trong `config/`, chủ file review mọi thay đổi |
| Chuỗi kết nối DB, tên DB/role | TV4 | TV3, Dự (vault) | Không hard-code, đặt trong `EnvironmentFile` |
| `/health` | TV3 | Dự (NLB), TV5 (health-check) | Trả 200 khi app + DB OK |
| Backup/restore | TV4 viết logic | TV5 gắn menu, review shellcheck | Dùng chung `lib/common.sh` |

---

## 4. Tiến độ

| Giai đoạn | Việc | Ai |
|---|---|---|
| **0. Khởi động** | Xin GV chấp thuận AWS; tạo repo, AWS account, IAM user | Cả nhóm, Dự |
| **1. Nền móng** | Terraform bootstrap → `shared` (s3, iam) → `lab` (vpc, nacl, security-group, ec2 + Bastion) | Dự |
| | Viết Flask chạy local | TV3 |
| | Viết `lib/common.sh`, khung menu | TV5 |
| | Soạn sẵn file cấu hình nginx/ssh/ufw/postgres | TV2, TV4 |
| **2. Dựng dịch vụ** | Ansible roles common/storage → postgresql → app → nginx | Dự + chủ file |
| | NLB, siết SG/NACL | Dự |
| | UFW, SSH, fail2ban, auditd | TV2 |
| **3. Vận hành** | Backup/restore/S3/timer | TV4 |
| | Deploy/rollback, health-check, logrotate, alert | TV5 |
| | Lynis + khắc phục | TV2 |
| | Hoàn thiện Ansible (`toolkit`, `backup_target`), README tái tạo | Dự |
| **4. Hoàn thiện** | Báo cáo, tập demo 2–3 lần, hỏi chéo vấn đáp | Cả nhóm, TV3 ghép |

> Giai đoạn 1 của Dự là **đường găng** — các thành viên khác làm trên VM local trong lúc chờ.

---

## 5. Để ai cũng hiểu tổng thể

- **Review xoay vòng** (PR phải được người này duyệt): Dự → TV2 → TV3 → TV4 → TV5 → Dự. Người review phải giải thích lại được phần đã review.
- **Mỗi người soạn 5 câu hỏi khó** về phần mình → gom thành bộ luyện vấn đáp chung.
- **Ai cũng vẽ lại được** 2 luồng: request (Client → NLB → Nginx → Flask → PostgreSQL) và backup (VM1 → VM2 → S3).
- **Kịch bản demo 12–15 phút** (mục 8 của đề), mỗi người trình bày đúng phần mình:

| Phút | Nội dung | Người |
|---|---|---|
| 0–2 | Sơ đồ, hạ tầng, SG/NACL, SSH qua Bastion | Dự |
| 2–5 | End-to-end, systemd, kill app → tự khởi động lại | TV3 |
| 5–7 | 2 vhost, HTTPS, fail2ban ban, auditd | TV2 |
| 7–10 | `ss` DB localhost, backup → VM2/S3, xoá dữ liệu → restore | TV4 |
| 10–13 | Menu, deploy lỗi → rollback, health-check → mail, shellcheck | TV5 |

> Trước demo: bật NAT + NLB, chụp EBS snapshot/AMI trạng thái tốt (tương đương snapshot VM của đề).

---

## 6. Quy ước làm việc

- Git: mỗi người một nhánh `feat/<vai>-<việc>`, merge qua PR, không push thẳng `main`.
- Không commit bí mật (xem `architecture.md` mục 8).
- Thay đổi kiến trúc → cập nhật `architecture.md` mục 11 (nhật ký thay đổi).
