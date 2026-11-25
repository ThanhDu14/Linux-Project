#!/usr/bin/env bash
# restore.sh — Khôi phục CSDL + nội dung web từ bản sao lưu do backup.sh tạo ra (TV4).
#
# Luồng: chọn bản (mặc định mới nhất) → kiểm sha256 → xác nhận → giải nén → dừng app →
#        dump an toàn DB hiện tại (pre-restore) → DROP + pg_restore --create → rsync web →
#        so "dấu vân tay" (số dòng + md5 từng bảng) với manifest lúc sao lưu → bật lại app.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/backup-common.sh
. "$SCRIPT_DIR/lib/backup-common.sh"

usage() {
    cat <<EOF
Cách dùng: $SCRIPT_NAME [-f FILE] [-c all|db|web] [-l] [-y] [-h|--help]

Khôi phục DB '$DB_NAME' và/hoặc thư mục web '$WEB_DIR' từ một file lab-backup-*.tar.gz.

  -f FILE      bản sao lưu cần khôi phục (mặc định: bản mới nhất trong $BACKUP_DIR)
  -c PHẦN      all (mặc định) | db | web
  -l           liệt kê các bản sao lưu hiện có rồi thoát
  -y           không hỏi xác nhận (dùng trong script)
  -h, --help   hiện trợ giúp này

Khôi phục từ VM2 khi VM1 mất bản cục bộ: chép file từ backup-01:$INCOMING_DIR về rồi dùng -f.
EOF
}

list_backups() {
    local f found=0
    while IFS= read -r f; do
        found=1
        printf '  %s  %6s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'lab-backup-*.tar.gz' | sort)
    (( found )) || echo "  (không có bản sao lưu nào trong $BACKUP_DIR)"
}

if [[ ${1:-} == --help ]]; then usage; exit 0; fi

FILE=
PART=all
ASSUME_YES=0
while getopts ':f:c:lyh' opt; do
    case $opt in
        f) FILE=$OPTARG ;;
        c) PART=$OPTARG ;;
        l) echo "Bản sao lưu trong $BACKUP_DIR:"; list_backups; exit 0 ;;
        y) ASSUME_YES=1 ;;
        h) usage; exit 0 ;;
        :) usage >&2; die "tuỳ chọn -$OPTARG cần giá trị" ;;
        *) usage >&2; die "tuỳ chọn không hợp lệ: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || { usage >&2; die "tham số thừa: $*"; }
case $PART in
    all | db | web) ;;
    *) die "-c chỉ nhận all|db|web, nhận được: '$PART'" ;;
esac

require_root
cd /

# 1. Chọn bản sao lưu
if [[ -z $FILE ]]; then
    FILE=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'lab-backup-*.tar.gz' | sort | tail -n 1)
    [[ -n $FILE ]] || die "không tìm thấy bản sao lưu nào trong $BACKUP_DIR"
fi
[[ -f $FILE ]] || die "không có file: $FILE"
FILE=$(realpath "$FILE")
log "=== Khôi phục ($PART) từ $FILE ==="

# 2. Kiểm tra toàn vẹn file trước khi đụng vào dữ liệu đang chạy
if [[ -f $FILE.sha256 ]]; then
    (cd "$(dirname "$FILE")" && sha256sum --quiet -c "$(basename "$FILE").sha256") ||
        die "sha256 KHÔNG KHỚP — file sao lưu bị hỏng, dừng lại"
    log "sha256 OK"
else
    log "WARN: không có $FILE.sha256, bỏ qua kiểm tra checksum"
fi

# 3. Xác nhận — thao tác này XOÁ dữ liệu hiện tại
if (( ! ASSUME_YES )); then
    [[ -t 0 ]] || die "không có terminal để xác nhận; dùng -y nếu chạy tự động"
    printf 'Sẽ GHI ĐÈ %s bằng %s.\nGõ YES để tiếp tục: ' "$PART" "$(basename "$FILE")" >&2
    read -r answer
    [[ $answer == YES ]] || die "người dùng huỷ"
fi

# 4. Giải nén
WORK_DIR=$(mktemp -d "$(dirname "$FILE")/.restore.XXXXXX")
tar -xzf "$FILE" -C "$WORK_DIR"

# 5. Khôi phục DB
APP_STOPPED=0
on_exit_hook() {
    if (( APP_STOPPED )); then
        if systemctl start "$APP_SERVICE"; then
            log "Đã bật lại $APP_SERVICE"
        else
            log "WARN: không bật lại được $APP_SERVICE"
        fi
    fi
}

if [[ $PART == all || $PART == db ]]; then
    [[ -f $WORK_DIR/$DB_NAME.dump ]] || die "bản sao lưu không chứa $DB_NAME.dump"

    # Dừng app để không còn kết nối giữ DB trong lúc DROP
    if [[ -n $APP_SERVICE ]] && systemctl is-active --quiet "$APP_SERVICE"; then
        systemctl stop "$APP_SERVICE"
        APP_STOPPED=1
        log "Đã dừng $APP_SERVICE"
    fi

    # Lưới an toàn: dump DB hiện tại trước khi xoá (nếu DB còn và dump được)
    if as_pg psql -XAtq -c "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" </dev/null | grep -q 1; then
        safety="$BACKUP_DIR/pre-restore-$(date +%Y%m%d-%H%M%S).dump"
        if as_pg pg_dump -Fc -d "$DB_NAME" >"$safety" 2>/dev/null; then
            chmod 600 "$safety"
            log "Đã lưu trạng thái trước khi khôi phục: $safety"
        else
            rm -f -- "$safety"
            log "WARN: không dump được DB hiện tại (có thể đã hỏng) — tiếp tục khôi phục"
        fi
    fi

    log "DROP DATABASE $DB_NAME rồi tạo lại từ bản sao lưu"
    as_pg dropdb --if-exists --force "$DB_NAME"
    # Đọc dump qua stdin: user postgres không cần quyền đọc thư mục tạm (700, của root)
    as_pg pg_restore --create --exit-on-error -d postgres <"$WORK_DIR/$DB_NAME.dump"
    log "pg_restore xong"
fi

# 6. Khôi phục nội dung web
if [[ $PART == all || $PART == web ]]; then
    web_name=$(basename "$WEB_DIR")
    if [[ -d $WORK_DIR/$web_name ]]; then
        mkdir -p "$WEB_DIR"
        rsync -a --delete "$WORK_DIR/$web_name/" "$WEB_DIR/"
        log "Đã khôi phục $WEB_DIR"
    elif [[ $PART == web ]]; then
        die "bản sao lưu không chứa thư mục web '$web_name'"
    else
        log "WARN: bản sao lưu không chứa thư mục web, bỏ qua"
    fi
fi

# 7. Chứng minh toàn vẹn: so dấu vân tay hiện tại với manifest lúc sao lưu
if [[ $PART == all || $PART == db ]]; then
    expected=$(grep -v '^#' "$WORK_DIR/manifest.txt" || true)
    actual=$(db_fingerprint "$DB_NAME")
    log "Kiểm tra toàn vẹn (bảng / số dòng / md5):"
    printf '%s\n' "$actual" | while IFS= read -r l; do log "  $l"; done
    if [[ $expected == "$actual" ]]; then
        log "TOÀN VẸN OK — dữ liệu khớp 100% với lúc sao lưu"
    else
        log "Manifest lúc sao lưu:"
        printf '%s\n' "$expected" | while IFS= read -r l; do log "  $l"; done
        die "dữ liệu sau khôi phục KHÔNG khớp manifest"
    fi
fi

log "=== Khôi phục hoàn tất ==="
