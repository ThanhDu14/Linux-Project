#!/usr/bin/env bash
# logrotate.sh — rotate one selected regular log, gzip it, and keep N generations.
set -Eeuo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: logrotate.sh [-f LOG_FILE] [-k KEEP] [-s MIN_SIZE_KB] [-F] [-h|--help]

Rotate LOG_FILE to LOG_FILE.1.gz, shift old generations, and retain KEEP files.
-F forces rotation even when the log is empty or smaller than MIN_SIZE_KB.
EOF
}

if [[ ${1:-} == --help ]]; then usage; exit 0; fi

LOG_FILE=${LOGROTATE_TARGET:-/var/log/lab-toolkit.log}
KEEP=${LOGROTATE_KEEP:-5}
MIN_SIZE_KB=0
FORCE=0
while getopts ':f:k:s:Fh' opt; do
    case $opt in
        f) LOG_FILE=$OPTARG ;;
        k) KEEP=$OPTARG ;;
        s) MIN_SIZE_KB=$OPTARG ;;
        F) FORCE=1 ;;
        h) usage; exit 0 ;;
        :) usage >&2; die "Option -$OPTARG requires a value" ;;
        *) usage >&2; die "Unknown option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || { usage >&2; die "Unexpected arguments: $*"; }
require_root
require_uint KEEP "$KEEP"
require_uint MIN_SIZE_KB "$MIN_SIZE_KB"
(( KEEP > 0 )) || die 'KEEP must be at least 1'
[[ -f $LOG_FILE && ! -L $LOG_FILE ]] || die "Log must be an existing regular file (not a symlink): $LOG_FILE"

size_kb=$(du -k -- "$LOG_FILE" | awk '{print $1}')
if (( ! FORCE && size_kb < MIN_SIZE_KB )); then
    log INFO "Skipping $LOG_FILE: ${size_kb}KB < ${MIN_SIZE_KB}KB"
    exit 0
fi
if (( ! FORCE )) && [[ ! -s $LOG_FILE ]]; then
    log INFO "Skipping empty log $LOG_FILE (use -F to force)"
    exit 0
fi

# Remove all numbered generations at or above KEEP, including after KEEP is lowered.
for old in "$LOG_FILE".[0-9]*; do
    [[ -e $old ]] || continue
    suffix=${old#"$LOG_FILE".}
    suffix=${suffix%.gz}
    [[ $suffix =~ ^[0-9]+$ ]] || continue
    if (( 10#$suffix >= KEEP )); then
        rm -f -- "$old"
    fi
done
for ((generation = KEEP - 1; generation >= 1; generation--)); do
    if [[ -e $LOG_FILE.$generation.gz ]]; then
        mv -- "$LOG_FILE.$generation.gz" "$LOG_FILE.$((generation + 1)).gz"
    elif [[ -e $LOG_FILE.$generation ]]; then
        mv -- "$LOG_FILE.$generation" "$LOG_FILE.$((generation + 1))"
    fi
done

# copytruncate retains the inode so processes holding the log open can continue writing.
cp -p -- "$LOG_FILE" "$LOG_FILE.1"
: > "$LOG_FILE"
gzip -f -- "$LOG_FILE.1"
log INFO "Rotated $LOG_FILE (${size_kb}KB); retained up to $KEEP compressed generations"
