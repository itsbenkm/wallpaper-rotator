#!/usr/bin/env bash
# =============================================================================
#  rotate-wallpaper.sh
# -----------------------------------------------------------------------------
#  Picks a random image from a folder and sets it as the GNOME desktop
#  wallpaper (for both the light and dark theme).
#
#  This script is launched on a schedule by the systemd user timer in
#  rotate-wallpaper.timer (which triggers rotate-wallpaper.service).
#
#  To run it manually for testing:
#      ~/.local/bin/wallpaper-rotator/rotate-wallpaper.sh
#  Or via systemd (same thing):
#      systemctl --user start rotate-wallpaper.service
# =============================================================================

# `set -e`  -> exit immediately if any command fails
# `set -u`  -> treat unset variables as errors (catches typos)
# `set -o pipefail` -> if any command in a pipeline fails, the whole pipeline fails
# Together these make the script "fail fast" instead of silently doing the wrong thing.
set -euo pipefail

# -----------------------------------------------------------------------------
#  CONFIG: where the wallpaper images live
# -----------------------------------------------------------------------------
# This is the folder GNOME's Settings -> Appearance "Add Picture..." button
# copies images into. If you ever want to point this at a different folder
# (e.g. ~/Pictures/Wallpapers), either:
#   1) edit the path below, OR
#   2) set the WALLPAPER_DIR env var in rotate-wallpaper.service like:
#        Environment=WALLPAPER_DIR=%h/Pictures/Wallpapers
#
# The "${VAR:-default}" syntax means: use $VAR if it's set, otherwise use the default.
WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/.local/share/backgrounds}"

# -----------------------------------------------------------------------------
#  Make sure we can talk to the GNOME settings daemon (D-Bus)
# -----------------------------------------------------------------------------
# `gsettings` needs to reach the GNOME settings daemon over D-Bus. When you
# run this script from a terminal, DBUS_SESSION_BUS_ADDRESS is already set
# for you. When systemd runs it in the background, it usually is too -- but
# just in case it isn't, we point it at the standard user bus socket.
# `$(id -u)` prints your numeric user ID (e.g. 1000), so the socket path
# becomes something like /run/user/1000/bus.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# -----------------------------------------------------------------------------
#  Build the list of candidate images
# -----------------------------------------------------------------------------
# `find` walks WALLPAPER_DIR and emits every image file it sees.
#   -maxdepth 1   : don't recurse into subfolders
#   -type f       : files only (no directories or symlinks-to-dirs)
#   -iname '*.jpg': case-insensitive match (so .JPG works too)
#   -print0       : separate filenames with a NUL byte instead of a newline,
#                   so filenames containing spaces/newlines don't break things
#
# `mapfile -d ''` reads that NUL-separated stream into the bash array `images`.
# Add more extensions to the list below if you have other image formats.
mapfile -d '' images < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' \) -print0)

# If the folder is empty (or doesn't exist), bail out with a clear error.
# `>&2` sends the message to stderr, which is the right place for errors;
# systemd will capture it and you can read it later with:
#     journalctl --user -u rotate-wallpaper.service
if [ "${#images[@]}" -eq 0 ]; then
    echo "No wallpapers found in $WALLPAPER_DIR" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
#  Figure out which wallpaper is currently set (so we can avoid repeats)
# -----------------------------------------------------------------------------
# `gsettings get` returns a value wrapped in single quotes, e.g.
#     'file:///home/b3n/.local/share/backgrounds/foo.jpg'
# The pipeline strips the quotes (`tr -d "'"`) and the "file://" prefix (`sed`)
# so we're left with a plain absolute path we can compare against.
current="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null | tr -d "'" | sed 's|^file://||')"

# -----------------------------------------------------------------------------
#  Pick a random image, retrying if we happen to pick the current one
# -----------------------------------------------------------------------------
# `$RANDOM` is a bash built-in that returns a random integer 0..32767.
# `% ${#images[@]}` wraps it into the valid index range for the array.
pick="${images[RANDOM % ${#images[@]}]}"

# If there's only one image, we have no choice but to "rotate" to itself.
# Otherwise, keep re-rolling until we get something different from the
# currently-set wallpaper. This prevents the boring case where the timer
# fires but nothing visibly changes.
if [ "${#images[@]}" -gt 1 ]; then
    while [ "$pick" = "$current" ]; do
        pick="${images[RANDOM % ${#images[@]}]}"
    done
fi

# -----------------------------------------------------------------------------
#  Apply the new wallpaper
# -----------------------------------------------------------------------------
# GNOME wants a URI, not a path -- so we prepend "file://".
# We set BOTH picture-uri and picture-uri-dark so the wallpaper updates
# whether your system is currently in light or dark mode.
uri="file://$pick"

# Drop a marker file RIGHT BEFORE changing the wallpaper. The
# wallpaper-monitor service watches for gsettings changes; when it sees one
# it checks for this marker:
#   - marker present -> this change came from this script. The MARKER FILE
#                       CONTENTS are used as the log event tag (default
#                       "AUTO"; can be overridden via WALLPAPER_EVENT env
#                       var, e.g. "CHANGE" when invoked by wallpaper-change).
#   - marker absent  -> change came from you (GNOME Settings) -> log as MANUAL
# /run/user/$UID is a tmpfs that auto-clears at logout, so stale markers
# can never survive a session boundary.
MARKER="/run/user/$(id -u)/wallpaper-rotator.auto"
echo "${WALLPAPER_EVENT:-AUTO}" > "$MARKER"

gsettings set org.gnome.desktop.background picture-uri "$uri"
gsettings set org.gnome.desktop.background picture-uri-dark "$uri"

# Note: we no longer echo "Wallpaper set: ..." here -- the monitor logs the
# event with timestamp, so a duplicate would just be noise. To debug, watch
# the live log:  tail -f ~/Desktop/wallpaper-rotator/wallpaper.log
