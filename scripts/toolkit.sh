#!/usr/bin/env bash
# toolkit.sh — interactive entry point for the Linux Project operations toolkit.
set -Eeuo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: toolkit.sh [-c COMMAND [ARGS...]] [-h|--help]

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
    local installed_target="/opt/lab-toolkit/scripts/$name"
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
            # TV1 grants Hưng this exact path, not a /usr/local/sbin symlink.
            sudo "$installed_target" "$@"
            ;;
        deploy.sh|healthcheck.sh|logrotate.sh)
            if [[ -x $sudo_target ]]; then
                sudo "$sudo_target" "$@"
            else
                sudo "$target" "$@"
            fi
            ;;
        restore.sh)
            log WARN "Restore changes application data and is restricted to authorized administrators."
            local rc=0
            if [[ -x $installed_target ]]; then
                sudo -n "$installed_target" "$@" || rc=$?
            else
                sudo -n "$sudo_target" "$@" || rc=$?
            fi
            if (( rc != 0 )); then
                log ERROR "Restore was denied by sudo or failed (exit $rc); only Duy/Du can run restore."
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
    rc=0
    run_command "$COMMAND" "$@" || rc=$?
    exit "$rc"
fi
[[ $# -eq 0 ]] || { usage >&2; die "Unexpected arguments: $*"; }

PROMPT_REPLY=
prompt_field() {
    local prompt_text=$1
    PROMPT_REPLY=
    read -r -p "$prompt_text" PROMPT_REPLY
}

run_interactive_choice() {
    local choice=$1
    local -a args=()
    case $choice in
        1)
            prompt_field 'Action: [1] Deploy, [2] Rollback (-r) [1]: ' || return 1
            if [[ $PROMPT_REPLY == 2 ]]; then
                args=(-r)
            elif [[ -z $PROMPT_REPLY || $PROMPT_REPLY == 1 ]]; then
                prompt_field 'Target [all|nginx|app] (default: all): ' || return 1
                [[ -z $PROMPT_REPLY ]] || args+=(-t "$PROMPT_REPLY")
                prompt_field "Source directory (default: ${APP_SRC_DIR:-/opt/lab-deploy-staging}): " || return 1
                [[ -z $PROMPT_REPLY ]] || args+=(-s "$PROMPT_REPLY")
                prompt_field "Domain Host header (default: ${APP_DOMAIN:-app.lab.local}): " || return 1
                [[ -z $PROMPT_REPLY ]] || args+=(-d "$PROMPT_REPLY")
            else
                log WARN "Invalid deploy action: '$PROMPT_REPLY'"
                return 0
            fi
            run_command deploy "${args[@]}"
            ;;
        2)
            prompt_field 'Local backup only without rsync to VM2 (-n)? [y/N]: ' || return 1
            [[ $PROMPT_REPLY == [yY] ]] && args+=(-n)
            run_command backup "${args[@]}"
            ;;
        3)
            run_command restore-list
            ;;
        4)
            prompt_field 'Part to restore [all|db|web] (default: all): ' || return 1
            [[ -z $PROMPT_REPLY ]] || args+=(-c "$PROMPT_REPLY")
            prompt_field 'Backup file path (Enter for latest): ' || return 1
            [[ -z $PROMPT_REPLY ]] || args+=(-f "$PROMPT_REPLY")
            run_command restore "${args[@]}"
            ;;
        5)
            prompt_field "Mode [local|remote|both] (default: ${HC_MODE:-local}): " || return 1
            [[ -z $PROMPT_REPLY ]] || args+=(-m "$PROMPT_REPLY")
            prompt_field 'Bypass alert cooldown (-N)? [y/N]: ' || return 1
            [[ $PROMPT_REPLY == [yY] ]] && args+=(-N)
            run_command healthcheck "${args[@]}"
            ;;
        6)
            prompt_field "Log file path (default: ${LOGROTATE_TARGET:-/var/log/lab-toolkit.log}): " || return 1
            [[ -z $PROMPT_REPLY ]] || args+=(-f "$PROMPT_REPLY")
            prompt_field "Generations to keep (default: ${LOGROTATE_KEEP:-5}): " || return 1
            [[ -z $PROMPT_REPLY ]] || args+=(-k "$PROMPT_REPLY")
            run_command logrotate "${args[@]}"
            ;;
        7)
            run_command shellcheck
            ;;
        *)
            return 2
            ;;
    esac
}

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
        0) break ;;
        [1-7])
            rc=0
            run_interactive_choice "$choice" || rc=$?
            if (( rc == 0 )); then
                log INFO "Menu option $choice completed"
            else
                log ERROR "Menu option $choice failed (exit $rc); returning to menu"
            fi
            ;;
        *)
            log WARN "Invalid menu choice: '${choice}'"
            ;;
    esac
done
