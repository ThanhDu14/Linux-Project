# 5. Vận hành & Tự động hóa

*Phụ trách: Hưng (TV5). Bộ công cụ: `scripts/toolkit.sh`, `scripts/deploy.sh`, `scripts/healthcheck.sh`, `scripts/logrotate.sh`, `scripts/lib/common.sh`; cấu hình mẫu: `config/toolkit/`, `config/msmtp/`, `config/systemd/lab-healthcheck.*`.*

## 5.1 Bộ công cụ CLI

Điểm vào `toolkit.sh` cung cấp menu cho deploy/rollback, backup, liệt kê và restore backup, health-check, xoay log, và chạy ShellCheck. Menu xử lý lựa chọn không hợp lệ và EOF; tùy chọn `-c` hỗ trợ chạy lệnh không tương tác. Các thao tác cần quyền quản trị được thực hiện qua sudo.

Các script bật `set -Eeuo pipefail`, dùng thư viện `common.sh` để thống nhất log, cấu hình, cảnh báo, xử lý lỗi và dọn tài nguyên tạm. Lỗi được ghi ra stderr/journald và file log; nếu cấu hình `ALERT_TO` cùng `msmtp`, script gửi email cảnh báo.

> 📷 *Hình 5.1 — Menu toolkit và một lựa chọn được điều phối.*

## 5.2 Deploy an toàn và rollback

`deploy.sh` chụp snapshot các target hiện hành trước khi thay đổi. App source lấy từ staging riêng và đồng bộ vào `/opt/todo-app` với owner `todo:todo`; cấu hình nhạy cảm được giữ riêng ở `/etc/todo-app`. Với app, script khởi động lại `app.service` và xác nhận `http://127.0.0.1:5000/health`. Với Nginx, script đồng bộ cấu hình, sửa owner/mode, chạy `nginx -t`, reload Nginx, rồi xác nhận `https://127.0.0.1/health` kèm header `Host: $APP_DOMAIN` để kiểm tra luồng reverse proxy mà không gặp hairpin NLB. Nếu bước deploy lỗi, snapshot được khôi phục và cấu hình cũ được kiểm tra/reload. Snapshot gần nhất được giữ dưới tên `last_good`; tham số `-r` yêu cầu khôi phục snapshot thành công gần nhất.

> 📷 *Hình 5.2 — Cấu hình cố tình lỗi bị từ chối, rollback chạy, endpoint cũ vẫn trả HTTP 200.*

## 5.3 Health-check & cảnh báo

`healthcheck.sh` kiểm tra CPU, RAM, dung lượng các mount được cấu hình, trạng thái services systemd, TCP ports đang LISTEN và endpoint ứng dụng. Các kiểm tra tài nguyên/service cục bộ chạy trên cả VM1 và VM2; VM1 gọi `http://127.0.0.1:5000/health`, còn VM2 tắt HTTP local bằng `HC_CHECK_LOCAL_HTTP=no` và kiểm tra chéo VM1 tại `https://10.0.2.10/health` bằng `curl -k`. Các ngưỡng được cấu hình trong `/etc/lab-toolkit.conf`. Một lần chạy gom bất thường thành báo cáo, ghi log, gửi email qua msmtp nếu đã cấu hình và trả mã lỗi khác 0.

`lab-healthcheck.timer` lên lịch kiểm tra từ hai phút sau khi boot, sau đó mỗi năm phút khi máy đang chạy; sau khi khởi động lại sẽ kiểm tra sau hai phút. SMTP dùng STARTTLS cổng 587. File `/etc/msmtprc` phải có quyền `0600`; secret chỉ lấy từ Ansible Vault, không lưu trong repository.

> 📷 *Hình 5.3 — Dịch vụ bị dừng, health-check trả lỗi và email cảnh báo được nhận thật.*
> 📷 *Hình 5.4 — VM2 phát hiện endpoint VM1 lỗi qua kiểm tra chéo.*

## 5.4 Xoay vòng log

`logrotate.sh` nhận đường dẫn log và số thế hệ cần giữ, sao chép nội dung hiện tại, truncate file đang hoạt động để tiến trình giữ file descriptor tiếp tục ghi đúng inode, nén bản xoay bằng gzip và dịch chuyển/xóa các thế hệ vượt quá giới hạn. Phương pháp copytruncate có thể mất các dòng ghi trong khoảng giữa sao chép và truncate.

> 📷 *Hình 5.5 — Các thế hệ log `.1.gz` đến `.N.gz` sau khi xoay.*

## 5.5 Kiểm định

Chạy `shellcheck -x -P scripts scripts/*.sh scripts/lib/*.sh` (hoặc `toolkit.sh -c shellcheck`) trên toàn bộ script, gồm cả script TV4, để bảo đảm không còn lỗi/cảnh báo. Kiểm tra unit bằng `systemd-analyze verify` và chạy thử từng trường hợp lỗi trước demo.

> 📷 *Hình 5.6 — Output ShellCheck sạch.*

**Trạng thái bằng chứng:** Các placeholder ảnh phía trên cần được thay bằng ảnh chụp từ lần chạy trên VM của nhóm. Không ghi nhận email/rollback/timer là đã hoạt động trên AWS cho tới khi có kết quả chạy thật.
