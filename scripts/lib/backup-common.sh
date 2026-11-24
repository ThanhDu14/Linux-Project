#!/usr/bin/env bash
# backup-common.sh — hàm dùng chung cho backup.sh, restore.sh, backup-offsite.sh (TV4).
# Chỉ để source, không chạy trực tiếp. Script gọi phải tự bật: set -Eeuo pipefail
#
# shellcheck disable=SC2034  # các biến cấu hình dưới đây do script source file này sử dụng
# shortcut: tự có log/trap riêng vì scripts/lib/common.sh (TV5) chưa có; khi có thì chuyển sang dùng chung.

# ---------- Cấu hình: mặc định, rồi ghi đè bằng file /etc/lab-backup.conf ----------
CONF_FILE=${CONF_FILE:-/etc/lab-backup.conf}
DB_NAME=appdb
WEB_DIR=/var/www
BACKUP_DIR=/data/backup
RETENTION_DAYS=7
MIN_FREE_MB=200
REMOTE=rbackup@10.0.2.20
SSH_KEY=/root/.ssh/backup_ed25519
APP_SERVICE=
ALERT_TO=
INCOMING_DIR=/backup/incoming
S3_BUCKET=
S3_PREFIX=web-app-db-01
AWS_REGION=ap-southeast-1
LOG_FILE=${LOG_FILE:-/var/log/lab-backup.log}

if [[ -r $CONF_FILE ]]; then
    # shellcheck source=/dev/null  # file cấu hình chỉ có trên máy thật
    . "$CONF_FILE"
fi

SCRIPT_NAME=${0##*/}
WORK_DIR=

# ---------- Log & cảnh báo ----------
# Ghi ra stderr (systemd đẩy vào journald) và nối vào LOG_FILE nếu ghi được.
log() {
    local line
    line="$(date '+%F %T') [$SCRIPT_NAME] $*"
    printf '%s\n' "$line" >&2
    printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
}

alert() {
    [[ -n $ALERT_TO ]] || return 0
    if command -v msmtp >/dev/null 2>&1; then
        printf 'To: %s\nSubject: [lab-backup] %s lỗi trên %s\n\n%s\n' \
            "$ALERT_TO" "$SCRIPT_NAME" "$(hostname)" "$*" | msmtp "$ALERT_TO" ||
            log "WARN: gửi mail cảnh báo thất bại"
    else
        log "WARN: không có msmtp, bỏ qua mail cảnh báo"
    fi
}

die() {
    log "ERROR: $*"
    alert "$*"
    exit 1
}

# ---------- trap ERR / EXIT ----------
on_err() {
    local rc=$? line=$1 cmd=$2
    trap - ERR
    log "ERROR: lệnh '$cmd' thất bại (exit $rc) tại dòng $line"
    alert "Lệnh '$cmd' thất bại (exit $rc) tại dòng $line"
    exit "$rc"
}

on_exit() {
    local rc=$?
    trap - ERR # dọn dẹp không được kích hoạt lại on_err
    if [[ -n $WORK_DIR && -d $WORK_DIR ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    # Hook cho script gọi (vd. restore.sh bật lại app)
    if declare -F on_exit_hook >/dev/null; then
        on_exit_hook
    fi
    exit "$rc"
}

trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR
trap on_exit EXIT

# ---------- Tiện ích ----------
require_root() {
    [[ $EUID -eq 0 ]] || die "cần chạy bằng root (sudo $SCRIPT_NAME)"
}

require_uint() { # tên, giá trị
    [[ $2 =~ ^[0-9]+$ ]] || die "$1 phải là số nguyên không âm, nhận được: '$2'"
}

# Chạy lệnh bằng user hệ điều hành postgres (xác thực peer qua Unix socket)
as_pg() {
    runuser -u postgres -- "$@"
}

# Xoá file khớp mẫu trong DIR cũ hơn DAYS ngày (tính chính xác theo phút, không làm tròn ngày)
apply_retention() { # dir days pattern...
    local dir=$1 days=$2 f
    shift 2
    local find_args=() p
    for p in "$@"; do
        find_args+=(-o -name "$p")
    done
    while IFS= read -r -d '' f; do
        rm -f -- "$f"
        log "retention: đã xoá $f (cũ hơn $days ngày)"
    done < <(find "$dir" -maxdepth 1 -type f \( "${find_args[@]:1}" \) -mmin +"$((days * 1440))" -print0)
}

# "Dấu vân tay" dữ liệu: mỗi bảng trong schema public → tên, số dòng, md5 toàn bộ nội dung.
# backup.sh lưu kết quả vào manifest.txt; restore.sh tính lại sau khi khôi phục và so sánh.
db_fingerprint() { # db
    local db=$1 t
    as_pg psql -XAtq -v ON_ERROR_STOP=1 -d "$db" \
        -c "SELECT quote_ident(tablename) FROM pg_tables WHERE schemaname = 'public' ORDER BY 1" </dev/null |
        while IFS= read -r t; do
            printf '%s %s\n' "$t" "$(as_pg psql -XAtq -v ON_ERROR_STOP=1 -d "$db" -c \
                "SELECT count(*) || ' ' || md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) FROM public.$t x" </dev/null)"
        done
}
