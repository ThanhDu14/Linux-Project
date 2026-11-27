#!/usr/bin/env bash
# deploy.sh — staged configuration/application deployment with snapshot rollback.
set -Eeuo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: deploy.sh [-s SOURCE_DIR] [-t nginx|app|all] [-d DOMAIN] [-r] [-h|--help]

SOURCE_DIR layout:
  nginx/sites-available/  -> NGINX_SITES_DIR/sites-available/
  nginx/conf.d/           -> NGINX_SITES_DIR/conf.d/
  app/                    -> APP_DEST_DIR (when deploying app or all)

App deployments copy only application source. Keep secrets in /etc/todo-app,
outside both staging and APP_DEST_DIR. Every deployment snapshots current targets.
Nginx deploys run nginx -t, reload, and verify NGINX_HEALTH_URL with Host: APP_DOMAIN;
app deploys verify HEALTH_URL. Failed steps trigger rollback.
-r restores the most recent successful snapshot.
EOF
}

if [[ ${1:-} == --help ]]; then usage; exit 0; fi

SOURCE=${APP_SRC_DIR:-/opt/lab-deploy-staging}
TARGET=all
ROLLBACK_ONLY=0
while getopts ':s:t:d:rh' opt; do
    case $opt in
        s) SOURCE=$OPTARG ;;
        t) TARGET=$OPTARG ;;
        d) APP_DOMAIN=$OPTARG ;;
        r) ROLLBACK_ONLY=1 ;;
        h) usage; exit 0 ;;
        :) usage >&2; die "Option -$OPTARG requires a value" ;;
        *) usage >&2; die "Unknown option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || { usage >&2; die "Unexpected arguments: $*"; }
[[ $TARGET == nginx || $TARGET == app || $TARGET == all ]] || die "-t must be nginx, app, or all"
require_root
require_cmd rsync
require_cmd systemctl

BACKUP_ROOT=${DEPLOY_BACKUP_DIR:-/var/backups/lab-deploy}
KEEP=${DEPLOY_KEEP:-5}
NGINX_ROOT=${NGINX_SITES_DIR:-/etc/nginx}
require_uint DEPLOY_KEEP "$KEEP"
install -d -m 0700 "$BACKUP_ROOT"

verify_endpoint() {
    local url=$1 host_header=${2:-} attempt resp=""
    local curl_args=(-fsSk --connect-timeout 3 --max-time 8)
    if [[ -n $host_header ]]; then
        curl_args+=(-H "Host: $host_header")
    fi
    for attempt in 1 2 3 4 5; do
        if resp=$(curl "${curl_args[@]}" "$url" 2>/dev/null) && [[ $resp == *ok* ]]; then
            return 0
        fi
        if (( attempt < 5 )); then
            sleep 2
        fi
    done
    return 1
}

restore_snapshot() {
    local snapshot=$1 target
    [[ -d $snapshot ]] || die "Snapshot does not exist: $snapshot"
    log WARN "Restoring snapshot $snapshot"
    if [[ -d $snapshot/nginx-sites-available ]]; then
        install -d "$NGINX_ROOT/sites-available" "$NGINX_ROOT/conf.d" || return 1
        rsync -ac --delete "$snapshot/nginx-sites-available/" "$NGINX_ROOT/sites-available/" || return 1
        rsync -ac --delete "$snapshot/nginx-conf.d/" "$NGINX_ROOT/conf.d/" || return 1
    fi
    if [[ -d $snapshot/app ]]; then
        target=${APP_DEST_DIR:-/opt/todo-app}
        install -d "$target" || return 1
        rsync -ac --delete --exclude '/config/' --exclude '/.env' "$snapshot/app/" "$target/" || return 1
        chown -R "${APP_OWNER:-todo:todo}" "$target" || return 1
    fi
    if [[ -d $snapshot/nginx-sites-available ]] && command -v nginx >/dev/null 2>&1; then
        if ! nginx -t; then
            log ERROR 'Restored Nginx config failed nginx -t; service was not reloaded'
            return 1
        fi
        systemctl reload nginx || return 1
    fi
    if [[ -d $snapshot/app && -n ${APP_SERVICE:-} ]]; then
        systemctl restart "$APP_SERVICE" || { log ERROR "Could not restart $APP_SERVICE after rollback"; return 1; }
    fi
}

if (( ROLLBACK_ONLY )); then
    last_good="$BACKUP_ROOT/last_good"
    [[ -L $last_good ]] || die "No last_good snapshot exists in $BACKUP_ROOT"
    restore_snapshot "$(readlink -f -- "$last_good")"
    log INFO 'Manual rollback completed'
    exit 0
fi

[[ -d $SOURCE ]] || die "Source directory does not exist: $SOURCE"
if [[ $TARGET == nginx || $TARGET == all ]]; then
    command -v nginx >/dev/null 2>&1 || die 'nginx is required for nginx/all deployment'
    [[ -d $SOURCE/nginx/sites-available && -d $SOURCE/nginx/conf.d ]] || die "Expected nginx/sites-available and nginx/conf.d under $SOURCE"
fi
if [[ $TARGET == app || $TARGET == all ]]; then
    [[ -d $SOURCE/app ]] || die "Expected app/ under $SOURCE"
fi

stamp=$(date +%Y%m%d-%H%M%S)
SNAPSHOT=$(mktemp -d "$BACKUP_ROOT/snapshot-$stamp-XXXXXX")
if [[ $TARGET == nginx || $TARGET == all ]]; then
    mkdir -p "$SNAPSHOT/nginx-sites-available" "$SNAPSHOT/nginx-conf.d"
    [[ ! -d $NGINX_ROOT/sites-available ]] || rsync -a "$NGINX_ROOT/sites-available/" "$SNAPSHOT/nginx-sites-available/"
    [[ ! -d $NGINX_ROOT/conf.d ]] || rsync -a "$NGINX_ROOT/conf.d/" "$SNAPSHOT/nginx-conf.d/"
fi
if [[ $TARGET == app || $TARGET == all ]]; then
    mkdir -p "$SNAPSHOT/app"
    current_app=${APP_DEST_DIR:-/opt/todo-app}
    [[ ! -d $current_app ]] || rsync -a --exclude '/config/' --exclude '/.env' "$current_app/" "$SNAPSHOT/app/"
fi
log INFO "Created pre-deploy snapshot $SNAPSHOT"

rollback_on_failure() {
    local rc=${1:-$?}
    trap - ERR
    log ERROR "Deployment failed (exit $rc); rolling back to $SNAPSHOT"
    local alert_body
    printf -v alert_body 'Host: %s\nSnapshot: %s\nExit status: %s' "$(hostname)" "$SNAPSHOT" "$rc"
    if restore_snapshot "$SNAPSHOT"; then
        alert 'Deployment rolled back' "$alert_body" || true
    else
        alert 'Deployment rollback failed' "${alert_body}"$'\nManual recovery is required.' || true
    fi
    exit "$rc"
}
trap 'rollback_on_failure "$?"' ERR

# Deploy/restart the app before the Nginx health probe so `-t all` verifies the new release.
if [[ $TARGET == app || $TARGET == all ]]; then
    current_app=${APP_DEST_DIR:-/opt/todo-app}
    owner=${APP_OWNER:-todo:todo}
    install -d "$current_app"
    rsync -ac --delete --exclude '/config/' --exclude '/.env' "$SOURCE/app/" "$current_app/"
    chown -R "$owner" "$current_app"
    find "$current_app" -type d -exec chmod 0750 {} +
    find "$current_app" -type f -exec chmod 0640 {} +
    [[ -z ${APP_SERVICE:-} ]] || systemctl restart "$APP_SERVICE"
fi

if [[ $TARGET == nginx || $TARGET == all ]]; then
    install -d "$NGINX_ROOT/sites-available" "$NGINX_ROOT/conf.d"
    rsync -ac --delete "$SOURCE/nginx/sites-available/" "$NGINX_ROOT/sites-available/"
    rsync -ac --delete "$SOURCE/nginx/conf.d/" "$NGINX_ROOT/conf.d/"
    chown -R root:root "$NGINX_ROOT/sites-available" "$NGINX_ROOT/conf.d"
    find "$NGINX_ROOT/sites-available" "$NGINX_ROOT/conf.d" -type d -exec chmod 0755 {} +
    find "$NGINX_ROOT/sites-available" "$NGINX_ROOT/conf.d" -type f -exec chmod 0644 {} +
    nginx -t
    systemctl reload nginx
fi

# Verify deployed endpoints: app directly via HEALTH_URL, Nginx via NGINX_HEALTH_URL + Host header.
require_cmd curl
if [[ $TARGET == app || $TARGET == all ]]; then
    health_url=${HEALTH_URL:-http://127.0.0.1:5000/health}
    if ! verify_endpoint "$health_url"; then
        log ERROR "App health verification failed at $health_url"
        rollback_on_failure 1
    fi
    log INFO "Verified app health endpoint: $health_url"
fi
if [[ $TARGET == nginx || $TARGET == all ]]; then
    nginx_health_url=${NGINX_HEALTH_URL:-https://127.0.0.1/health}
    app_domain=${APP_DOMAIN:-app.lab.local}
    if ! verify_endpoint "$nginx_health_url" "$app_domain"; then
        log ERROR "Nginx health verification failed at $nginx_health_url (Host: $app_domain)"
        rollback_on_failure 1
    fi
    log INFO "Verified Nginx health endpoint: $nginx_health_url (Host: $app_domain)"
fi

ln -sfn "$SNAPSHOT" "$BACKUP_ROOT/last_good"
# Keep the last N snapshots (including this successful pre-deploy snapshot).
mapfile -t old_snapshots < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'snapshot-*' -printf '%T@ %p\n' | sort -nr | awk -v keep="$KEEP" 'NR > keep { $1=""; sub(/^ /, ""); print }')
for old in "${old_snapshots[@]}"; do
    [[ $(readlink -f -- "$BACKUP_ROOT/last_good") == "$old" ]] || rm -rf -- "$old"
done
trap - ERR
log INFO "Deployment succeeded; snapshot: $SNAPSHOT"
