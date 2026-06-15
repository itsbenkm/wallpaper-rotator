#!/usr/bin/env bash
set -euo pipefail

# Run from the script's own directory so relative copies and the baked-in
# project path are correct even if the installer is invoked from elsewhere.
cd "$(dirname "$(readlink -f "$0")")"

USER_HOME=$HOME
INSTALL_DIR="$USER_HOME/.local/bin/wallpaper-rotator"
SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
# The log lives in the cloned directory to keep everything self-contained.
# (To relocate it, see "Customizing the Log Location" in the README -- that
# requires editing the systemd units, so the installer doesn't bake it in.)
LOG_FILE="$PWD/wallpaper.log"

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
cp aliases.sh "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR/rotate-wallpaper.sh"
chmod +x "$INSTALL_DIR/navigate-wallpaper.sh"
chmod +x "$INSTALL_DIR/wallpaper-monitor.sh"
chmod +x "$INSTALL_DIR/wallpaper-log"

# Patch the installed scripts with the physical location of this repository
# so the log file is kept locally alongside the source code. Escape sed
# metacharacters (&, |, \) so paths containing them don't corrupt the edit.
REPO_DIR_ESC=$(printf '%s' "$PWD" | sed -e 's/[&\\|]/\\&/g')
sed -i "s|<REPO_DIR_PLACEHOLDER>|$REPO_DIR_ESC|g" "$INSTALL_DIR/wallpaper-log"
sed -i "s|<REPO_DIR_PLACEHOLDER>|$REPO_DIR_ESC|g" "$INSTALL_DIR/navigate-wallpaper.sh"

echo "Scripts installed to $INSTALL_DIR"

# -----------------------------------------------------------------------------
# 3. Set up the log location + wallpaper folder
# -----------------------------------------------------------------------------
mkdir -p "$(dirname "$LOG_FILE")"

# The log file is kept locally within the cloned repository.
echo "Log file will be created at: $LOG_FILE"

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
if ! grep -q "source ~/.local/bin/wallpaper-rotator/aliases.sh" "$BASHRC" 2>/dev/null; then
    echo "Adding aliases to $BASHRC..."
    echo '[ -f ~/.local/bin/wallpaper-rotator/aliases.sh ] && source ~/.local/bin/wallpaper-rotator/aliases.sh' >> "$BASHRC"
    echo "Aliases added. Run 'source ~/.bashrc' or open a new terminal to use them."
fi

echo ""
echo "Installation complete!"
echo "Your wallpaper will now rotate automatically."
echo "Log file: $LOG_FILE"
