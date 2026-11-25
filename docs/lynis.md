# Lynis — điểm gia cố trước / sau

> Chủ sở hữu: Trân (TV2). Dùng cho mục "Bảo mật" của báo cáo (đề mục 2.2: ghi điểm gia cố và ≥ 3 mục đã khắc phục).
> Lynis 3.0.7 (gói Ubuntu 22.04), `lynis audit system --quick`. Báo cáo gốc: `reports/lynis/<truoc|sau>/<máy>.{dat,log}` (không commit — chứa thông tin hệ thống).

## 1. Cách chạy

```bash
cd ansible
ansible-playbook lynis.yml -e lynis_label=truoc --vault-password-file ~/.ansible/linux-project.vault_pass
# ... khắc phục, chạy site.yml ...
ansible-playbook lynis.yml -e lynis_label=sau   --vault-password-file ~/.ansible/linux-project.vault_pass
```

Mốc "trước" (2026-11-21 13:45) được chụp **sau** đợt gia cố đầu (SSH tắt root/mật khẩu, fail2ban, auditd, TLS) và **trước** các mục khắc phục dưới đây. Mốc "sau": 2026-11-21 14:20.

## 2. Kết quả

| Máy | Hardening index trước | Sau | Cảnh báo | Gợi ý |
|---|---|---|---|---|
| bastion-01 | 61 | **70** (+9) | 2 → 1 | 47 → 36 |
| web-app-db-01 | 65 | **76** (+11) | 2 → 1 | 48 → 35 |
| backup-01 | 61 | **71** (+10) | 2 → 1 | 47 → 35 |

## 3. Các mục đã khắc phục

| # | Mã Lynis | Vấn đề | Khắc phục | File (TV2) → role |
|---|---|---|---|---|
| 1 | **FIRE-4512** (cảnh báo) | Có iptables nhưng không có luật nào | UFW: deny incoming / allow outgoing / deny routed, chỉ mở đúng cổng từng máy | `config/ufw/rules.yml` → `firewall` |
| 2 | **SSH-7408** | Cấu hình SSH còn lỏng | `MaxAuthTries 3`, `LogLevel VERBOSE` (ghi fingerprint key), tắt X11/agent forwarding, `Compression no`, `ClientAliveInterval 300` + `ClientAliveCountMax 2`; VM1/VM2 thêm `AllowTcpForwarding no` (Bastion giữ để ProxyJump) | `config/ssh/sshd-hardening.conf`, `sshd-private.conf` → `ssh_hardening` |
| 3 | **BANN-7126 / 7130** | Không có banner pháp lý | `/etc/issue`, `/etc/issue.net` + `Banner` trong sshd | `config/ssh/issue.net` → `os_hardening` |
| 4 | **NETW-3200** | Có thể nạp giao thức ít dùng | Chặn `dccp`, `sctp`, `rds`, `tipc` | `config/modprobe/role2-blacklist.conf` → `os_hardening` |
| 5 | **USB-1000** | USB storage chưa bị chặn | Chặn `usb-storage` | như trên |
| 6 | KRNL-6000 (một phần) | Tham số kernel khác khuyến nghị | `kptr_restrict`, `dmesg_restrict`, `sysrq`, `suid_dumpable`, `protected_fifos/regular`, BPF, ICMP redirect, `log_martians` | `config/sysctl/99-role2-hardening.conf` → `os_hardening` |

Kiểm tra lại trên máy: `sshd -T | grep -i maxauthtries`, `ufw status verbose`, `sysctl kernel.kptr_restrict`, `cat /etc/issue.net`.

## 4. Chưa khắc phục (và lý do)

| Mã | Lý do |
|---|---|
| PKGS-7392 (cảnh báo) + KRNL-5830 | Có gói cần cập nhật bảo mật, kernel mới cần reboot → `apt upgrade` + reboot trong khung bảo trì (lab dựng lại hằng ngày từ AMI mới nhất cũng giải quyết) |
| BOOT-5122 | Mật khẩu GRUB: EC2 không có console vật lý để vào single-user |
| FILE-6310 | Tách `/home`, `/tmp`, `/var` ra phân vùng riêng: cần dựng lại máy; dữ liệu quan trọng đã ở EBS `/data` riêng |
| AUTH-9230/9262/9286 | Chính sách mật khẩu: SSH chỉ dùng key, mật khẩu chỉ dùng cho `sudo` của 2 người |
| LOGG-2154 | Log tập trung ra máy khác: ngoài phạm vi (hướng mở rộng) |
| FIRE-4513 (mới) | Gợi ý xem lại luật iptables chưa có traffic — bình thường với máy ít truy cập |
