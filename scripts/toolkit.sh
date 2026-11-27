#!/usr/bin/env bash
# toolkit.sh — interactive entry point for the Linux Project operations toolkit.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: toolkit.sh [-c COMMAND] [-h|--help]

Without -c, show the interactive operations menu.
Commands: deploy, backup, restore-list, restore, healthcheck, logrotate, shellcheck
EOF
}

if [[ ${1:-} == --help ]]; then usage; exit 0; fi

run_script() {
    local name=$1
    shift
    local target="$SCRIPT_DIR/$name"
    local sudo_target="/usr/local/sbin/$name"
    [[ -x $target ]] || die "Toolkit command is not executable: $target"
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        if "$target" "$@"; then
            return 0
        else
            local rc=$?
            return "$rc"
        fi
    fi

    case $name in
        backup.sh)
            # TV1 grants Hưng this exact path, not its /usr/local/sbin symlink.
            sudo /opt/lab-toolkit/scripts/backup.sh "$@"
            ;;
        deploy.sh|healthcheck.sh|logrotate.sh)
            sudo "$sudo_target" "$@"
            ;;
        restore.sh)
            log WARN "Restore changes application data and is restricted to authorized administrators."
            local rc=0
            sudo -n "$sudo_target" "$@" || rc=$?
            if (( rc != 0 )); then
                log ERROR "Restore was denied or failed (exit $rc); ask an authorized administrator to run it."
            fi
            return "$rc"
            ;;
        *)
            log ERROR "No sudo rule configured for $name"
            return 1
            ;;
    esac
}

run_command() {
    case $1 in
        deploy) run_script deploy.sh "${@:2}" ;;
        backup) run_script backup.sh "${@:2}" ;;
        restore-list) run_script restore.sh -l "${@:2}" ;;
        restore) run_script restore.sh "${@:2}" ;;
        healthcheck) run_script healthcheck.sh "${@:2}" ;;
        logrotate) run_script logrotate.sh "${@:2}" ;;
        shellcheck)
            if ! command -v shellcheck >/dev/null 2>&1; then
                log ERROR "Required command not found: shellcheck"
                return 1
            fi
            shellcheck -x "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh
            ;;
        *) die "Unknown command: $1" ;;
    esac
}

COMMAND=
while getopts '+:c:h' opt; do
    case $opt in
        c) COMMAND=$OPTARG; break ;;
        h) usage; exit 0 ;;
        :) usage >&2; die "Option -$OPTARG requires a value" ;;
        *) usage >&2; die "Unknown option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
if [[ -n $COMMAND ]]; then
    run_command "$COMMAND" "$@"
    exit $?
fi
[[ $# -eq 0 ]] || { usage >&2; die "Unexpected arguments: $*"; }

while true; do
    cat <<'EOF'

Linux Project — Operations Toolkit
  1) Deploy / rollback
  2) Backup (TV4)
  3) List backups (TV4)
  4) Restore backup (TV4; destructive, requires confirmation)
  5) Health check
  6) Rotate a log
  7) Run ShellCheck on scripts/
  0) Exit
EOF
    if ! read -r -p 'Choose [0-7]: ' choice; then
        printf '\nEOF received; exiting menu.\n'
        break
    fi
    case $choice in
        1) command_name=deploy ;;
        2) command_name=backup ;;
        3) command_name=restore-list ;;
        4) command_name=restore ;;
        5) command_name=healthcheck ;;
        6) command_name=logrotate ;;
        7) command_name=shellcheck ;;
        0) break ;;
        *) log WARN "Invalid menu choice: '${choice}'"; continue ;;
    esac
    if run_command "$command_name"; then
        log INFO "Command $command_name completed"
    else
        rc=$?
        log ERROR "Command $command_name failed (exit $rc); returning to menu"
    fi
done
