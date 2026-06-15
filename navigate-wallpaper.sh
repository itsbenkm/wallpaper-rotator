#!/usr/bin/env bash
# =============================================================================
#  navigate-wallpaper.sh
# -----------------------------------------------------------------------------
#  Allows navigating back and forth through the history of set wallpapers.
#  Usage:
#      navigate-wallpaper.sh PREV
#      navigate-wallpaper.sh NEXT
# =============================================================================

set -euo pipefail

DIRECTION="${1:-}"
if [[ "$DIRECTION" != "PREV" && "$DIRECTION" != "NEXT" ]]; then
    echo "Usage: navigate-wallpaper.sh [PREV|NEXT]"
    exit 1
fi

export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
# Canonical log path: kept within the cloned project directory.
REPO_DIR="<REPO_DIR_PLACEHOLDER>"
LOG="${WALLPAPER_LOG:-$REPO_DIR/wallpaper.log}"
OFFSET_FILE="/run/user/$(id -u)/wallpaper-rotator.offset"

# Guard: detect a moved/deleted project folder (the repo path was baked in at
# install time) so the user gets a clear message instead of a misleading
# "no history found".
if [ -z "${WALLPAPER_LOG:-}" ] && [ ! -d "$REPO_DIR" ]; then
    echo "wallpaper-rotator: project folder '$REPO_DIR' not found (moved or deleted)." >&2
    echo "Re-run install.sh from its new location." >&2
    exit 1
fi

if [ ! -f "$LOG" ]; then
    echo "No wallpaper history found."
    exit 1
fi

# Load the base history (ignore ON, OFF, INTERVAL, PREV, NEXT entries).
# Skip any wallpaper whose file no longer exists on disk, so navigation never
# tries to set a deleted image (which GNOME would render as a blank background).
history_list=()
last_added=""
while IFS= read -r line; do
    # Skip blanks, files that no longer exist, and CONSECUTIVE duplicates
    # (the same wallpaper logged twice in a row, e.g. a manual re-set) so
    # prev/next always move to a visibly different image instead of sticking
    # on the same one. Non-consecutive repeats (a -> b -> a) are preserved.
    if [ -n "$line" ] && [ -f "$line" ] && [ "$line" != "$last_added" ]; then
        history_list+=("$line")
        last_added="$line"
    fi
done < <(grep -E ' (AUTO|CHANGE|MANUAL) ' "$LOG" | sed -E 's/^.{19}[[:space:]]+[^[:space:]]+[[:space:]]+//')

count=${#history_list[@]}
if [ "$count" -eq 0 ]; then
    echo "No wallpaper history available to navigate."
    exit 1
fi

# Read current offset (default 0 means head of history)
offset=0
if [ -f "$OFFSET_FILE" ]; then
    offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
fi

if [ "$DIRECTION" = "PREV" ]; then
    new_offset=$((offset + 1))
    if [ "$new_offset" -ge "$count" ]; then
        echo "You have reached the beginning of your wallpaper history."
        exit 1
    fi
elif [ "$DIRECTION" = "NEXT" ]; then
    if [ "$offset" -eq 0 ]; then
        echo -e "\033[0;33mHeads up!\033[0m Use \033[1mwallpaper-change\033[0m to see a new wallpaper."
        echo -e "The \033[1mwallpaper-next\033[0m command is preserved for when you are navigating back through previous wallpapers."
        exit 0
    fi
    new_offset=$((offset - 1))
else
    exit 1
fi

# Calculate the target index (0-based, oldest is 0, newest is count-1)
target_idx=$((count - 1 - new_offset))
target_path="${history_list[$target_idx]}"

# Safety net: the history is already filtered to existing files, but guard anyway.
if [ -z "$target_path" ] || [ ! -f "$target_path" ]; then
    echo "That wallpaper file no longer exists on disk."
    exit 1
fi

# Drop the marker so the monitor logs this as a navigation event, NOT a MANUAL change.
# This ensures it doesn't get added to the base history array, and prevents the monitor
# from resetting our offset.
MARKER="/run/user/$(id -u)/wallpaper-rotator.auto"
echo "$DIRECTION" > "$MARKER"

# Set the wallpaper
uri="file://$target_path"
gsettings set org.gnome.desktop.background picture-uri "$uri"
gsettings set org.gnome.desktop.background picture-uri-dark "$uri"

# Save the new offset
echo "$new_offset" > "$OFFSET_FILE"

if [ "$new_offset" -eq 0 ]; then
    echo "Returned to the most recent wallpaper."
else
    echo "Showing historical wallpaper ($new_offset step(s) back)."
fi
