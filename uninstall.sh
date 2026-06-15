#!/usr/bin/env bash
# =============================================================================
#  uninstall.sh -- cleanly remove Wallpaper Rotator
# -----------------------------------------------------------------------------
#  Reverses install.sh: stops & disables the systemd units, removes the unit
#  files and installed scripts, and strips the alias source line from
#  ~/.bashrc. Your log history (wallpaper.log in the project folder) is kept --
#  the script tells you where, so you can delete it yourself if you want.
# =============================================================================
set -uo pipefail   # not -e: we want to keep going even if a piece is already gone

USER_HOME=$HOME
INSTALL_DIR="$USER_HOME/.local/bin/wallpaper-rotator"
SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
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

# 4. Strip the alias block from ~/.bashrc
if [ -f "$BASHRC" ] && grep -q "source ~/.local/bin/wallpaper-rotator/aliases.sh" "$BASHRC"; then
    # Temp file beside ~/.bashrc so the mv is an atomic same-filesystem rename.
    tmp=$(mktemp -p "$(dirname "$BASHRC")")
    grep -v "source ~/.local/bin/wallpaper-rotator/aliases.sh" "$BASHRC" > "$tmp"
    mv "$tmp" "$BASHRC"
    echo "Removed the alias source line from ~/.bashrc (open a new terminal to refresh)."
fi

echo ""
echo "Uninstall complete."
echo "Your log history was left in the cloned directory: $PWD/wallpaper.log"
echo "Delete it with:  rm -f \"$PWD/wallpaper.log\"   (if you don't want to keep it)"
