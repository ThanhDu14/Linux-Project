# Trân ơi, gửi Dự 3 thứ này để có tài khoản trên server

Gửi qua **tin nhắn riêng** (Zalo/Messenger), không commit lên repo. Làm mất khoảng 10 phút.

```
1. SSH public key   : ssh-ed25519 AAAA... tran@linux-project
2. WireGuard pubkey : xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
3. Hash mật khẩu    : $6$....
```

---

## 1. SSH public key

**Linux / macOS / WSL / Git Bash**
```bash
ls ~/.ssh/id_ed25519.pub 2>/dev/null || ssh-keygen -t ed25519 -C "tran@linux-project"
cat ~/.ssh/id_ed25519.pub
```
**Windows (PowerShell)**
```powershell
if (-not (Test-Path "$env:USERPROFILE\.ssh\id_ed25519.pub")) { ssh-keygen -t ed25519 -C "tran@linux-project" }
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```
Hỏi gì cứ Enter (passphrase nên đặt). Gửi **nguyên 1 dòng** bắt đầu bằng `ssh-ed25519`.

## 2. WireGuard public key

- **Windows / macOS**: cài app ở <https://www.wireguard.com/install/> → **Add empty tunnel…** → đặt tên `linux-project` → copy dòng **Public key** ở trên cùng. Để cửa sổ đó lại (Save), lát Dự gửi thông tin sẽ dán tiếp.
- **Linux**:
  ```bash
  sudo apt install wireguard-tools
  sudo sh -c 'umask 077; wg genkey > /etc/wireguard/linux-project.key'
  sudo cat /etc/wireguard/linux-project.key | wg pubkey
  ```

## 3. Hash mật khẩu sudo

Bạn có sudo đầy đủ, mỗi lần `sudo` phải nhập mật khẩu này. Chạy (Linux/macOS/WSL/**Git Bash** trên Windows):
```bash
openssl passwd -6
```
Nhập mật khẩu 2 lần → gửi chuỗi `$6$...` in ra. **Nhớ mật khẩu**, chỉ gửi chuỗi hash, không gửi mật khẩu.

---

## ⚠️ KHÔNG BAO GIỜ gửi

- File `~/.ssh/id_ed25519` (không có `.pub`): đó là **private key**.
- Dòng `PrivateKey = ...` trong WireGuard.
- Mật khẩu thật.

Ai có mấy thứ trên là đăng nhập được thay bạn.

## Sau khi gửi

Dự gửi lại: **IP VPN của bạn** (`10.8.0.3`), **public key của server**, **IP Bastion**. Lúc đó làm tiếp mục 3–4 trong [`ssh-access.md`](ssh-access.md) (cấu hình VPN + SSH). Lỗi thì xem mục 5 của file đó.
