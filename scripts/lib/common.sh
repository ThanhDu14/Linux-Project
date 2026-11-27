#!/usr/bin/env bash
# common.sh — shared logging, configuration, alerts, and error handling.
# Scripts that source this library must enable: set -Eeuo pipefail

SCRIPT_NAME=${SCRIPT_NAME:-${0##*/}}
TOOLKIT_CONF=${TOOLKIT_CONF:-/etc/lab-toolkit.conf}
TOOLKIT_LOG=${TOOLKIT_LOG:-/var/log/lab-toolkit.log}
ALERT_TO=${ALERT_TO:-}
WORK_DIR=

if [[ -r $TOOLKIT_CONF ]]; then
    # This file must be an administrator-owned, trusted shell config (not user input).
    # shellcheck source=/dev/null
    . "$TOOLKIT_CONF"
fi

log() {
    local level=$1
    shift
    local line
    line="$(date '+%F %T') [$SCRIPT_NAME] $level: $*"
    printf '%s\n' "$line" >&2
    if [[ -n ${TOOLKIT_LOG:-} ]]; then
        if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
            { printf '%s\n' "$line" >>"$TOOLKIT_LOG"; } 2>/dev/null || true
        elif [[ -e $TOOLKIT_LOG && -w $TOOLKIT_LOG ]]; then
            { printf '%s\n' "$line" >>"$TOOLKIT_LOG"; } 2>/dev/null || true
        fi
    fi
}

alert() {
    local subject=$1
    local body=$2
    [[ -n ${ALERT_TO:-} ]] || return 0
    if ! command -v msmtp >/dev/null 2>&1; then
        log WARN "msmtp is unavailable; alert was not sent"
        return 0
    fi
    if ! printf 'To: %s\nSubject: [Linux Project] %s\n\n%s\n' \
        "$ALERT_TO" "$subject" "$body" | msmtp "$ALERT_TO"; then
        log WARN "msmtp failed to send alert to $ALERT_TO"
        return 0
    fi
    log INFO "Alert sent to $ALERT_TO: $subject"
}

die() {
    log ERROR "$*"
    alert "${SCRIPT_NAME} failed" "$*" || true
    exit 1
}

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root (sudo $SCRIPT_NAME)"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_uint() {
    [[ $2 =~ ^[0-9]+$ ]] || die "$1 must be a non-negative integer; got '$2'"
}

on_err() {
    local rc=$? line=${1:-?} cmd=${2:-unknown}
    trap - ERR
    log ERROR "command failed (exit $rc) at line $line: $cmd"
    alert "${SCRIPT_NAME} failed" "Command failed with exit $rc at line $line: $cmd" || true
    exit "$rc"
}

on_exit() {
    local rc=$?
    trap - ERR
    if [[ -n ${WORK_DIR:-} && -d $WORK_DIR ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    if declare -F on_exit_hook >/dev/null; then
        on_exit_hook || true
    fi
    return "$rc"
}

trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR
trap on_exit EXIT
