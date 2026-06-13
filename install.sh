#!/usr/bin/env bash
set -euo pipefail

USER_HOME=$HOME
INSTALL_DIR="$USER_HOME/.local/bin/wallpaper-rotator"
SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
STATE_DIR="${XDG_STATE_HOME:-$USER_HOME/.local/state}/wallpaper-rotator"
LOG_FILE="$STATE_DIR/wallpaper.log"

echo "Installing Wallpaper Rotator for user: $USER"

# -----------------------------------------------------------------------------
# 0. Preflight: this tool targets GNOME running on a systemd user session.
# -----------------------------------------------------------------------------
if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: systemctl not found. Wallpaper Rotator needs systemd (user services)." >&2
    exit 1
fi
if ! command -v gsettings >/dev/null 2>&1 || \
   ! gsettings list-schemas 2>/dev/null | grep -q '^org.gnome.desktop.background$'; then
    echo "Error: this tool requires GNOME -- it sets the wallpaper via gsettings." >&2
    echo "GNOME ships by default with Ubuntu. On other desktops this won't work." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# 1. Create installation directories
# -----------------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"
mkdir -p "$SYSTEMD_DIR"

# -----------------------------------------------------------------------------
# 2. Copy scripts
# -----------------------------------------------------------------------------
cp rotate-wallpaper.sh "$INSTALL_DIR/"
cp navigate-wallpaper.sh "$INSTALL_DIR/"
cp wallpaper-monitor.sh "$INSTALL_DIR/"
cp wallpaper-log "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR/rotate-wallpaper.sh"
chmod +x "$INSTALL_DIR/navigate-wallpaper.sh"
chmod +x "$INSTALL_DIR/wallpaper-monitor.sh"
chmod +x "$INSTALL_DIR/wallpaper-log"

echo "Scripts installed to $INSTALL_DIR"

# -----------------------------------------------------------------------------
# 3. Set up the log location (XDG state dir) + a clickable Desktop shortcut
# -----------------------------------------------------------------------------
mkdir -p "$STATE_DIR"

# Figure out the real Desktop folder (handles localized names like "Bureau").
DESKTOP_DIR="$( (command -v xdg-user-dir >/dev/null 2>&1 && xdg-user-dir DESKTOP) || true )"
[ -z "$DESKTOP_DIR" ] && DESKTOP_DIR="$USER_HOME/Desktop"
[ "$DESKTOP_DIR" = "$USER_HOME" ] && DESKTOP_DIR="$USER_HOME/Desktop"
mkdir -p "$DESKTOP_DIR"

# Drop a symlink on the Desktop so you can open/tail the log any time. The real
# file lives in the state dir; the symlink survives the log's atomic trims.
ln -sf "$LOG_FILE" "$DESKTOP_DIR/wallpaper-rotator.log"
echo "Log shortcut on Desktop: $DESKTOP_DIR/wallpaper-rotator.log"

# Make sure the default wallpaper folder exists so the timer doesn't error out
# on a brand-new user who hasn't added any pictures yet.
mkdir -p "$USER_HOME/.local/share/backgrounds"

# -----------------------------------------------------------------------------
# 4. Copy systemd units
# -----------------------------------------------------------------------------
cp rotate-wallpaper.service "$SYSTEMD_DIR/"
cp rotate-wallpaper.timer "$SYSTEMD_DIR/"
cp wallpaper-monitor.service "$SYSTEMD_DIR/"

echo "Systemd units installed to $SYSTEMD_DIR"

# -----------------------------------------------------------------------------
# 5. Enable and start systemd units
# -----------------------------------------------------------------------------
systemctl --user daemon-reload
systemctl --user enable --now rotate-wallpaper.timer
systemctl --user enable --now wallpaper-monitor.service

echo "Systemd timer and monitor service started."

# -----------------------------------------------------------------------------
# 6. Add aliases to .bashrc if not present
# -----------------------------------------------------------------------------
BASHRC="$USER_HOME/.bashrc"
if ! grep -q "Wallpaper rotator aliases" "$BASHRC" 2>/dev/null; then
    echo "Adding aliases to $BASHRC..."
    cat << 'EOF' >> "$BASHRC"

# --- Wallpaper rotator aliases ---
alias wallpaper-off='systemctl --user disable --now rotate-wallpaper.timer && ~/.local/bin/wallpaper-rotator/wallpaper-log OFF'
alias wallpaper-on='systemctl --user enable --now rotate-wallpaper.timer && ~/.local/bin/wallpaper-rotator/wallpaper-log ON'
wallpaper-status() {
    if ! systemctl --user is-active --quiet rotate-wallpaper.timer; then
        echo -e "\033[0;31mInactive\033[0m"
        return
    fi
    local interval next_us next_s now_s diff left=""
    interval=$(grep -E '^OnUnitActiveSec=' ~/.config/systemd/user/rotate-wallpaper.timer 2>/dev/null | cut -d'=' -f2)
    # The 'next' field from list-timers JSON is an absolute CLOCK_REALTIME timestamp
    # in microseconds. We compute the countdown ourselves, so it's locale-independent
    # (unlike scraping the human table) and format-stable (unlike `show`'s elapse
    # properties, which render as a human duration on some systemd versions).
    # If --output=json isn't supported, next_us is empty and we just show the interval.
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
alias wallpaper-change='WALLPAPER_EVENT=CHANGE ~/.local/bin/wallpaper-rotator/rotate-wallpaper.sh'
alias wallpaper-prev='~/.local/bin/wallpaper-rotator/navigate-wallpaper.sh PREV'
alias wallpaper-next='~/.local/bin/wallpaper-rotator/navigate-wallpaper.sh NEXT'
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
# --- End wallpaper rotator aliases ---
EOF
    echo "Aliases added. Run 'source ~/.bashrc' or open a new terminal to use them."
fi

echo ""
echo "Installation complete!"
echo "Your wallpaper will now rotate automatically."
echo "View the log any time at: $DESKTOP_DIR/wallpaper-rotator.log"
echo "(the real file lives at $LOG_FILE)"
