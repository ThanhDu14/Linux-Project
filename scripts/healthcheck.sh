#!/usr/bin/env bash
# healthcheck.sh — resource, service, listening-port, and optional remote endpoint checks.
set -Eeuo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: healthcheck.sh [-m local|remote|both] [-c CPU_MAX] [-M RAM_MAX] [-d DISK_MAX] [-N] [-q] [-h|--help]

Checks configured services, ports, disk mounts, CPU/RAM thresholds, and HTTP health.
-N bypasses the alert cooldown (automatically bypassed when -c/-M/-d overrides are set).
On failure, logs a consolidated report, sends an alert (if configured), and exits non-zero.
EOF
}

if [[ ${1:-} == --help ]]; then usage; exit 0; fi

MODE=${HC_MODE:-local}
CPU_MAX=${HC_CPU_MAX:-85}
RAM_MAX=${HC_RAM_MAX:-85}
DISK_MAX=${HC_DISK_MAX:-80}
QUIET=0
NO_COOLDOWN=0
while getopts ':m:c:M:d:Nqh' opt; do
    case $opt in
        m) MODE=$OPTARG ;;
        c) CPU_MAX=$OPTARG; NO_COOLDOWN=1 ;;
        M) RAM_MAX=$OPTARG; NO_COOLDOWN=1 ;;
        d) DISK_MAX=$OPTARG; NO_COOLDOWN=1 ;;
        N) NO_COOLDOWN=1 ;;
        q) QUIET=1 ;;
        h) usage; exit 0 ;;
        :) usage >&2; die "Option -$OPTARG requires a value" ;;
        *) usage >&2; die "Unknown option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || { usage >&2; die "Unexpected arguments: $*"; }
[[ $MODE == local || $MODE == remote || $MODE == both ]] || die "-m must be local, remote, or both"
require_uint HC_CPU_MAX "$CPU_MAX"
require_uint HC_RAM_MAX "$RAM_MAX"
require_uint HC_DISK_MAX "$DISK_MAX"
(( CPU_MAX <= 100 && RAM_MAX <= 100 && DISK_MAX <= 100 )) || die 'CPU, RAM, and disk thresholds must be between 0 and 100'

FAILURES=()
check_result() {
    local description=$1 result=$2
    if [[ $result == 0 ]]; then
        (( QUIET )) || log INFO "OK: $description"
    else
        FAILURES+=("$description")
        log ERROR "FAIL: $description"
    fi
}

cpu_usage() {
    local user nice system idle iowait irq softirq steal total1 idle1 total2 idle2
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    idle1=$((idle + iowait))
    total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
    sleep 1
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    idle2=$((idle + iowait))
    total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local delta_total=$((total2 - total1))
    (( delta_total > 0 )) || return 1
    printf '%s\n' "$(( (100 * (delta_total - (idle2 - idle1))) / delta_total ))"
}

ram_usage() {
    awk '/MemTotal:/ { total=$2 } /MemAvailable:/ { available=$2 } END {
        if (total <= 0) exit 1
        printf "%d\n", (100 * (total - available)) / total
    }' /proc/meminfo
}

# Host-local resource/service checks run in every mode, including remote-only HTTP checks.
cpu=$(cpu_usage) || die "Unable to calculate CPU usage"
if (( cpu <= CPU_MAX )); then
    check_result "CPU usage ${cpu}% (threshold ${CPU_MAX}%)" 0
else
    check_result "CPU ${cpu}% exceeds ${CPU_MAX}%" 1
fi

ram=$(ram_usage) || die "Unable to calculate RAM usage"
if (( ram <= RAM_MAX )); then
    check_result "RAM usage ${ram}% (threshold ${RAM_MAX}%)" 0
else
    check_result "RAM ${ram}% exceeds ${RAM_MAX}%" 1
fi

for mount in ${HC_DISK_MOUNTS:-/}; do
    if usage_pct=$(df -P -- "$mount" 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }') && [[ $usage_pct =~ ^[0-9]+$ ]]; then
        if (( usage_pct <= DISK_MAX )); then
            check_result "Disk $mount ${usage_pct}% (threshold ${DISK_MAX}%)" 0
        else
            check_result "Disk $mount ${usage_pct}% exceeds ${DISK_MAX}%" 1
        fi
    else
        check_result "Could not read disk usage for $mount" 1
    fi
done

if [[ -n ${HC_SERVICES:-} || -n ${HC_CHECK_BACKUP_UNIT:-} ]]; then
    require_cmd systemctl
fi

for service in ${HC_SERVICES:-}; do
    if systemctl is-active --quiet "$service"; then
        check_result "service $service is active" 0
    else
        check_result "service $service is not active" 1
    fi
done

if [[ -n ${HC_PORTS:-} ]]; then
    require_cmd ss
fi

for port in ${HC_PORTS:-}; do
    if ss -H -ltn "sport = :$port" | grep -q .; then
        check_result "TCP port $port is listening" 0
    else
        check_result "TCP port $port is not listening" 1
    fi
done

if [[ -n ${HC_CHECK_BACKUP_UNIT:-} ]]; then
    if systemctl is-failed --quiet "$HC_CHECK_BACKUP_UNIT"; then
        check_result "backup unit $HC_CHECK_BACKUP_UNIT is failed" 1
    else
        check_result "backup unit $HC_CHECK_BACKUP_UNIT is not failed" 0
    fi
fi

check_http_health() {
    local label=$1 url=$2 host_header=${3:-} resp=""
    local curl_args=(-fsSk --connect-timeout 3 --max-time 8)
    if [[ -n $host_header ]]; then
        curl_args+=(-H "Host: $host_header")
    fi
    if resp=$(curl "${curl_args[@]}" "$url" 2>/dev/null) && [[ $resp == *ok* ]]; then
        check_result "$label is healthy ($url)" 0
    else
        check_result "$label failed ($url)" 1
    fi
}

hc_domain=${HC_APP_DOMAIN:-${APP_DOMAIN:-}}

if [[ ${HC_CHECK_LOCAL_HTTP:-yes} == yes && ( $MODE == local || $MODE == both ) ]]; then
    require_cmd curl
    health_url=${HEALTH_URL:-http://127.0.0.1:5000/health}
    check_http_health "local HTTP health endpoint" "$health_url" "$hc_domain"
fi

if [[ $MODE == remote || $MODE == both ]]; then
    require_cmd curl
    remote_url=${HC_REMOTE_URL:-}
    [[ -n $remote_url ]] || die "HC_REMOTE_URL must be configured for remote checks"
    check_http_health "remote HTTP health endpoint" "$remote_url" "$hc_domain"
fi

if (( ${#FAILURES[@]} > 0 )); then
    report=$(printf '%s\n' "${FAILURES[@]}")
    log ERROR "Health check found ${#FAILURES[@]} problem(s)"
    cooldown=${HC_COOLDOWN_SEC:-300}
    require_uint HC_COOLDOWN_SEC "$cooldown"
    state_file=${HC_ALERT_STATE_FILE:-/run/lab-healthcheck.last-alert}
    now=$(date +%s)
    last=0
    if [[ -r $state_file ]]; then
        read -r last < "$state_file" || last=0
        [[ $last =~ ^[0-9]+$ ]] || last=0
    fi
    if (( NO_COOLDOWN || cooldown == 0 || now - last >= cooldown )); then
        alert "Health check failed on $(hostname)" "$report" || true
        if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
            printf '%s\n' "$now" > "$state_file"
        fi
    else
        log WARN "Alert suppressed by cooldown (${cooldown}s); current failures: $report"
    fi
    exit 1
fi
(( QUIET )) || log INFO 'Health check passed'
