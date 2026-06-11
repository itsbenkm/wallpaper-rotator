#!/usr/bin/env bash

USER_HOME=$HOME
INSTALL_DIR="$USER_HOME/.local/bin/wallpaper-rotator"
SYSTEMD_DIR="$USER_HOME/.config/systemd/user"

echo "Installing Wallpaper Rotator for user: $USER"

# 1. Create installation directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$SYSTEMD_DIR"

# 2. Copy scripts
cp rotate-wallpaper.sh "$INSTALL_DIR/"
cp wallpaper-monitor.sh "$INSTALL_DIR/"
cp wallpaper-log "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR/rotate-wallpaper.sh"
chmod +x "$INSTALL_DIR/wallpaper-monitor.sh"
chmod +x "$INSTALL_DIR/wallpaper-log"

echo "Scripts installed to $INSTALL_DIR"

# 3. Copy systemd units
cp rotate-wallpaper.service "$SYSTEMD_DIR/"
cp rotate-wallpaper.timer "$SYSTEMD_DIR/"
cp wallpaper-monitor.service "$SYSTEMD_DIR/"

echo "Systemd units installed to $SYSTEMD_DIR"

# 4. Enable and start systemd units
systemctl --user daemon-reload
systemctl --user enable --now rotate-wallpaper.timer
systemctl --user enable --now wallpaper-monitor.service

echo "Systemd timer and monitor service started."

# 5. Add aliases to .bashrc if not present
BASHRC="$USER_HOME/.bashrc"
if ! grep -q "Wallpaper rotator aliases" "$BASHRC"; then
    echo "Adding aliases to $BASHRC..."
    cat << 'EOF' >> "$BASHRC"

# --- Wallpaper rotator aliases ---
alias wallpaper-off='systemctl --user disable --now rotate-wallpaper.timer && ~/.local/bin/wallpaper-rotator/wallpaper-log OFF'
alias wallpaper-on='systemctl --user enable --now rotate-wallpaper.timer && ~/.local/bin/wallpaper-rotator/wallpaper-log ON'
alias wallpaper-status='echo "$(systemctl --user is-enabled rotate-wallpaper.timer 2>/dev/null || echo disabled) $(systemctl --user is-active rotate-wallpaper.timer 2>/dev/null || echo inactive)"'
alias wallpaper-change='WALLPAPER_EVENT=CHANGE ~/.local/bin/wallpaper-rotator/rotate-wallpaper.sh'
wallpaper-duration() {
    if [ -z "$1" ]; then
        echo "Usage: wallpaper-duration <time> (e.g. 5min, 1h)"
        return 1
    fi
    sed -i "s/^OnUnitActiveSec=.*/OnUnitActiveSec=$1/" ~/.config/systemd/user/rotate-wallpaper.timer
    systemctl --user daemon-reload
    if systemctl --user is-active --quiet rotate-wallpaper.timer; then
        systemctl --user restart rotate-wallpaper.timer
    fi
    ~/.local/bin/wallpaper-rotator/wallpaper-log INTERVAL "-> $1"
}
EOF
    echo "Aliases added. Run 'source ~/.bashrc' or open a new terminal to use them."
fi

echo ""
echo "Installation complete!"
echo "Your wallpaper will now rotate automatically. Check the log at ~/Desktop/wallpaper-rotator/wallpaper.log"
