# Hướng dẫn SSH vào hệ thống lab (qua VPN WireGuard)

> Dành cho các thành viên nhóm. Không cần khai IP nhà nữa: bạn bật VPN WireGuard → SSH vào Bastion qua đường hầm → ProxyJump vào VM1/VM2.
> Kiến trúc mạng: `docs/architecture.md` mục 4 và 6. Phần cho người quản trị (Dự): [mục 6](#6-dành-cho-người-quản-trị-dự).

```
Máy bạn ──(WireGuard UDP 51820, mã hoá)──► Bastion 10.8.0.1 ──(SSH ProxyJump)──► VM1 10.0.2.10 / VM2 10.0.2.20
```

---

## 0. Tóm tắt — cần gửi gì?

Gửi cho **Dự** qua tin nhắn riêng (Zalo/Messenger), **không** commit lên repo:

```
Tên user Linux     : <vd: tran>       # chữ thường, không dấu, không khoảng trắng
SSH public key     : ssh-ed25519 AAAA... tran@linux-project
WireGuard pub key  : <44 ký tự, kết thúc bằng dấu =>
Hash mật khẩu sudo : $6$...           # CHỈ Trân (người có sudo đầy đủ) — xem mục 0.1
```

Dự gửi lại cho bạn: **IP VPN của bạn** (vd `10.8.0.3`), **public key của server**, **IP public của Bastion**.

### 0.1 Quyền của bạn trên từng máy

| Người | Bastion | VM1 `web-app-db-01` | VM2 `backup-01` |
|---|---|---|---|
| Dự, Trân | sudo đầy đủ (nhập mật khẩu) | sudo đầy đủ | sudo đầy đủ |
| Đăng (TV3) | chỉ đăng nhập (đi qua) | sudo giới hạn: `app.service` | — (không có user) |
| Duy (TV4) | chỉ đăng nhập | sudo giới hạn: PostgreSQL, backup/restore | sudo giới hạn: `s3-sync.service` |
| Hưng (TV5) | chỉ đăng nhập | sudo giới hạn: `nginx -t`, reload Nginx, deploy, logrotate, healthcheck, chạy backup (không restore) | sudo giới hạn: healthcheck |

- Xem đúng quyền của mình: `sudo -l`. Lệnh ngoài danh sách bị từ chối ngay và **được ghi log** (`/var/log/auth.log`).
- Lệnh phải gõ **đúng y** như trong `sudo -l` (đường dẫn, tham số). Đọc log/trạng thái **không cần sudo**: `systemctl status ...`, `journalctl -u ...`, `systemctl list-timers`.
- Thiếu lệnh cần cho phần việc của bạn → nhắn Dự (danh sách ở `ansible/roles/common/defaults/main.yml`, mục `common_sudo_profiles`). Muốn thử tự do thì dùng VM local.
- **Người có sudo đầy đủ** (Trân) tạo hash mật khẩu sudo — mật khẩu chỉ dùng cho `sudo`, SSH vẫn chỉ bằng key:
  ```bash
  openssl passwd -6        # nhập mật khẩu 2 lần → in ra $6$...  → gửi chuỗi này cho Dự (không gửi mật khẩu)
  ```
  Đổi mật khẩu = gửi hash mới cho Dự (đổi bằng `passwd` trên máy sẽ bị Ansible ghi đè lần chạy sau).

> ⚠️ Chỉ gửi **public key**. **Không bao giờ gửi** SSH private key (file không có đuôi `.pub`) hay WireGuard **PrivateKey** — ai có nó là vào được thay bạn.

---

## 1. Tạo SSH key

Đã có `~/.ssh/id_ed25519.pub` thì bỏ qua bước tạo.

**Linux / macOS / WSL**

```bash
ls ~/.ssh/id_ed25519.pub 2>/dev/null || ssh-keygen -t ed25519 -C "<ten-ban>@linux-project"
cat ~/.ssh/id_ed25519.pub
```

**Windows (PowerShell)** — cần OpenSSH Client (Settings → Apps → Optional features nếu chưa có)

```powershell
if (-not (Test-Path "$env:USERPROFILE\.ssh\id_ed25519.pub")) { ssh-keygen -t ed25519 -C "<ten-ban>@linux-project" }
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

Hỏi đường dẫn → Enter. Passphrase → nên đặt. Copy **nguyên một dòng** bắt đầu bằng `ssh-ed25519`.

---

## 2. Cài WireGuard và tạo WireGuard key

### Windows / macOS

1. Tải app tại <https://www.wireguard.com/install/> (macOS: App Store).
2. Mở app → **Add Tunnel** (mũi tên cạnh nút) → **Add empty tunnel…**
3. Đặt tên `linux-project`. App tự tạo sẵn dòng `PrivateKey = ...` và hiện **Public key** ở phía trên.
4. Copy **Public key** gửi Dự. Để cửa sổ đó mở (hoặc Save) — bước 3 sẽ dán phần còn lại.

### Linux

```bash
sudo apt install wireguard-tools      # Fedora: sudo dnf install wireguard-tools
sudo sh -c 'umask 077; wg genkey > /etc/wireguard/linux-project.key'
sudo cat /etc/wireguard/linux-project.key | wg pubkey
```

Dòng in ra là **public key** → gửi Dự. Private key nằm ở `/etc/wireguard/linux-project.key` (chỉ root đọc được), không cần copy đi đâu.

---

## 3. Cấu hình VPN (sau khi Dự gửi lại thông tin)

Nội dung tunnel (Windows/macOS: sửa trong app; Linux: file `/etc/wireguard/linux-project.conf`, quyền `600`):

```ini
[Interface]
PrivateKey = <PRIVATE KEY CỦA BẠN>          # app tự điền; Linux: sudo cat /etc/wireguard/linux-project.key
Address    = <IP VPN Dự cấp>/32              # vd 10.8.0.3/32

[Peer]
PublicKey           = <PUBLIC KEY CỦA SERVER>   # Dự gửi
Endpoint            = <IP PUBLIC BASTION>:51820 # Dự gửi
AllowedIPs          = 10.8.0.1/32               # CHỈ đi VPN khi tới Bastion, internet vẫn đi đường thường
PersistentKeepalive = 25                        # giữ kết nối khi ngồi sau NAT/wifi
```

> **Không** thêm `DNS = ...` và **không** đổi `AllowedIPs` thành `0.0.0.0/0` — VPN này chỉ để vào Bastion, không phải để ra internet.

> **Linux: file config phải nằm trong `/etc/wireguard/`.** Ubuntu bản mới có AppArmor profile cho `wg-quick`, chỉ cho đọc config trong thư mục này — để ở `~/` thì `sudo wg-quick up ~/...conf` báo `Permission denied` dù chạy bằng root (`journalctl -k | grep DENIED` sẽ thấy `profile="wg-quick"`). Lỡ tạo ở home thì chuyển vào:
> ```bash
> sudo install -m 600 -o root -g root ~/linux-project.conf /etc/wireguard/linux-project.conf && rm ~/linux-project.conf
> ```

Bật VPN:
- **Windows/macOS:** bấm **Activate**.
- **Linux:** `sudo wg-quick up linux-project` (tắt: `sudo wg-quick down linux-project`; xem trạng thái: `sudo wg show`).

Kiểm tra: `ping 10.8.0.1` có trả lời là VPN đã lên.

---

## 4. Cấu hình SSH và kết nối

Thêm vào `~/.ssh/config` (Windows: `C:\Users\<bạn>\.ssh\config`, không có đuôi `.txt`):

```
# ===== linux-project (AWS lab) — bật VPN trước =====
Host lp-bastion
    HostName 10.8.0.1

Host lp-web1
    HostName 10.0.2.10
    ProxyJump lp-bastion

Host lp-backup
    HostName 10.0.2.20
    ProxyJump lp-bastion

# Thiết lập chung cho cả 3 máy
Host lp-*
    User <ten-user-cua-ban>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

```bash
ssh lp-bastion   # Bastion
ssh lp-web1      # VM1 web-app-db-01, đi xuyên Bastion
ssh lp-backup    # VM2 backup-01
```

Lần đầu hỏi `continue connecting (yes/no)?` → `yes`.

- `IdentitiesOnly yes`: chỉ thử đúng key đã khai — máy có nhiều key thì không bị `Too many authentication failures`.
- **Nên dùng file config thay vì gõ `-J` trên dòng lệnh.** `ssh -i <key> -J user@10.8.0.1 user@10.0.2.10` sẽ lỗi `Permission denied` **ở Bastion**: `-i` chỉ áp cho máy đích, bước nhảy qua Bastion là một kết nối riêng không nhận `-i`. Với file config, `ProxyJump lp-bastion` đọc khối `lp-bastion`/`lp-*` nên lấy đúng key.

**Kiểm tra đúng là đi qua VPN:** trong Bastion chạy `echo $SSH_CLIENT` → phải bắt đầu bằng IP VPN của bạn (`10.8.0.x`).

---

## 5. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `ping 10.8.0.1` không trả lời, app báo không có "handshake" | Sai key / sai Endpoint, Dự chưa thêm bạn, lab đang tắt, hoặc **mạng chặn UDP** (wifi trường/công ty) | Kiểm tra lại 3 thông tin Dự gửi; hỏi Dự lab có bật không; thử phát 4G từ điện thoại |
| `sudo wg-quick up ~/...conf` → `Permission denied` | AppArmor chỉ cho `wg-quick` đọc `/etc/wireguard/` | Chuyển file vào `/etc/wireguard/` (mục 3) |
| `ssh lp-bastion` → `Connection timed out` | Chưa bật VPN | Bật VPN, `ping 10.8.0.1` trước |
| `ssh lp-web1` → timeout sau khi vào Bastion được | VM1/VM2 đang **stopped** (nhóm tắt máy cho đỡ tốn tiền) | Hỏi Dự bật máy |
| `Permission denied (publickey)` ở `10.8.0.1` khi dùng `-J` | `-i` không áp cho bước nhảy | Dùng `~/.ssh/config` (mục 4) |
| `Permission denied (publickey)` | Sai tên user / key, hoặc user chưa được tạo | Kiểm tra `User`, `IdentityFile`; `ssh -v lp-bastion` xem đang dùng key nào |
| `UNPROTECTED PRIVATE KEY FILE` | Quyền file key quá rộng | `chmod 600 ~/.ssh/id_ed25519` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Lab bị dựng lại, máy mới có host key mới | `ssh-keygen -R 10.8.0.1` (và `10.0.2.10`, `10.0.2.20`) rồi SSH lại |
| Lab dựng lại xong VPN không lên | Bastion đổi IP public | Hỏi Dự IP mới, sửa `Endpoint` |

---

## 6. Dành cho người quản trị (Dự)

### 6.1 Đã có sẵn (thiết lập 2026-11-05)

| Thứ | Ở đâu | Ghi chú |
|---|---|---|
| Private key server | `ansible/group_vars/bastion/vault.yml` (ansible-vault, **được commit**) | Public key server: `jt9/kRg6hBAzkEv1vzPj2WcCeglqLJoztuVTcBnS5g0=` |
| Mật khẩu vault | `~/.ansible/linux-project.vault_pass` trên máy Dự (quyền 600, **ngoài repo**) | **Sao lưu file này** — mất là không mở được vault, phải tạo key server mới và cả nhóm sửa lại config |
| Config VPN của Dự | `/etc/wireguard/linux-project.conf` (IP `10.8.0.2`) | |
| Danh sách thành viên | `ansible/group_vars/all/members.yml` | Nguồn duy nhất: user, SSH key, quyền theo máy, peer VPN |
| Hash mật khẩu sudo | `ansible/group_vars/all/vault.yml` (ansible-vault) | `vault_sudo_password_hashes: { du: "$6$...", tran: "$6$..." }` |
| SSH config của Dự | `~/.ssh/config`: `lp-bastion` (VPN), `lp-bastion-direct` (IP public, dự phòng), `lp-web1`, `lp-backup` | User `ubuntu` + `linux-project-key.pem` |

Key server nằm trong vault nên **dựng lại lab không đổi key** — thành viên chỉ phải sửa `Endpoint` nếu IP Bastion đổi.

Làm lại từ đầu (mất vault): `wg genkey` → `ansible-vault create group_vars/bastion/vault.yml` với nội dung `vault_wireguard_server_private_key: "<key>"`.

### 6.2 Thêm / bớt thành viên

1. Bastion phải đang **running** (nhóm hay tắt máy cho đỡ tốn tiền):

   ```bash
   aws ec2 describe-instances --region ap-southeast-1 --filters "Name=tag:Project,Values=linux-project" \
     --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name,InstanceId]' --output text
   aws ec2 start-instances --region ap-southeast-1 --instance-ids <id>
   ```
2. **Thêm người:** sửa `ansible/group_vars/all/members.yml` — bỏ comment khối của họ, điền `ssh_key`, `wireguard: { ip, public_key }` (IP không trùng), kiểm tra `access`. Người có `full` thì thêm hash vào vault:

   ```bash
   cd ansible && ansible-vault edit group_vars/all/vault.yml --vault-password-file ~/.ansible/linux-project.vault_pass
   ```

   Chưa có hash → user vẫn được tạo nhưng **tạm không có sudo** (playbook in cảnh báo).

   **Gỡ người:** xoá họ khỏi `members`, ghi tên vào `removed_members` → gỡ user + home + sudoers trên mọi máy, peer VPN tự mất.

   **Đổi quyền:** sửa `access` của họ, hoặc danh sách lệnh trong `common_sudo_profiles` (`roles/common/defaults/main.yml`). Không thêm editor/pager/`systemctl edit`/`tar`/`rsync`/`find` — đều thoát ra được shell root.
3. Chạy (nên `--check --diff` trước):

   ```bash
   cd ansible && ansible-playbook site.yml --vault-password-file ~/.ansible/linux-project.vault_pass
   ```

   Task cuối in **Server public key** → gửi cho thành viên cùng IP VPN của họ và `bastion_public_ip` (`terraform -chdir=../terraform/environments/lab output -raw bastion_public_ip`).
4. Kiểm tra: `ssh lp-web1 'sudo -l -U <user>'`.

**Không** tạo user / sửa `/etc/sudoers.d/` bằng tay — lần chạy sau Ansible ghi đè (`authorized_keys` cũng độc quyền: key không có trong `members.yml` bị gỡ).

Reload dùng `wg syncconf` nên thêm người **không** làm rớt kết nối của người đang dùng.

### 6.3 `admin_cidrs` — Ansible + đường dự phòng

`admin_cidrs` (Terraform, `terraform.tfvars`) cho SSH **thẳng** vào IP public của Bastion. Vẫn cần vì:

- **Ansible đi đường này**: `inventory/hosts.ini` do Terraform sinh ra trỏ IP public của Bastion — lần cài WireGuard đầu tiên chưa có VPN để đi. IP mạng đang ngồi không nằm trong `admin_cidrs` thì playbook báo timeout → thêm dải `/16` của mạng đó rồi `terraform apply`.
- **Dự phòng** khi WireGuard hỏng: `ssh lp-bastion-direct`.

Kiểm tra VPN trên Bastion: `sudo wg show` (mỗi peer có `latest handshake` là đang kết nối).
