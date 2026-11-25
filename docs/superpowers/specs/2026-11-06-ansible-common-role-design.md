# Thiết kế: Ansible role `common` — user, SSH key, sudo giới hạn

- Ngày: 2026-11-06 · Người quyết định: Dự (hạ tầng) · Trạng thái: chờ duyệt
- Liên quan: `docs/team.md` (mục 2.1: `common` = hostname, user sudo, SSH key, package), `docs/ssh-access.md` (mục 6), `docs/architecture.md`

## 1. Vì sao

Hiện thêm một thành viên phải làm tay trên 3 máy: tạo user, dán `authorized_keys`, (sẽ phải) cấu hình sudo. Dự đã tạo tay `duy`, `hung` trên Bastion, VM1, VM2. Làm tay thì dễ sót máy, không ai biết ai đang có quyền gì, và không có cách gỡ người cho sạch. Danh sách VPN (`wireguard_peers`) lại nằm riêng, nên có thể lệch với danh sách user.

Mục tiêu: **khai báo mỗi thành viên đúng một lần**, Ansible dựng user + key + sudo + peer VPN trên đúng các máy; quyền sudo **tối thiểu theo vai, cố định ngay từ đầu** (thành viên đã có VM local với root đầy đủ để thử nghiệm; lab AWS được coi là "môi trường thật" để triển khai/demo). Đây cũng là nội dung cho phần Bảo mật của báo cáo.

## 2. Mục tiêu / Không làm / Thất bại nếu

**Mục tiêu**
- Một nguồn duy nhất cho thành viên; role `wireguard` cũng đọc từ đó.
- Tạo user, `authorized_keys` (độc quyền: key không khai báo bị gỡ), file `/etc/sudoers.d/<user>` theo vai, trên đúng các máy được phép.
- Gỡ thành viên rõ ràng, an toàn.
- Hostname, múi giờ, vài gói cơ bản (phần nhỏ của `common` theo `team.md`).

**Không làm (role khác lo)**
- Đụng vào user `ubuntu` hoặc sudo của nó (Ansible đang dùng nó).
- Cấu hình `sshd` (`AllowUsers`, tắt password, tắt root) — role `ssh_hardening`, nội dung do Trân sở hữu.
- UFW, fail2ban, auditd, Nginx, PostgreSQL, app, script.

**Thất bại nếu (dù chạy "được")**
- Một file sudoers sai cú pháp làm hỏng sudo trên máy.
- Có lối thoát lên root từ sudo giới hạn (editor, pager, script người dùng sửa được, `*` đặt sai).
- `duy`/`hung` mất quyền truy cập đang có khi chạy role lần đầu.
- Xoá nhầm user không nằm trong danh sách gỡ (vd `ubuntu`, `postgres`).
- Lab không vào được nữa (cả nhóm bị khoá ngoài).

## 3. Đã quyết

### 3.1 Thành viên và quyền

| User Linux | Người | Vai (`team.md`) | Bastion | VM1 `web` | VM2 `backup` | Mật khẩu sudo |
|---|---|---|---|---|---|---|
| `du` | Dự | 1 — Hạ tầng | sudo đầy đủ | sudo đầy đủ | sudo đầy đủ | Có |
| `tran` | Trân | 2 — Nginx + bảo mật | sudo đầy đủ | sudo đầy đủ | sudo đầy đủ | Có |
| `dang` | Đăng | 3 — App + systemd | chỉ đăng nhập (ProxyJump) | sudo giới hạn | **không có user** | `NOPASSWD` |
| `duy` | Duy | 4 — CSDL + backup | chỉ đăng nhập | sudo giới hạn | sudo giới hạn | `NOPASSWD` |
| `hung` | Hưng | 5 — Toolkit + cảnh báo | chỉ đăng nhập | sudo giới hạn | sudo giới hạn | `NOPASSWD` |

- Lý do Trân có sudo đầy đủ: phần bảo mật chạm UFW, sshd, fail2ban, auditd, Lynis, `/etc/shadow` trên cả 3 máy — liệt kê ra gần bằng root và danh sách dài dễ có lỗ.
- Bastion: chỉ người phải cấu hình nó có sudo (lỡ `ufw enable` thiếu 51820 là cả nhóm bị khoá).
- Không có sudo giới hạn theo từng lệnh cho Dự/Trân.

### 3.2 Mật khẩu (chỉ cho sudo, không cho SSH)
- SSH vẫn chỉ bằng key. Mật khẩu chỉ để `sudo` cho người có sudo đầy đủ.
- Mỗi người tự chạy `openssl passwd -6`, gửi **chuỗi hash `$6$...`** cho Dự qua tin nhắn riêng; Dự không biết mật khẩu. Hash được cất trong **ansible-vault**, không để chữ thường.

### 3.3 Danh sách thành viên một nơi
- File `ansible/group_vars/all/members.yml`. Mỗi thành viên: tên user, SSH public key (inline), WireGuard `{ip, public_key}` (tuỳ chọn), máy được vào, loại sudo theo máy. Hash mật khẩu ở `group_vars/all/vault.yml` (vault, cùng file mật khẩu `~/.ansible/linux-project.vault_pass`).
- `wireguard_peers` (`group_vars/bastion/wireguard.yml`) được **suy ra** từ `members` thay vì khai báo riêng. Template `wg.conf.j2` giữ nguyên hình dạng `{name, ip, public_key}`.
- Bỏ các file lẻ `ansible/Duy.pub`, `ansible/hung.pub` sau khi đã chép vào `members.yml`.
- IP VPN hiện có giữ nguyên: `du` = `10.8.0.2`. Chưa ai khác có key WireGuard — chỉ thêm khi họ gửi.

### 3.4 Gỡ thành viên
- Danh sách tường minh `removed_members` (tên user). Chỉ những tên đó bị gỡ: user + home, file sudoers, peer VPN (tự mất vì không còn trong `members`).
- **Không** gỡ "mọi user không có trong danh sách".

### 3.5 Bảo đảm cho sudoers
- Mọi file ghi vào `/etc/sudoers.d/` qua `validate: 'visudo -cf %s'`, quyền `0440`, owner `root`.
- Lệnh ghi đường dẫn tuyệt đối; không dùng `*` trừ khi không thể tránh và đã cân nhắc.
- Không cho editor (`vim`, `nano`), pager (`less`, `more`), `systemctl edit`, `tar`/`rsync`/`find` với quyền root.
- Script được phép chạy bằng sudo phải do `root` sở hữu, người dùng không ghi được, nằm ở `/usr/local/sbin/`.
- Mọi lần sudo bị từ chối vẫn được ghi log (mặc định) — dùng để demo.

### 3.6 Phần phụ
- Hostname theo `inventory_hostname` (`bastion-01`, `web-app-db-01`, `backup-01`).
- Múi giờ `Asia/Ho_Chi_Minh` (giờ log và tên file backup khớp giờ VN).
- Gói: `vim`, `curl`, `htop`, `git`, `tree`.

### 3.7 Thứ tự trong `site.yml`
Play `common` chạy trên `all` **trước** play `wireguard` trên `bastion`. Kết nối Ansible giữ nguyên (`ubuntu` + `.pem`, ProxyCommand qua IP public).

### 3.8 Xong khi
- Chạy `site.yml` lần 2 ra `changed=0`.
- Mỗi người `sudo -l` thấy đúng quyền của mình; `dang` thử `sudo bash` bị từ chối và có dòng log tương ứng.
- `duy`, `hung` vẫn SSH vào cả 3 máy như trước.
- `docs/ssh-access.md` mục 0 và 6.2 cập nhật quy trình mới (gửi thêm hash nếu có sudo đầy đủ; thêm/gỡ người = sửa `members.yml`/`removed_members` rồi chạy playbook). Thêm một dòng vào bảng lịch sử thay đổi của `architecture.md`.

## 4. Quyết định của Claude (Dự chưa xác nhận từng điểm)

1. **Không dùng `sudoedit` trên lab.** Theo nguyên tắc ở `team.md` (role chỉ copy từ `config/`), file cấu hình sửa trong repo rồi triển khai bằng Ansible; sửa tay trên máy sẽ bị ghi đè lần chạy sau. Bỏ `sudoedit` cũng bớt một hướng lách.
2. **Đọc log không cần sudo:** `dang`, `duy`, `hung` vào group `systemd-journal` (đọc toàn bộ journal) thay vì cho `sudo journalctl`.
3. **Danh sách lệnh nháp cho sudo giới hạn** (tên unit/script là giả định — chủ phần đó xác nhận/đổi tên trước khi triển khai, tên chốt sẽ được ghi vào biến):
   - `dang` @ VM1: `systemctl start|stop|restart|status app` (`app.service`), `systemctl daemon-reload`.
   - `duy` @ VM1: `systemctl start|stop|restart|status postgresql`, `systemctl start|status backup.service`, `systemctl list-timers`; chạy `psql` với quyền user `postgres` (runas `postgres`, **không** root — `\!` trong psql chỉ ra shell `postgres`, chấp nhận); `/usr/local/sbin/backup.sh`, `/usr/local/sbin/restore.sh`.
   - `duy` @ VM2: `systemctl start|status` cho unit đẩy S3 (`s3-sync.service`), `systemctl list-timers`.
   - `hung` @ VM1: `/usr/sbin/nginx -t`, `systemctl reload nginx`, `systemctl status nginx`, `/usr/local/sbin/deploy.sh`, `/usr/local/sbin/logrotate.sh`, `systemctl start|status healthcheck.service`.
   - `hung` @ VM2: `systemctl start|status healthcheck.service`, `/usr/local/sbin/healthcheck.sh`.
   - `systemctl status` mặc định mở pager → mỗi dòng `status` dùng `--no-pager` cố định trong lệnh được phép, hoặc đặt `Defaults:<user> env_keep -= "PAGER SYSTEMD_PAGER"` kèm `SYSTEMD_PAGER=` — builder chọn một cách nhưng phải không có pager root.
   Sudoers cho phép lệnh trỏ tới unit/script chưa tồn tại — không sao.
4. **`update_password: always`:** hash trong vault là nguồn sự thật; đổi mật khẩu = gửi hash mới cho Dự (đổi bằng `passwd` trên máy sẽ bị ghi đè lần chạy sau). Ghi điều này vào `ssh-access.md`.
5. **Thiếu hash** cho người có sudo đầy đủ (vd Trân chưa gửi): vẫn tạo user + key, **không** cấp sudo, in cảnh báo; playbook không fail (không chặn người khác).
6. **Giữ hostname sau reboot:** đặt `preserve_hostname: true` qua `/etc/cloud/cloud.cfg.d/` để cloud-init không đặt lại hostname của EC2.
7. **User mới:** shell `/bin/bash`, home `/home/<user>`, group riêng cùng tên. `duy`/`hung` có sẵn được nhận lại (không đổi UID/home); `authorized_keys` độc quyền sẽ thay key dán tay bằng key trong `members.yml` — phải là cùng key (`Duy.pub`, `hung.pub`).
8. Ghi họ tên Đăng (TV3), Duy (TV4) vào bảng ở `docs/team.md`.

## 5. Để builder tự quyết
- Hình dạng dữ liệu cụ thể của `members` (miễn biểu diễn được bảng 3.1 + mục 4.3, và đọc dễ cho người thêm thành viên).
- Cách sinh file sudoers (template Jinja hay `copy` nội dung), tên file trong `/etc/sudoers.d/`.
- Module dùng cho múi giờ (có `community.general` hay dùng `timedatectl`).
- Chia task trong role (`users.yml`, `sudo.yml`, ...), tên biến, tag.
- Cách kiểm tra (lệnh ad-hoc, `--check --diff`, một playbook verify nhỏ).

## 6. Lưu ý vận hành
- Lab phải đang **running** (nhóm hay tắt máy) mới chạy được; xem lệnh ở `ssh-access.md` mục 6.2.
- Chạy thử `--check --diff` trước lần đầu; `diff: false` cho task có hash.
- Đường lui nếu sudoers lỗi: user `ubuntu` (sudo của nó không bị đụng) + `lp-bastion-direct`.
