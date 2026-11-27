# TV5 — Bash Toolkit & Cảnh báo: triển khai và vận hành

Người phụ trách: Hưng (TV5). Phần này bổ sung `scripts/toolkit.sh`, `scripts/deploy.sh`, `scripts/healthcheck.sh`, `scripts/logrotate.sh`, thư viện `scripts/lib/common.sh`, mẫu cấu hình toolkit/msmtp và systemd timer.

## 1. Cài đặt & cấu hình

Cài source toolkit tại `/opt/lab-toolkit/scripts/` (root:root; executable scripts `0755`, thư viện `0644`). Cài:

- `config/toolkit/lab-toolkit.conf` → `/etc/lab-toolkit.conf` (root:root, `0644`); cấu hình theo từng VM.
- `config/msmtp/msmtprc.example` → `/etc/msmtprc` (root:root, `0600`), thay bằng địa chỉ thật và secret lấy từ Ansible Vault. Không commit App Password.
- `config/systemd/lab-healthcheck.service` và `.timer` → `/etc/systemd/system/`, sau đó `systemctl daemon-reload && systemctl enable --now lab-healthcheck.timer`.

Theo thông tin TV1 xác nhận: VM1 dùng `HC_MODE=local`, `HC_CHECK_LOCAL_HTTP=yes`, `HEALTH_URL=http://127.0.0.1:5000/health`, `APP_SERVICE=app.service`, `APP_DEST_DIR=/opt/todo-app`, `APP_OWNER=todo:todo`, `HC_DISK_MOUNTS="/ /data"`, `HC_SERVICES="nginx postgresql app.service"`, `HC_PORTS="80 443 5000 5432"`. VM2 dùng `HC_MODE=both`, `HC_CHECK_LOCAL_HTTP=no`, `HC_REMOTE_URL=https://10.0.2.10/health`, `HC_DISK_MOUNTS="/ /backup"`, và danh sách service/port chỉ cho dịch vụ cục bộ VM2. Như vậy VM2 vẫn kiểm tra CPU/RAM/disk/service của chính nó, đồng thời thực hiện health-check chéo VM1. Secret ứng dụng trong `/etc/todo-app` nằm ngoài `/opt/todo-app`; deploy source phải được đặt ngoài thư mục đích.

Cổng egress TCP 587 đã có trong Terraform SG/NACL. VM private cần `enable_nat=true` để gửi mail ra SMTP. `ALERT_TO` để trống thì toolkit ghi log nhưng không gửi thư.

> **Tích hợp cần xác nhận với TV1/TV3/TV4:** Unit app là `app.service`; cấu hình trong `/etc/todo-app` không được đưa vào staging/deploy. Unit backup VM1 là `lab-backup.service`, dùng `/opt/lab-toolkit/scripts/backup.sh`; menu phải gọi chính xác đường dẫn này theo sudoers. Quyền deploy/healthcheck/logrotate/restore cần được đối chiếu với sudoers của lab khi role được tích hợp. Tên timer là `lab-healthcheck.timer`.

## 2. Sử dụng

```bash
sudo /opt/lab-toolkit/scripts/toolkit.sh
sudo /opt/lab-toolkit/scripts/toolkit.sh -c healthcheck
sudo /opt/lab-toolkit/scripts/healthcheck.sh --help
sudo /opt/lab-toolkit/scripts/deploy.sh --help
sudo /opt/lab-toolkit/scripts/logrotate.sh --help
sudo /opt/lab-toolkit/scripts/backup.sh --help
sudo /opt/lab-toolkit/scripts/restore.sh --help
```

Menu gọi trực tiếp công cụ TV4 hiện có (`backup.sh`, `restore.sh`). Restore sẽ ghi đè dữ liệu nên yêu cầu xác nhận như script TV4 đã thiết kế.

### Deploy

`deploy.sh` nhận source directory có cấu trúc `nginx/sites-available/`, `nginx/conf.d/` và/hoặc `app/`. Chụp snapshot trước khi thay đổi; triển khai Nginx sẽ chạy `nginx -t`, reload Nginx, rồi curl `/health` với header Host. Nếu bất kỳ bước lỗi nào được phát hiện, script phục hồi snapshot và reload cấu hình cũ. `last_good` trỏ tới snapshot trước lần deploy thành công, để có thể gọi `deploy.sh -r` khôi phục thủ công.

Ví dụ staging được cấu hình bên ngoài thư mục đích:

```text
/opt/lab-deploy-staging/
├── nginx/
│   ├── sites-available/*.conf
│   └── conf.d/*.conf
└── app/                       # nếu deploy app/all
```

Ứng dụng chạy tại `/opt/todo-app`, service `app.service`, owner `todo:todo`; secret vẫn nằm ở `/etc/todo-app` và không được đặt trong staging. Trên VM1, app health mặc định là `http://127.0.0.1:5000/health`; health chéo từ VM2 dùng `https://10.0.2.10/health` với `curl -k`. Deploy Nginx còn kiểm tra cú pháp và health endpoint đã cấu hình.

### Health check

`healthcheck.sh` kiểm tra CPU, RAM, các mount point, services, TCP listen ports và HTTPS health endpoint. Local check dùng `127.0.0.1`; remote check trên VM2 truy cập VM1 bằng private IP `10.0.2.10`. Khi có lỗi, script gom lỗi vào một cảnh báo, ghi log ra stderr/journald và file log, gửi mail nếu msmtp được cấu hình, rồi trả exit code khác 0.

```bash
sudo /opt/lab-toolkit/scripts/healthcheck.sh -m local
sudo /opt/lab-toolkit/scripts/healthcheck.sh -m remote
sudo /opt/lab-toolkit/scripts/healthcheck.sh -m local -d 0  # cố ý kích hoạt cảnh báo disk khi chạy trực tiếp
journalctl -u lab-healthcheck.service
systemctl list-timers lab-healthcheck.timer
```

Không chạy timer với ngưỡng cố tình thấp; chỉ dùng override trong lệnh demo. Ngưỡng CPU/RAM/disk là phần trăm từ 0–100.

### Log rotation

```bash
sudo /opt/lab-toolkit/scripts/logrotate.sh -f /var/log/lab-toolkit.log -k 5
ls -l /var/log/lab-toolkit.log*
```

Script xoay file được chỉ định, nén các thế hệ thành `.gz`, và giữ tối đa N thế hệ. Copytruncate có thể mất các dòng ghi giữa lúc sao chép và truncate. Nó không thay thế logrotate hệ thống cho `/var/log/nginx` hay journald.

## 3. Kiểm thử & demo

```bash
shellcheck -x scripts/*.sh scripts/lib/*.sh
systemd-analyze verify config/systemd/lab-healthcheck.service config/systemd/lab-healthcheck.timer
```

Trong lab:

1. Chạy menu và nhập lựa chọn sai để chứng minh xử lý input.
2. Chuẩn bị một cấu hình Nginx sai cú pháp trong staging, chạy deploy và chứng minh `nginx -t` bắt lỗi, tự rollback, site cũ vẫn trả 200.
3. Chạy healthcheck bình thường, rồi dừng dịch vụ (hoặc override ngưỡng) và chứng minh exit non-zero, log và email thật nhận được.
4. Trên VM2, chạy remote health check khi VM1 endpoint lỗi để chứng minh giám sát chéo.
5. Xoay log nhiều lần với `-k 3`, chứng minh `.1.gz`–`.3.gz` và không còn thế hệ cũ hơn.
6. Chạy ShellCheck trực tiếp, chụp output sạch.

Lưu ý demo: chỉ dừng service trong thời gian ngắn, sau đó bật lại và xác minh active. Không chỉnh sửa cấu hình production đang chạy nếu chưa có snapshot/đường rollback.

## 4. Giới hạn đã biết

- Timer chạy sau boot hai phút và sau đó mỗi năm phút; không chạy bù các lần bỏ lỡ khi máy tắt.
- Timer systemd và cài đặt `msmtp` cần được tích hợp vào Ansible role `toolkit` của TV1; repo hiện chưa có role đó.
- Cấu hình unit app, đường dẫn artifact deploy và ownership cần khớp với ứng dụng TV3 trước khi triển khai thật.
- Script health check hiện kiểm tra sự tồn tại của TCP listener cho mỗi port được cấu hình; port chỉ áp dụng trên VM1. Cấu hình danh sách riêng theo từng host.
- `msmtp` chỉ được xem là hoàn tất sau khi gửi thư thử thành công tới hộp thư thật; file mẫu không chứa secret và không tự cấu hình tài khoản.
