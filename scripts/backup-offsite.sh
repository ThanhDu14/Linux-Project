#!/usr/bin/env bash
# backup-offsite.sh — Chạy trên VM2 (backup-01): kiểm tra checksum bản nhận từ VM1,
#                     áp retention, rồi đẩy lên S3 qua Gateway Endpoint (TV4).
#
# Quyền ghi S3 lấy từ IAM instance profile gắn vào VM2 (Terraform modules/iam) — không có access key.
# Trên S3, lifecycle (Terraform modules/s3) tự xoá object cũ hơn backup_retention_days.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/backup-common.sh
. "$SCRIPT_DIR/lib/backup-common.sh"

usage() {
    cat <<EOF
Cách dùng: $SCRIPT_NAME [-d DIR] [-r DAYS] [-b BUCKET] [-n] [-h|--help]

  -d DIR       thư mục nhận backup từ VM1      (mặc định: $INCOMING_DIR)
  -r DAYS      số ngày giữ lại trên VM2         (mặc định: $RETENTION_DAYS)
  -b BUCKET    S3 bucket đích                   (mặc định: ${S3_BUCKET:-<chưa đặt>})
  -n           không đẩy lên S3 (chỉ kiểm tra + retention)
  -h, --help   hiện trợ giúp này
EOF
}

if [[ ${1:-} == --help ]]; then usage; exit 0; fi

DO_S3=1
while getopts ':d:r:b:nh' opt; do
    case $opt in
        d) INCOMING_DIR=$OPTARG ;;
        r) RETENTION_DAYS=$OPTARG ;;
        b) S3_BUCKET=$OPTARG ;;
        n) DO_S3=0 ;;
        h) usage; exit 0 ;;
        :) usage >&2; die "tuỳ chọn -$OPTARG cần giá trị" ;;
        *) usage >&2; die "tuỳ chọn không hợp lệ: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || { usage >&2; die "tham số thừa: $*"; }

require_root
require_uint RETENTION_DAYS "$RETENTION_DAYS"
[[ -d $INCOMING_DIR ]] || die "không có thư mục $INCOMING_DIR"
cd "$INCOMING_DIR"

log "=== Off-site: $INCOMING_DIR ==="

# 1. Retention trước — không tốn công kiểm tra/đẩy file sắp bị xoá
apply_retention "$INCOMING_DIR" "$RETENTION_DAYS" 'lab-backup-*.tar.gz' 'lab-backup-*.tar.gz.sha256'

# 2. Kiểm tra checksum mọi bản đang giữ (phát hiện file truyền hỏng / bị sửa)
count=0
for sum in lab-backup-*.tar.gz.sha256; do
    [[ -e $sum ]] || continue
    sha256sum --quiet -c "$sum" || die "checksum sai: ${sum%.sha256}"
    count=$((count + 1))
done
log "Checksum OK: $count bản"

# 3. Đẩy lên S3 (không --delete: xoá trên S3 do lifecycle lo, giữ lâu hơn VM2)
if (( DO_S3 )); then
    [[ -n $S3_BUCKET ]] || die "chưa đặt S3_BUCKET (trong $CONF_FILE hoặc -b)"
    log "aws s3 sync → s3://$S3_BUCKET/$S3_PREFIX/"
    aws s3 sync "$INCOMING_DIR" "s3://$S3_BUCKET/$S3_PREFIX/" \
        --region "$AWS_REGION" --only-show-errors --exclude '*' --include 'lab-backup-*'
    log "S3 sync xong"
else
    log "Bỏ qua S3 (-n)"
fi

log "=== Off-site hoàn tất ==="
