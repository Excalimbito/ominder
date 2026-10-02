# Ominder — Specification

Ominder is an Omarchy shell plugin that replaces the built-in `omarchy.reminders` overlay. It adds flexible time input, repeating reminders, snooze, notification sound, and a panel for managing reminders. It is meant to be published on the Omarchy plugin marketplace.

## Principles

- **The CLI is the source of truth.** The overlay, panel, bar widget, and systemd units are thin layers over `bin/ominder`.
- **No new dependencies.** systemd handles timing, `omarchy-notification-send` displays notifications, `pw-play` plays sound, and Qt/QML (already pulled in by Quickshell) runs the time parser.
- **Keyboard-first.** Creating a reminder never requires the mouse.
- **Omarchy theming only.** Use `Style` / `Color` tokens and `qs.Ui` components. No custom visuals.
- **Backward compatible.** `ominder 30 "message"` behaves like `omarchy-reminder 30 "message"`.

## Identity

| Field | Value |
|---|---|
| Plugin id | `io.github.excalimbito.ominder` |
| Repository | `github.com/Excalimbito/ominder` (public) |
| License | MIT, keeping the Omarchy copyright line, because the plugin starts from `omarchy plugin clone omarchy.reminders` |
| `omarchy.clonedFrom` | `omarchy.reminders`. Calls aimed at the built-in id (keybinding, Omarchy menu, Reminder indicator click) route to Ominder. Drop this field if marketplace review objects |

## Manifest

- `kinds`: `["bar-widget", "overlay"]`
  - **bar-widget**: a bell with a count of upcoming reminders. Clicking it opens the management panel, which is loaded by the bar widget, not declared as its own kind.
  - **overlay**: the create/edit flow. `keepLoaded: true`.
- No `service` kind. Sweeping and importing run inside the CLI.

## Storage

| What | Where |
|---|---|
| Reminder data | `~/.local/state/ominder/reminders.json` |
| Settings | The plugin's entry in `~/.config/omarchy/shell.json` (hand-editable, hot-reloads) |
| Scheduling | Real user units in `~/.config/systemd/user/ominder-<id>.timer` / `.service` |
| Hyprland binding stub | `~/.local/state/omarchy/toggles/hypr/ominder.lua` |

Timers do **not** use `Persistent=true`. A reminder whose time passed while the machine was off never fires and is dropped by the next sweep.

### Settings

| Key | Default |
|---|---|
| `sound` | `true` |
| `soundFile` | `/usr/share/sounds/freedesktop/stereo/complete.oga` |
| `snoozeMinutes` | `5` (choices: 5 / 10 / 15 / 30) |

## CLI — `bin/ominder`

The plugin ships the CLI inside its own folder. Everything that uses it (QML, systemd units, the Hyprland stub) calls it by full path. Users who want it on their `PATH` can symlink it themselves.

| Command | Behaviour |
|---|---|
| `ominder <when> [message]` | Create. A bare number means minutes. Empty message → "Reminder" |
| `ominder list [--json]` | List upcoming reminders |
| `ominder rm <id>` | Delete one |
| `ominder edit <id> <when> [message]` | Replace the time and/or message |
| `ominder snooze <id>` | Create a one-time copy `snoozeMinutes` from now |
| `ominder clear` | Delete all one-time reminders |
| `ominder reset [--yes]` | Delete every reminder, including repeating ones. Asks for confirmation unless `--yes` is passed |
| `ominder sweep` | Import `omarchy-reminder-*` transient timers and remove stale entries |
| `ominder panel` | Open the management panel |
| `ominder parse [--json] <when>` | Resolve a time expression, used by the CLI's own create/edit |
| `ominder uninstall` | Remove all units, state, and the Hyprland stub |

**Disabled-plugin pass-through:** if the plugin is disabled, `ominder` hands `show` / `clear` and other legacy calls to `omarchy-reminder "$@"`, so the default keybindings keep working.

## Time grammar

English only. One parser, written in JS (`TimeParser.js`).

| Form | Example |
|---|---|
| Minutes | `30` |
| Duration | `90m`, `1h30m`, `2h` |
| Clock time (today, or tomorrow if already passed) | `14:30` |
| Relative day | `tomorrow 9:00` |
| Weekday | `fri 14:00` |
| ISO date | `2026-10-05 9:00` |
| Repeat by interval | `every 30m` |
| Repeat daily | `every day 8:00` |
| Repeat on chosen days | `every mon,wed 9:00`, `every weekday 9:00` |
| Repeat monthly | `every 1st 10:00` |

Repeats map to `OnCalendar=` or `OnUnitActiveSec=`. Raw `OnCalendar` strings are not accepted.

### One parser, two callers

- **Overlay:** imports `TimeParser.js` directly, so the preview runs without spawning a process on each keystroke.
- **CLI:** asks the running shell with `omarchy-shell shell call <pluginId> parse "<when>"`. If the shell isn't running (TTY, SSH), it falls back to evaluating `TimeParser.js` through `qml6` with `QT_QPA_PLATFORM=offscreen`.

## Create overlay

A single card with a live preview and two stacked fields:

```
→ Thu 14:30 · in 2h10m · daily      ← live preview / inline error
[ when:    tomorrow 9:00         ]
[ message: pay boleto            ]
```

- Tab / Shift+Tab move between fields.
- Enter in *when* moves to *message*. Enter in *message* submits.
- An invalid *when* shows the error on the preview line, not as a notification.
- Escape clears the current field, then closes.
- Edit from the panel opens this overlay with both fields prefilled.

## Panel

Opened from the bar widget or `ominder panel`.

- A list of upcoming reminders: time, message, and a repeat icon. Each row has edit and delete.
- **Clear** removes one-time reminders immediately.
- **Reset** removes everything after an inline confirmation, with no modal dialog.
- **Settings**: sound on/off, sound file, default snooze length.

## Notifications

- Sent through `omarchy-notification-send` with glyph `󰢌`.
- **Left click** snoozes, via `--exec ominder snooze <id>`. **Right click** dismisses (Omarchy's default).
- Snoozing a repeating reminder creates a one-time copy. The repeat schedule is unchanged.
- If `sound` is on, the unit plays `soundFile` with `pw-play` when it fires.

## Keybindings

| Keys | Action |
|---|---|
| `Super+Ctrl+R` | Create overlay (through `clonedFrom`, no rebinding needed) |
| `Super+Ctrl+Alt+R` | Open the panel |
| `Super+Shift+Ctrl+R` | `ominder clear` (one-time reminders only) |

Plugins have no enable/disable/remove hooks, so the bindings are managed like this:

1. When the bar widget loads, it writes `~/.local/state/omarchy/toggles/hypr/ominder.lua`, but only if the file is missing or its contents differ. Omarchy loads that directory on every Hyprland reload. The stub rebinds the two keys only while the plugin folder exists.
2. Right after writing the stub, Ominder applies it live with `hyprctl eval`. It never calls `hyprctl reload`.
3. Disabled plugin: the keys still call `ominder`, which passes the call through to `omarchy-reminder`.
4. Removed plugin: the stub does nothing, so Omarchy's defaults return on the next reload.

## Lifecycle and cleanup

- **On fire (one-time reminder):** the unit sends the notification, deletes its own unit files and state entry, then runs `systemctl --user daemon-reload`.
- **Sweep** (runs on `list`, when the panel opens, and when the bar widget refreshes): imports active `omarchy-reminder-*` timers by stopping each transient timer and recreating it as an Ominder unit with the same fire time and message, then drops past-due one-time entries and orphaned units.
- **Uninstall safety net:** each unit's `ExecStart` checks that `ominder` still exists. If it doesn't, the unit deletes its own files instead of failing.
- **Explicit uninstall:** run `ominder uninstall` before `omarchy plugin remove`. The README documents this.

## Bar widget refresh

The bar widget watches `reminders.json` with a `FileView` (`watchChanges: true`). No polling, no IPC.

## Tests

- `test.js`: a table of time expressions and their expected fire times, run against `TimeParser.js`.
- `test.sh`: runs the CLI with a temporary `XDG_STATE_HOME` and `XDG_CONFIG_HOME` through create, list, rm, clear, reset, and sweep/import.
- Before publishing: `omarchy plugin validate` and `qmllint -I "$OMARCHY_PATH/shell"` on every QML file.

## Out of scope

Deferred to later versions:

- Calendar integration. The clock panel `omarchy.clock` has no extension slot, so this needs either an upstream contribution slot or a separate clock clone.
- Catching up on reminders missed while the machine was off, and showing a "Missed" section.
- Snooze action buttons. These need `notify-send -A`, which bypasses Omarchy's notification wrapper.
- Sound chosen per reminder. Categories, priorities, pausing a reminder.
- PT-BR time grammar.
- External calendars (Google, CalDAV, `.ics`).

## Open follow-ups

- Review how the repeat grammar is implemented once the plugin works.
- Review the parser path (shell call, with `qml6` fallback) for speed and reliability.
- Revisit missed-reminder behaviour.
