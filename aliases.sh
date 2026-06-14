#!/usr/bin/env bash
# =============================================================================
#  aliases.sh -- Wallpaper Rotator
# -----------------------------------------------------------------------------
#  This file provides the user-facing commands (aliases and functions) for
#  controlling the Wallpaper Rotator. It is meant to be sourced in ~/.bashrc.
# =============================================================================

alias wallpaper-off='systemctl --user disable --now rotate-wallpaper.timer && ~/.local/bin/wallpaper-rotator/wallpaper-log OFF'
alias wallpaper-on='systemctl --user enable --now rotate-wallpaper.timer && ~/.local/bin/wallpaper-rotator/wallpaper-log ON'
alias wallpaper-change='WALLPAPER_EVENT=CHANGE ~/.local/bin/wallpaper-rotator/rotate-wallpaper.sh'
alias wallpaper-prev='~/.local/bin/wallpaper-rotator/navigate-wallpaper.sh PREV'
alias wallpaper-next='~/.local/bin/wallpaper-rotator/navigate-wallpaper.sh NEXT'

wallpaper-status() {
    if ! systemctl --user is-active --quiet rotate-wallpaper.timer; then
        echo -e "\033[0;31mInactive\033[0m"
        return
    fi
    local interval next_us next_s now_s diff left=""
    interval=$(grep -E '^OnUnitActiveSec=' ~/.config/systemd/user/rotate-wallpaper.timer 2>/dev/null | cut -d'=' -f2)
    next_us=$(systemctl --user list-timers rotate-wallpaper.timer --no-pager --output=json 2>/dev/null \
        | sed -n 's/.*"next":\([0-9]\+\).*/\1/p')
    if [ -n "$next_us" ] && [ "$next_us" != "0" ]; then
        next_s=$((next_us / 1000000))
        now_s=$(date +%s)
        diff=$((next_s - now_s))
        if [ "$diff" -gt 0 ]; then
            if [ "$diff" -ge 3600 ]; then left=" (next in ~$((diff/3600))h $(((diff%3600)/60))m)"
            elif [ "$diff" -ge 60 ]; then left=" (next in ~$((diff/60))m)"
            else left=" (next in ~${diff}s)"; fi
        fi
    fi
    echo -e "\033[0;32mActive\033[0m -- rotates every ${interval:-?}${left}"
}

wallpaper-duration() {
    if [ -z "${1:-}" ]; then
        local current=$(grep "^OnUnitActiveSec=" ~/.config/systemd/user/rotate-wallpaper.timer 2>/dev/null | cut -d'=' -f2 || echo "Unknown")
        echo -e "Current rotation interval: \033[1m$current\033[0m"
        echo "To change it, use: wallpaper-duration <time> (e.g. 30s, 5min, 1h, 1d)"
        return 0
    fi
    if ! [[ "$1" =~ ^[0-9]+(s|sec|secs|seconds?|m|min|mins|minutes?|h|hr|hrs|hours?|d|days?)?$ ]]; then
        echo -e "\033[0;31mInvalid duration '$1'.\033[0m Examples: 30s, 5min, 1h, 1d"
        return 1
    fi
    sed -i "s/^OnUnitActiveSec=.*/OnUnitActiveSec=$1/" ~/.config/systemd/user/rotate-wallpaper.timer
    systemctl --user daemon-reload
    if systemctl --user is-active --quiet rotate-wallpaper.timer; then
        systemctl --user restart rotate-wallpaper.timer
    else
        echo -e "\033[0;33mNote:\033[0m timer is paused; run 'wallpaper-on' to start rotating at the new interval."
    fi
    ~/.local/bin/wallpaper-rotator/wallpaper-log INTERVAL "-> $1"
    echo "Rotation interval set to $1."
}

wallpaper-help() {
    cat <<'HELP'
Wallpaper rotator commands:
  wallpaper-on                Turn rotation ON (persistent across reboots).
  wallpaper-off               Turn rotation OFF (persistent across reboots).
  wallpaper-status            Show active/inactive state and the next change.
  wallpaper-change            Rotate to a NEW random wallpaper right now.
  wallpaper-prev              Go back to the previous wallpaper in history.
  wallpaper-next              Go forward (only after using wallpaper-prev).
  wallpaper-duration <time>   Change rotation frequency (e.g. 30s, 5min, 1h, 1d).
  wallpaper-help              Show this help.

Log file: ~/Desktop/wallpaper-rotator.log
HELP
}
