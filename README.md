# Wallpaper Rotator

This is a small system that automatically rotates your GNOME desktop wallpaper at a chosen interval, using a random image from `~/.local/share/backgrounds/` (the folder GNOME's Settings -> Appearance "Add Picture..." button writes to).

---

## Installation

1. Clone or download this repository.
2. Open your terminal in the downloaded folder.
3. Make the installer executable:
   ```bash
   chmod +x install.sh
   ```
4. Run the installer script:
   ```bash
   ./install.sh
   ```

*(Note: The installer does NOT require `sudo` as it runs entirely in your user space using `systemctl --user`)*.

---

## How It Works

| Component | What it does |
|-----------|--------------|
| `rotate-wallpaper.sh`      | The bash script that picks a random image and sets it as the wallpaper. |
| `rotate-wallpaper.service` | Tells systemd HOW to run the script (one-shot). |
| `rotate-wallpaper.timer`   | Tells systemd WHEN to run it (the schedule). |
| `wallpaper-monitor.sh`     | Background watcher that detects wallpaper changes (auto AND manual) so they can be logged. |
| `wallpaper-monitor.service`| Systemd unit that runs the monitor at login. |
| `wallpaper-log`            | Central logging helper. Every event funnels through this so the log format and 500-line cap stay consistent. |

During installation, the scripts are copied to `~/.local/bin/wallpaper-rotator/` and the systemd units are copied to `~/.config/systemd/user/`.

---

## Turning the rotator ON and OFF (the "on/off switch")

The installer adds a few handy aliases to your `~/.bashrc`. Open any new terminal and use:

```bash
wallpaper-off               # PAUSE rotation (persistent — stays off after reboot)
wallpaper-on                # RESUME rotation (persistent — auto-starts at login)
wallpaper-status            # Check current state
wallpaper-change            # Rotate to a NEW random wallpaper right now
                            # (works whether rotation is on or off; doesn't
                            # reset the schedule)
wallpaper-duration <time>   # Change how often the wallpaper rotates
                            #   e.g. wallpaper-duration 30s
                            #        wallpaper-duration 5min
                            #        wallpaper-duration 1h
                            #        wallpaper-duration 1d
```

All five commands also write an entry to `~/.local/share/wallpaper-rotator/wallpaper.log` so you can see later when you toggled or changed things.

### Typical workflow

1. The rotator is happily rotating, you see a wallpaper you love.
2. Run `wallpaper-off`. The current wallpaper stays put — no more rotation, not now, not after you reboot, not ever, until you turn it back on.
3. Days/weeks later you're bored of that wallpaper.
4. Run `wallpaper-on`. Rotation resumes immediately, then continues on its schedule.

---

## The log file

Everything the rotator does (and everything you do that affects the wallpaper) gets written to:

```
~/.local/share/wallpaper-rotator/wallpaper.log
```

### Event types

| Tag        | When it's written                                                |
|------------|------------------------------------------------------------------|
| `AUTO`     | The rotator picked a new wallpaper on its schedule.              |
| `CHANGE`   | You forced a rotation by running `wallpaper-change`.             |
| `MANUAL`   | You changed the wallpaper yourself (Settings → Appearance).      |
| `ON`       | You ran `wallpaper-on`.                                          |
| `OFF`      | You ran `wallpaper-off`.                                         |
| `INTERVAL` | The rotation interval was changed (via `wallpaper-duration`).    |

### Useful log commands

```bash
# Watch live -- new entries appear as they happen
tail -f ~/.local/share/wallpaper-rotator/wallpaper.log

# Show only manual changes
grep MANUAL ~/.local/share/wallpaper-rotator/wallpaper.log
```

---

## Using a different image folder

By default the script reads from `~/.local/share/backgrounds/`. To point it elsewhere:

1. Edit the service file:
   ```bash
   nano ~/.config/systemd/user/rotate-wallpaper.service
   ```
2. Inside the `[Service]` section, add a line like:
   ```
   Environment=WALLPAPER_DIR=%h/Pictures/Wallpapers
   ```
3. Reload and restart:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart rotate-wallpaper.timer
   ```

---

## Uninstalling completely

If you ever want to nuke the whole setup:

```bash
# Stop and disable the timer + monitor
systemctl --user disable --now rotate-wallpaper.timer
systemctl --user disable --now wallpaper-monitor.service

# Remove the unit files
rm ~/.config/systemd/user/rotate-wallpaper.service
rm ~/.config/systemd/user/rotate-wallpaper.timer
rm ~/.config/systemd/user/wallpaper-monitor.service
systemctl --user daemon-reload

# Remove the scripts and logs
rm -rf ~/.local/bin/wallpaper-rotator
rm -rf ~/.local/share/wallpaper-rotator

# Finally, remove the "# --- Wallpaper rotator aliases ---" block from your ~/.bashrc
```
