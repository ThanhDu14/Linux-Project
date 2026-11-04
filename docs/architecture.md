# Kiến trúc hệ thống — Đồ án Linux trên AWS

> Trạng thái: **Bản chốt v1** — cập nhật khi có thay đổi, ghi vào mục [Nhật ký thay đổi](#11-nhật-ký-thay-đổi).
> Chủ sở hữu tài liệu: Dự (Hạ tầng). Mọi thay đổi kiến trúc phải mở PR và được cả nhóm duyệt.

---

## 1. Tóm tắt

Hệ thống hiện thực đề "Đồ án thực hành Linux" (xem `docs/Do_An_Thuc_Hanh_Linux.pdf`) trên **AWS EC2** thay cho VirtualBox/VMware, giữ nguyên toàn bộ yêu cầu của đề:

- **Web → App → DB** là 3 tầng **logic** trên cùng một máy (VM1): Nginx `proxy_pass` tới cổng cục bộ của Flask, PostgreSQL chỉ nghe `127.0.0.1`.
- **3 lớp mạng**: Internet → public subnet (NLB, NAT, Bastion) → private subnet (VM1, VM2).
- **VM2** là máy nhận bản sao lưu (rsync), có thêm bản sao off-site trên **S3**.
- **3 lớp tường lửa**: NACL (subnet) → Security Group (instance) → UFW (hệ điều hành).
- **3 lớp công cụ**: Terraform (tạo hạ tầng) → Ansible (cài & cấu hình) → Bash toolkit (vận hành hằng ngày).

> ⚠️ **Việc cần làm trước**: xin giảng viên chấp thuận dùng AWS EC2 thay VirtualBox/VMware (mục 1.1 của đề).

---

## 2. Các quyết định đã chốt

| # | Quyết định | Lý do | Phương án đã loại |
|---|---|---|---|
| D1 | Chạy trên AWS EC2, Ubuntu 22.04 LTS | Mong muốn của nhóm, sát thực tế nghề nghiệp | VirtualBox/VMware (vẫn là phương án dự phòng) |
| D2 | **1 VPC**, 1 public subnet + 1 private subnet, 1 AZ | Đơn giản, đủ phân tách bằng subnet + SG; cả 5 người nắm được | 2 VPC + Transit Gateway/Peering (đắt, phức tạp, không cộng điểm) |
| D3 | Nginx + Flask + PostgreSQL **cùng trên VM1** | Đề bắt buộc `proxy_pass` tới cổng cục bộ và DB chỉ nghe localhost | Tách 3 tầng máy / RDS (lệch đề mục 3.2, 4.1) |
| D4 | **NLB** (TCP passthrough) ở public subnet đưa Internet vào VM1 | Chỉ cần 1 subnet; Nginx tự xử lý TLS tự ký (đúng mục 6); giữ IP thật của client cho log/fail2ban | ALB (bắt buộc 2 AZ, phải đưa cert vào ACM, mất IP client) |
| D5 | **NAT Gateway**, bật/tắt bằng biến Terraform `enable_nat` | Do AWS quản lý, tin cậy; tắt khi không dùng nên chi phí thấp | NAT instance trên Bastion |
| D6 | **Bastion** là cửa SSH duy nhất (ProxyJump) | Đúng gợi ý mục 3.2 của đề; VM1/VM2 không có IP public | SSH trực tiếp / SSM Session Manager |
| D7 | Backup: VM1 **push** rsync sang VM2 bằng key bị giới hạn (`rrsync`), VM2 đẩy tiếp lên **S3** | Đúng đề (rsync sang VM thứ hai) + off-site 3-2-1; key giới hạn chống xoá backup nếu VM1 bị chiếm | Push không giới hạn key; chỉ dùng S3 |
| D8 | Health-check chạy trên VM1 **và** từ VM2 kiểm tra chéo sang VM1 | VM1 treo hẳn thì vẫn có cảnh báo | Chỉ tự kiểm tra trên VM1 |
| D9 | Terraform theo khuôn repo NT548: **bootstrap + modules (theo dịch vụ AWS) + environments (`shared`, `lab`)**, partial backend; Ansible chia **roles + site + inventory** | Tái sử dụng, dễ review; `shared` giữ backup S3 khi destroy `lab`; nhóm đã quen khuôn này | Một file Terraform/playbook phẳng; 1 môi trường duy nhất |
| D10 | Region đề xuất **`ap-southeast-1` (Singapore)** — là biến, có thể đổi | Gần Việt Nam, độ trễ thấp | `us-east-1` (rẻ hơn chút) |

**Không phải HA.** Hệ thống chạy trong 1 AZ, VM1 là điểm lỗi đơn. Đây là đánh đổi có chủ đích để đúng đề và tiết kiệm chi phí. Hướng mở rộng xem [mục 10](#10-giới-hạn-đã-biết--hướng-mở-rộng).

---

## 3. Sơ đồ tổng thể

```
                            Internet
                 (người dùng)        (nhóm: SSH từ IP cho phép)
                      │                      │
                ┌─────┴──────────────────────┴─────┐
                │        Internet Gateway          │
                └─────┬──────────────────────┬─────┘
VPC 10.0.0.0/16       │                      │
┌─────────────────────┼──────────────────────┼─────────────────────────┐
│ Public subnet 10.0.1.0/24 — ap-southeast-1a   (rt-public)            │
│                     │                      │                         │
│  ┌──────────────┐ ┌─┴────────────┐ ┌───────┴───────┐                 │
│  │ NAT Gateway  │ │     NLB      │ │  bastion-01   │                 │
│  │ (Elastic IP) │ │ TCP 80, 443  │ │  10.0.1.10    │                 │
│  └──────▲───────┘ └─┬────────────┘ │ sshd,fail2ban │                 │
│         │ ra ngoài  │              └───────┬───────┘                 │
│─────────┼───────────┼──────────────────────┼─────────────────────────│
│ Private subnet 10.0.2.0/24 — ap-southeast-1a  (rt-private)           │
│         │           │ 80/443               │ SSH ProxyJump           │
│  ┌──────┴───────────▼──────────────────────▼─┐     ┌───────────────┐ │
│  │ web-app-db-01            10.0.2.10        │     │ backup-01     │ │
│  │ ┌───────────────────────────────────────┐ │rsync│ 10.0.2.20     │ │
│  │ │ Nginx :80 (301) / :443 TLS, ≥2 vhost  │ ├────►│ /backup (EBS) │ │
│  │ │   └► Flask (systemd) 127.0.0.1:5000   │ │ SSH │ retention     │ │
│  │ │        └► PostgreSQL   127.0.0.1:5432 │ │     │ health-check  │ │
│  │ └───────────────────────────────────────┘ │◄────┤ chéo → VM1    │ │
│  │ EBS /data (fstab): pgdata, web content    │ 443 └───────┬───────┘ │
│  └───────────────────────────────────────────┘             │         │
│                                         S3 Gateway Endpoint│         │
└────────────────────────────────────────────────────────────┼─────────┘
                                                             ▼
                                              S3 bucket backup (lifecycle)
```

---

## 4. Quy hoạch tài nguyên

### 4.1 Mạng

| Thành phần | Giá trị |
|---|---|
| Region / AZ | `ap-southeast-1` / `ap-southeast-1a` (biến) |
| VPC | `10.0.0.0/16` |
| Public subnet | `10.0.1.0/24` |
| Private subnet | `10.0.2.0/24` |
| DNS nội bộ VPC | `10.0.0.2` (Amazon DNS) |

### 4.2 Máy chủ

| Hostname | Subnet | IP private | Loại (đề xuất) | Ổ dữ liệu | Vai trò |
|---|---|---|---|---|---|
| `bastion-01` | public | `10.0.1.10` + IP public | t3.micro | — | Cửa SSH duy nhất |
| `web-app-db-01` (VM1) | private | `10.0.2.10` | t3.small | EBS gp3 10 GB → `/data` | Nginx, Flask, PostgreSQL |
| `backup-01` (VM2) | private | `10.0.2.20` | t3.micro | EBS gp3 20 GB → `/backup` | Nhận backup, đẩy S3, health-check chéo |

Mọi máy: Ubuntu 22.04 LTS, user quản trị non-root có sudo, đăng nhập bằng khoá, mount EBS qua `/etc/fstab` (dùng `UUID=`, có `nofail`).

### 4.3 Dịch vụ & cổng

| Dịch vụ | Máy | Lắng nghe | Ai được truy cập |
|---|---|---|---|
| sshd | cả 3 | `0.0.0.0:22` | Bastion: IP nhóm; VM1/VM2: từ Bastion (VM2 thêm từ VM1) |
| Nginx | VM1 | `0.0.0.0:80`, `0.0.0.0:443` | Từ NLB (và VM2 cho health-check) |
| Flask (gunicorn) | VM1 | `127.0.0.1:5000` | Chỉ Nginx trên cùng máy |
| PostgreSQL | VM1 | `127.0.0.1:5432` | Chỉ Flask và script backup trên cùng máy |

### 4.4 Virtual host trên Nginx

| Vhost | Nội dung |
|---|---|
| `app.lab.local` | Reverse proxy tới Flask (endpoint đọc/ghi, `/health`) |
| `status.lab.local` | Trang trạng thái tĩnh |

Truy cập khi không có domain thật: `curl -k -H "Host: app.lab.local" https://<nlb-dns-name>`.

---

## 5. Route table

Hai subnet trong cùng VPC **tự thấy nhau** nhờ route `local` (AWS tạo sẵn, không xoá được). Route table chỉ quyết định **traffic ra ngoài VPC đi đường nào**. Ai được nói chuyện với ai do SG/NACL quyết định.

| Route table | Gắn vào | Destination | Target |
|---|---|---|---|
| `rt-public` | Public subnet | `10.0.0.0/16` | local |
| | | `0.0.0.0/0` | Internet Gateway |
| `rt-private` | Private subnet | `10.0.0.0/16` | local |
| | | `0.0.0.0/0` | NAT Gateway (chỉ khi `enable_nat = true`) |
| | | prefix list S3 | S3 Gateway Endpoint |

---

## 6. Tường lửa 3 lớp

### 6.1 So sánh

| | NACL | Security Group | UFW |
|---|---|---|---|
| Phạm vi | Ranh giới subnet | Từng ENI/instance | Trong hệ điều hành |
| Trạng thái | Stateless (phải mở chiều về) | Stateful | Stateful |
| Allow / Deny | Cả hai | Chỉ Allow | Cả hai |
| Tham chiếu | Chỉ CIDR | CIDR hoặc SG khác | IP/CIDR |
| Vai trò | Chặn thô ở biên, chặn dải IP xấu | Kiểm soát chính, chi tiết | Yêu cầu bắt buộc của đề, phòng thủ chiều sâu |

### 6.2 Security Group

**`sg-nlb`** (gắn vào NLB)

| Chiều | Port | Nguồn/Đích | Lý do |
|---|---|---|---|
| In | 80, 443 | `0.0.0.0/0` | Người dùng truy cập web |
| Out | 80, 443 | `sg-vm1` | Chuyển traffic + health check tới VM1 |

**`sg-bastion`**

| Chiều | Port | Nguồn/Đích | Lý do |
|---|---|---|---|
| In | 22 | `<IP nhóm>/32` (biến `admin_cidrs`) | Chỉ nhóm SSH vào |
| Out | 22 | `sg-vm1`, `sg-vm2` | ProxyJump |
| Out | 80, 443 | `0.0.0.0/0` | apt |
| Out | 587 | `0.0.0.0/0` | Mail cảnh báo |

**`sg-vm1`** (web-app-db-01)

| Chiều | Port | Nguồn/Đích | Lý do |
|---|---|---|---|
| In | 80, 443 | `sg-nlb` | Chỉ nhận web từ NLB |
| In | 443 | `sg-vm2` | Health-check chéo từ VM2 |
| In | 22 | `sg-bastion` | Quản trị |
| Out | 22 | `sg-vm2` | rsync backup |
| Out | 80, 443 | `0.0.0.0/0` | apt, pip (qua NAT) |
| Out | 587 | `0.0.0.0/0` | msmtp cảnh báo |

**`sg-vm2`** (backup-01)

| Chiều | Port | Nguồn/Đích | Lý do |
|---|---|---|---|
| In | 22 | `sg-bastion`, `sg-vm1` | Quản trị + nhận rsync |
| Out | 443 | `sg-vm1` | Health-check chéo |
| Out | 80, 443 | `0.0.0.0/0` | apt (qua NAT), S3 (qua endpoint) |
| Out | 587 | `0.0.0.0/0` | msmtp cảnh báo |

> Cổng 5000 (Flask) và 5432 (PostgreSQL) **không xuất hiện trong bất kỳ SG nào** — cả hai chỉ nghe localhost.

### 6.3 Network ACL

Dải ephemeral dùng chung: **1024–65535** (Linux dùng 32768–60999; NLB/NAT Gateway dùng 1024–65535).

**`nacl-public`** (10.0.1.0/24)

| # | Chiều | Proto/Port | Nguồn/Đích | Hành động | Lý do |
|---|---|---|---|---|---|
| 50 | In | ALL | `<dải IP xấu>` | DENY | Chặn ở biên (SG không làm được) — thêm khi cần |
| 100 | In | TCP 80 | `0.0.0.0/0` | ALLOW | Web vào NLB; NAT nhận traffic từ private |
| 110 | In | TCP 443 | `0.0.0.0/0` | ALLOW | như trên |
| 120 | In | TCP 22 | `<IP nhóm>/32` | ALLOW | SSH vào Bastion |
| 130 | In | TCP 587 | `10.0.2.0/24` | ALLOW | NAT nhận mail từ VM1/VM2 |
| 140 | In | TCP 1024–65535 | `0.0.0.0/0` | ALLOW | Traffic trả về |
| * | In | ALL | `0.0.0.0/0` | DENY | |
| 100 | Out | TCP 80 | `0.0.0.0/0` | ALLOW | NLB → VM1, NAT/Bastion → Internet |
| 110 | Out | TCP 443 | `0.0.0.0/0` | ALLOW | như trên |
| 120 | Out | TCP 587 | `0.0.0.0/0` | ALLOW | NAT chuyển mail ra ngoài |
| 130 | Out | TCP 22 | `10.0.2.0/24` | ALLOW | Bastion → VM1/VM2 |
| 140 | Out | TCP 1024–65535 | `0.0.0.0/0` | ALLOW | Trả lời người dùng, nhóm; NAT trả về private |
| * | Out | ALL | `0.0.0.0/0` | DENY | |

**`nacl-private`** (10.0.2.0/24)

| # | Chiều | Proto/Port | Nguồn/Đích | Hành động | Lý do |
|---|---|---|---|---|---|
| 100 | In | TCP 80 | `0.0.0.0/0` | ALLOW | Web qua NLB (xem lưu ý 1) |
| 110 | In | TCP 443 | `0.0.0.0/0` | ALLOW | như trên |
| 120 | In | TCP 22 | `10.0.1.0/24` | ALLOW | SSH từ Bastion |
| 130 | In | TCP 1024–65535 | `0.0.0.0/0` | ALLOW | Traffic trả về (apt, mail, S3) |
| * | In | ALL | `0.0.0.0/0` | DENY | |
| 100 | Out | TCP 80 | `0.0.0.0/0` | ALLOW | apt |
| 110 | Out | TCP 443 | `0.0.0.0/0` | ALLOW | apt, pip, S3 |
| 120 | Out | TCP 587 | `0.0.0.0/0` | ALLOW | msmtp |
| 130 | Out | TCP 1024–65535 | `0.0.0.0/0` | ALLOW | Trả lời người dùng (qua NLB) và Bastion |
| * | Out | ALL | `0.0.0.0/0` | DENY | |

### 6.4 Những điểm dễ sai

1. **NLB giữ IP thật của client** → gói tin tới VM1 có IP nguồn là IP người dùng, nên `nacl-private` phải mở 80/443 từ `0.0.0.0/0`. Lớp chặn thật là `sg-vm1` (chỉ nhận từ `sg-nlb`).
2. **NACL không lọc traffic trong cùng subnet** → rsync và health-check giữa VM1 ↔ VM2 chỉ do SG + UFW kiểm soát.
3. **Không bị SG/NACL lọc**: Amazon DNS (`10.0.0.2`), metadata (`169.254.169.254`), Time Sync (`169.254.169.123`).
4. **Hairpin NLB**: VM1 gọi chính DNS của NLB sẽ timeout. Script trên VM1 phải kiểm tra qua `https://127.0.0.1` kèm header `Host`.

### 6.5 UFW (trên từng máy)

| Máy | Mặc định | Cho phép vào |
|---|---|---|
| bastion-01 | deny incoming, allow outgoing | 22/tcp |
| web-app-db-01 | deny incoming, allow outgoing | 22/tcp từ `10.0.1.10`; 80, 443/tcp |
| backup-01 | deny incoming, allow outgoing | 22/tcp từ `10.0.1.10` và `10.0.2.10` |

---

## 7. Luồng dữ liệu

**Người dùng**
```
Client ─HTTPS 443─► IGW ─► NLB ─► Nginx (VM1, giải mã TLS)
       ─proxy_pass 127.0.0.1:5000─► Flask ─127.0.0.1:5432─► PostgreSQL
Client ─HTTP 80─► ... ─► Nginx trả 301 → https://
```

**Quản trị**
```
Máy nhóm ─SSH─► Bastion ─ProxyJump─► VM1 / VM2
```

**Sao lưu** (systemd timer, 02:00 hằng ngày)
```
VM1: pg_dump + tar /data/www ─► nén .tar.gz gắn timestamp ─► kiểm tra dung lượng đĩa
   ─rsync (key giới hạn rrsync)─► VM2:/backup/incoming
VM2: áp retention (xoá > 7 ngày) ─► aws s3 sync qua Gateway Endpoint ─► S3 (lifecycle xoá > 30 ngày)
```

**Giám sát & cảnh báo**
```
VM1: health-check (CPU/RAM/disk/port/service) mỗi 5 phút ─► vượt ngưỡng ─► log + msmtp ─► NAT ─► SMTP 587
VM2: curl https://10.0.2.10/health (Host: app.lab.local) ─► lỗi ─► msmtp cảnh báo
```

**Đi ra Internet** (chỉ khi `enable_nat = true`)
```
VM1/VM2 ─► rt-private ─► NAT Gateway ─► IGW ─► Internet (apt, pip, SMTP)
```

---

## 8. Phân lớp công cụ & cấu trúc repo

```
Terraform    → TẠO hạ tầng       : VPC, subnet, RT, NAT, NLB, SG, NACL, EC2, EBS, S3, IAM
Ansible      → CÀI & CẤU HÌNH    : package, user, hostname, fstab, copy file từ config/, bật service
Bash toolkit → VẬN HÀNH hằng ngày: deploy/rollback, backup/restore, health-check, xoay log, cảnh báo
```

```
linux-project/
├── terraform/                     # Terraform — Dự (cùng khuôn với repo NT548)
│   ├── bootstrap/                 # main.tf, variables.tf, outputs.tf — S3 bucket chứa tfstate (state local, chạy 1 lần)
│   ├── modules/                   # đặt tên theo dịch vụ AWS, mỗi module: main.tf / variables.tf / outputs.tf
│   │   ├── vpc/                   # VPC, 2 subnet, IGW, NAT Gateway (enable_nat), route table, S3 Gateway Endpoint
│   │   ├── nacl/                  # nacl-public, nacl-private
│   │   ├── security-group/        # sg-nlb, sg-bastion, sg-vm1, sg-vm2
│   │   ├── ec2/                   # 1 instance + EBS data (gọi 3 lần: bastion, vm1, vm2)
│   │   ├── nlb/                   # NLB (enable_nlb), listener 80/443, target group, health check
│   │   ├── s3/                    # bucket backup + versioning, mã hoá, chặn public, lifecycle
│   │   └── iam/                   # role + instance profile cho VM2 ghi S3
│   └── environments/
│       ├── shared/                # TÀI NGUYÊN SỐNG LÂU: s3 backup, iam — không destroy hằng ngày
│       │   └── backend.tf main.tf variables.tf outputs.tf terraform.tfvars.example
│       └── lab/                   # TÀI NGUYÊN DỰNG/HUỶ: vpc, nacl, sg, ec2, nlb
│           └── backend.tf main.tf variables.tf outputs.tf inventory.tf terraform.tfvars.example
├── .checkov.yml                   # quét bảo mật Terraform; mọi ngoại lệ ghi `# checkov:skip=... "lý do"`
├── ansible/                       # Ansible — Dự
│   ├── ansible.cfg
│   ├── site.yml
│   ├── inventory/
│   │   ├── hosts.ini              # Terraform sinh ra (gitignored)
│   │   └── group_vars/            # all, private, web, backup, vault
│   └── roles/                     # common, storage, ssh_hardening, firewall, fail2ban, auditd,
│                                  # nginx, postgresql, app, backup_target, toolkit
├── config/                        # File cấu hình THẬT — nguồn duy nhất, role chỉ copy
│   ├── nginx/  ssh/  ufw/  fail2ban/  audit/     # Thành viên 2
│   ├── systemd/                                  # Thành viên 3
│   └── postgresql/                               # Thành viên 4
├── app/                           # Flask — Thành viên 3
├── scripts/                       # Bash toolkit — Thành viên 4, 5
└── docs/                          # architecture.md, team.md, báo cáo
```

**Quy ước Terraform (theo NT548)**

| Quy ước | Cách làm |
|---|---|
| Phiên bản | `required_version >= 1.5.0`, provider `hashicorp/aws ~> 5.0` |
| State bucket | `<project>-terraform-state-<account_id>`, versioning + AES256 + chặn public + `prevent_destroy` |
| Backend | **Partial config**: `backend.tf` chỉ ghi `key`, `encrypt = true`, `use_lockfile = true`; `bucket` và `region` truyền qua `-backend-config` khi `init` (không hard-code account ID) |
| Key state | `shared/terraform.tfstate`, `lab/terraform.tfstate` |
| Liên kết môi trường | `lab` đọc output của `shared` qua `data "terraform_remote_state" "shared"` |
| `backend.tf` | Chứa khối `terraform {}` + `provider "aws"` |
| `main.tf` của môi trường | Gọi module theo thứ tự, mỗi khối có comment đánh số `# 1. VPC Module` |
| Tag | `Name = "${var.project_name}-<tên>"`, `Project`, `Environment` |
| Biến | Luôn có `type` + `description`; giá trị thật trong `terraform.tfvars` (gitignored), mẫu trong `terraform.tfvars.example` |

**Vì sao tách `shared` và `lab`:** `terraform destroy` môi trường `lab` để tiết kiệm chi phí **không làm mất bản backup trên S3** và IAM role. Khi dựng lại `lab`, VM2 gắn lại đúng instance profile cũ và đọc được backup cũ để restore.

**Tái tạo toàn bộ hệ thống:**
```bash
# Lần đầu (1 lần duy nhất cho mỗi tài khoản AWS)
terraform -chdir=terraform/bootstrap init && terraform -chdir=terraform/bootstrap apply

# Mỗi môi trường: init với partial backend rồi apply (shared trước, lab sau)
for env in shared lab; do
  terraform -chdir=terraform/environments/$env init -reconfigure \
    -backend-config="bucket=${STATE_BUCKET}" -backend-config="region=${AWS_REGION}"
  terraform -chdir=terraform/environments/$env apply
done

ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --ask-vault-pass
./scripts/toolkit.sh deploy
```

Các script hỗ trợ Terraform (nếu có) đặt trong `terraform/scripts/`, **không** để trong `scripts/`, vì `scripts/` là bộ Bash toolkit được chấm điểm và phải qua shellcheck.

**Không commit:** `*.tfstate*`, `*.tfvars` (trừ `.example`), `.terraform/`, private key, `.env`, `ansible/inventory/hosts.ini`, file vault chưa mã hoá.

---

## 9. Chi phí & bật/tắt

| Thành phần | Đơn giá (ước tính, Singapore) | Biến điều khiển |
|---|---|---|
| NAT Gateway | ~0.059 USD/giờ + 0.059 USD/GB | `enable_nat` |
| NLB | ~0.025 USD/giờ + LCU | `enable_nlb` |
| EC2 (1× t3.small + 2× t3.micro) | ~0.05 USD/giờ tổng | stop khi không dùng |
| EBS gp3 30 GB | ~2.9 USD/tháng (tính cả khi stop) | — |
| IPv4 public (Bastion, NAT, NLB) | 0.005 USD/giờ mỗi IP | đi theo thành phần |
| S3 | gần như 0 với dung lượng backup nhỏ | — |

**Khi tắt NAT** (`enable_nat = false`): web, SSH, backup lên S3 vẫn chạy; **không** chạy được apt/pip/Ansible cài package và **không gửi được mail cảnh báo** → bật NAT trước khi làm việc và trước buổi demo.

Thiết lập **AWS Budget** cảnh báo khi vượt ngưỡng (ví dụ 10 USD).

---

## 10. Giới hạn đã biết & hướng mở rộng

| Giới hạn | Ảnh hưởng | Hướng mở rộng |
|---|---|---|
| 1 AZ, VM1 là điểm lỗi đơn | VM1/AZ sự cố → web ngừng | Thêm subnet AZ-b, VM1-b, PostgreSQL streaming replication qua SSH tunnel, NLB health check theo `pg_is_in_recovery()` |
| VM2 cùng AZ với VM1 | AZ sự cố → mất cả bản gốc và bản sao trên VM2 | Đã giảm thiểu bằng S3 (đa AZ) |
| Bastion là điểm lỗi đơn cho quản trị | Không SSH được, web không ảnh hưởng | Dự phòng bằng SSM Session Manager |
| Chứng chỉ TLS tự ký | Trình duyệt cảnh báo | Có domain thật → Let's Encrypt (hệ thống đã ra Internet) |
| Replication ≠ backup | — | Luôn giữ `pg_dump` + retention, kể cả khi thêm replication |

---

## 11. Nhật ký thay đổi

| Ngày | Phiên bản | Thay đổi | Người |
|---|---|---|---|
| 2026-11-03 | v1 | Bản chốt đầu tiên | Dự |
| 2026-11-03 | v1.1 | Terraform đổi sang khuôn NT548: `terraform/{bootstrap,modules,environments/{shared,lab}}`, module theo dịch vụ AWS, partial backend, checkov | Dự |
