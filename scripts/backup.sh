#!/usr/bin/env bash
# backup.sh — Sao lưu CSDL PostgreSQL + nội dung web trên VM1, rồi rsync sang VM2 (TV4).
#
# Luồng: kiểm tra dung lượng → pg_dump → manifest (số dòng + md5 từng bảng) → nén .tar.gz gắn
#        timestamp + sha256 → rsync sang VM2 (key bị rrsync khoá chỉ-ghi) → retention cục bộ.
# Chạy tự động bởi lab-backup.timer (02:00 hằng ngày); có thể gọi tay hoặc từ toolkit.sh.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/backup-common.sh
. "$SCRIPT_DIR/lib/backup-common.sh"

usage() {
    cat <<EOF
Cách dùng: $SCRIPT_NAME [-d DIR] [-r DAYS] [-R USER@HOST] [-n] [-h|--help]

Sao lưu DB '$DB_NAME' + thư mục web '$WEB_DIR' thành DIR/lab-backup-<YYYYmmdd-HHMMSS>.tar.gz,
rsync sang VM2 và xoá bản cũ hơn DAYS ngày.

  -d DIR         thư mục lưu bản sao lưu trên máy này   (mặc định: $BACKUP_DIR)
  -r DAYS        số ngày giữ lại (retention)             (mặc định: $RETENTION_DAYS)
  -R USER@HOST   đích rsync trên VM2                     (mặc định: $REMOTE)
  -n             không rsync sang VM2 (chỉ sao lưu cục bộ)
  -h, --help     hiện trợ giúp này

Cấu hình mặc định đọc từ $CONF_FILE. Mã thoát khác 0 nếu có lỗi (kèm mail nếu đặt ALERT_TO).
EOF
}

if [[ ${1:-} == --help ]]; then usage; exit 0; fi

DO_RSYNC=1
while getopts ':d:r:R:nh' opt; do
    case $opt in
        d) BACKUP_DIR=$OPTARG ;;
        r) RETENTION_DAYS=$OPTARG ;;
        R) REMOTE=$OPTARG ;;
        n) DO_RSYNC=0 ;;
        h) usage; exit 0 ;;
        :) usage >&2; die "tuỳ chọn -$OPTARG cần giá trị" ;;
        *) usage >&2; die "tuỳ chọn không hợp lệ: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || { usage >&2; die "tham số thừa: $*"; }

require_root
require_uint RETENTION_DAYS "$RETENTION_DAYS"
require_uint MIN_FREE_MB "$MIN_FREE_MB"
cd /
umask 077 # bản sao lưu chứa toàn bộ dữ liệu: chỉ root đọc được

log "=== Bắt đầu sao lưu: DB=$DB_NAME, WEB=$WEB_DIR → $BACKUP_DIR ==="
install -d -m 700 "$BACKUP_DIR"

# 1. Kiểm tra dung lượng TRƯỚC khi ghi (câu hỏi vấn đáp: "2 giờ sáng đĩa đầy thì sao?")
#    Ước lượng = kích thước DB + web chưa nén, nhân 2 (bản dump tạm + file nén), cộng MIN_FREE_MB.
db_bytes=$(as_pg psql -XAtq -v ON_ERROR_STOP=1 -c "SELECT pg_database_size('$DB_NAME')" </dev/null)
db_kb=$((db_bytes / 1024))
web_kb=0
if [[ -d $WEB_DIR ]]; then
    web_kb=$(du -sk "$WEB_DIR" | cut -f1)
else
    log "WARN: không có thư mục web $WEB_DIR — chỉ sao lưu DB"
fi
need_kb=$(( (db_kb + web_kb) * 2 + MIN_FREE_MB * 1024 ))
avail_kb=$(df -Pk "$BACKUP_DIR" | awk 'NR == 2 { print $4 }')
log "Dung lượng: cần ~$((need_kb / 1024)) MB, còn trống $((avail_kb / 1024)) MB trên $(df -P "$BACKUP_DIR" | awk 'NR == 2 { print $6 }')"
if (( avail_kb < need_kb )); then
    die "KHÔNG ĐỦ DUNG LƯỢNG: cần ~$((need_kb / 1024)) MB, chỉ còn $((avail_kb / 1024)) MB — huỷ sao lưu, không ghi gì"
fi

# 2. Dump DB vào thư mục tạm (cùng đĩa, trong BACKUP_DIR, quyền 700) — bị xoá khi thoát
ts=$(date +%Y%m%d-%H%M%S)
name="lab-backup-$ts.tar.gz"
WORK_DIR=$(mktemp -d "$BACKUP_DIR/.work.XXXXXX")

log "pg_dump $DB_NAME (định dạng custom, đã nén)"
as_pg pg_dump -Fc -d "$DB_NAME" >"$WORK_DIR/$DB_NAME.dump"

{
    echo "# lab-backup manifest"
    echo "# created: $(date -Is)  host: $(hostname)  db: $DB_NAME  web: $WEB_DIR"
    echo "# <bảng> <số dòng> <md5 nội dung>"
    db_fingerprint "$DB_NAME"
} >"$WORK_DIR/manifest.txt"
log "Manifest: $(grep -vc '^#' "$WORK_DIR/manifest.txt") bảng"

# 3. Nén thành 1 file gắn timestamp: <db>.dump + manifest.txt + thư mục web
tar_args=(-C "$WORK_DIR" "$DB_NAME.dump" manifest.txt)
if [[ -d $WEB_DIR ]]; then
    tar_args+=(-C "$(dirname "$WEB_DIR")" "$(basename "$WEB_DIR")")
fi
tar -czf "$WORK_DIR/$name" "${tar_args[@]}"

# mv trong cùng filesystem là nguyên tử: không bao giờ có file lab-backup-*.tar.gz dở dang
mv "$WORK_DIR/$name" "$BACKUP_DIR/$name"
(cd "$BACKUP_DIR" && sha256sum "$name" >"$name.sha256")
log "Đã tạo $BACKUP_DIR/$name ($(du -h "$BACKUP_DIR/$name" | cut -f1))"

# 4. rsync sang VM2. Phía VM2 key bị khoá: command="rrsync -wo /backup/incoming" → chỉ ghi được
#    vào đúng thư mục đó, không đọc/xoá được backup cũ (VM1 bị chiếm cũng không phá được bản sao).
if (( DO_RSYNC )); then
    log "rsync → $REMOTE"
    rsync -a --chmod=F600 \
        -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15" \
        "$BACKUP_DIR/$name" "$BACKUP_DIR/$name.sha256" "$REMOTE:"
    log "rsync xong"
else
    log "Bỏ qua rsync (-n)"
fi

# 5. Retention cục bộ — làm SAU rsync: nếu VM2 lỗi thì script đã dừng ở trên và giữ nguyên bản cũ
apply_retention "$BACKUP_DIR" "$RETENTION_DAYS" 'lab-backup-*.tar.gz' 'lab-backup-*.tar.gz.sha256' 'pre-restore-*.dump'

log "=== Sao lưu hoàn tất: $name ==="
