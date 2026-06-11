#!/usr/bin/env bash
# =============================================================================
#  wallpaper-monitor.sh
# -----------------------------------------------------------------------------
#  Runs in the background and watches for any wallpaper change -- whether
#  triggered by the rotator script or by you manually clicking around in
#  GNOME Settings -> Appearance. Each change gets logged.
#
#  How it tags each change:
#    - The rotator script (rotate-wallpaper.sh) writes a small "marker" file
#      RIGHT BEFORE it changes the wallpaper via gsettings. The CONTENTS of
#      the marker is the event tag to log -- "AUTO" for a scheduled
#      rotation, "CHANGE" when triggered by the wallpaper-change alias.
#    - This monitor watches gsettings for changes. When a change arrives:
#         * If the marker file exists -> read its contents as the event
#           tag, log under that tag, delete the marker.
#         * If no marker file        -> it was you, via Settings. Log MANUAL.
#
#  This script is launched and supervised by wallpaper-monitor.service so it
#  starts automatically at login and restarts if it ever crashes.
# =============================================================================

set -euo pipefail

# Talk to the GNOME settings daemon over D-Bus. systemd user services usually
# inherit this; the fallback covers the case where they don't.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# The marker file the rotator drops before each automatic change.
# Lives in /run/user/$UID (a tmpfs that auto-clears at reboot), so we never
# have to worry about stale markers from a previous session.
MARKER="/run/user/$(id -u)/wallpaper-rotator.auto"

# Central log helper -- everything funnels through this script for
# consistent formatting and trimming.
LOGGER="$HOME/.local/bin/wallpaper-rotator/wallpaper-log"

# `gsettings monitor` streams a line every time the value changes:
#     picture-uri: 'file:///home/b3n/.local/share/backgrounds/foo.jpg'
# We loop over those lines and decide AUTO vs MANUAL for each one.
gsettings monitor org.gnome.desktop.background picture-uri | while IFS= read -r line; do
    # Strip everything up to and including the first "'" and the trailing "'".
    # That leaves us with just the URI (file:///...).
    uri=$(printf '%s' "$line" | sed -E "s/^[^']*'//; s/'$//")
    # Drop the "file://" prefix so the log shows a clean absolute path.
    path=${uri#file://}

    if [ -f "$MARKER" ]; then
        # Rotator just made this change. Use the marker contents as the
        # event tag (defaults to AUTO; "CHANGE" when via wallpaper-change).
        # Trim whitespace and fall back to AUTO if the marker is empty.
        event=$(tr -d '[:space:]' < "$MARKER")
        rm -f "$MARKER"
        "$LOGGER" "${event:-AUTO}" "$path"
    else
        # No marker -> a human (you) changed the wallpaper via Settings.
        "$LOGGER" MANUAL "$path"
    fi
done
