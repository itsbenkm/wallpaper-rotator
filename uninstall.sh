#!/usr/bin/env bash
# =============================================================================
#  uninstall.sh -- cleanly remove Wallpaper Rotator
# -----------------------------------------------------------------------------
#  Reverses install.sh: stops & disables the systemd units, removes the unit
#  files and installed scripts, drops the Desktop log symlink, and strips the
#  alias block from ~/.bashrc. Your log history in the state dir is kept (the
#  script tells you where, so you can delete it yourself if you want).
# =============================================================================
set -uo pipefail   # not -e: we want to keep going even if a piece is already gone

USER_HOME=$HOME
INSTALL_DIR="$USER_HOME/.local/bin/wallpaper-rotator"
SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
STATE_DIR="${XDG_STATE_HOME:-$USER_HOME/.local/state}/wallpaper-rotator"
BASHRC="$USER_HOME/.bashrc"

echo "Uninstalling Wallpaper Rotator..."

# 1. Stop & disable the units (ignore errors if they're already gone)
systemctl --user disable --now rotate-wallpaper.timer 2>/dev/null || true
systemctl --user disable --now wallpaper-monitor.service 2>/dev/null || true

# 2. Remove the unit files and reload
rm -f "$SYSTEMD_DIR/rotate-wallpaper.service" \
      "$SYSTEMD_DIR/rotate-wallpaper.timer" \
      "$SYSTEMD_DIR/wallpaper-monitor.service"
systemctl --user daemon-reload 2>/dev/null || true

# 3. Remove the installed scripts
rm -rf "$INSTALL_DIR"

# 4. Remove the Desktop log symlink (only if it really is a symlink we made)
DESKTOP_DIR="$( (command -v xdg-user-dir >/dev/null 2>&1 && xdg-user-dir DESKTOP) || true )"
[ -z "$DESKTOP_DIR" ] && DESKTOP_DIR="$USER_HOME/Desktop"
[ "$DESKTOP_DIR" = "$USER_HOME" ] && DESKTOP_DIR="$USER_HOME/Desktop"
[ -L "$DESKTOP_DIR/wallpaper-rotator.log" ] && rm -f "$DESKTOP_DIR/wallpaper-rotator.log"

# 5. Strip the alias block from ~/.bashrc (between our two markers, inclusive)
if [ -f "$BASHRC" ] && grep -q "# --- Wallpaper rotator aliases ---" "$BASHRC"; then
    tmp=$(mktemp)
    sed '/# --- Wallpaper rotator aliases ---/,/# --- End wallpaper rotator aliases ---/d' "$BASHRC" > "$tmp"
    mv "$tmp" "$BASHRC"
    echo "Removed the alias block from ~/.bashrc (open a new terminal to refresh)."
fi

echo ""
echo "Uninstall complete."
echo "Your log history was left at: $STATE_DIR"
echo "Delete it with:  rm -rf \"$STATE_DIR\"   (if you don't want to keep it)"
