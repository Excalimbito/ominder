# Ominder — Specification

Ominder is an Omarchy shell plugin that replaces the built-in `omarchy.reminders` overlay. It adds flexible time input, repeating reminders, snooze, notification sound, and a panel for managing reminders. It is meant to be published on the Omarchy plugin marketplace.

## Principles

- **The CLI is the source of truth.** The overlay, panel, bar widget, and systemd units are thin layers over `bin/ominder`.
- **No new dependencies.** systemd handles timing, `omarchy-notification-send` displays notifications, `pw-play` plays sound, and Qt/QML (already pulled in by Quickshell) runs the time parser.
- **Keyboard-first.** Creating a reminder never requires the mouse.
- **Omarchy theming only.** Use `Style` / `Color` tokens and `qs.Ui` components. Custom visuals only where `qs.Ui` has no equivalent (the floating overlay's drum, underlined fields, and blur), and those still take every colour, font, and size from `Style` / `Color`.
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
| `soundFile` | `/usr/share/sounds/freedesktop/stereo/window-attention.oga`. The default lives in `bin/ominder` only; the panel shows an empty field with a "Default sound" placeholder |
| `snoozeMinutes` | `5` (choices: 5 / 10 / 15 / 30) |
| `style` | `floating` (choices: `floating` / `classic`). Create overlay style |
| `blur` | `0` (0 to 1). Floating style: strength of the blur behind the overlay. `0` turns it off |
| `dim` | `0` (0 to 1). Floating style: opacity of the scrim, in the theme's scrim colour. `0` means no dimming |
| `performanceMode` | `false`. Disables the drum animation |
| `showCount` | `true`. Shows the number of upcoming reminders next to the bell |
| `emptyBell` | `dimmed` (choices: `dimmed` / `hidden`). The bell with no upcoming reminders |

The CLI and the overlay both read settings from the plugin's bar entry first, then from its `plugins[]` entry. The overlay watches `shell.json` with a `FileView`, because the shell API it receives does not refresh on settings edits.

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

Two stacked fields, *when* and *message*, in one of two styles chosen by the `style` setting.

**Floating** (default): no card. The fields have only an underline and sit centered on the scrim, below a drum and a context line. Omarchy turns Hyprland's blur off, so the overlay takes a still of its screen with `ScreencopyView` as it opens and blurs it by `blur`; each open builds a new capture, and the window waits for its still (at most 250 ms) so the still never contains the overlay itself. The scrim's opacity is `dim`.

```
        13   29          ← neighbours, dimmed and half clipped
        14 : 30          ← fire time
        15   31
   Fri · in 2h10m · daily   ← day, countdown, repeat, or inline error
   ____tomorrow 9:00____
   ____pay boleto_______
```

- The drum shows the parsed fire time. While *when* is empty it shows the current time, dimmed. While *when* is unrecognized it shows the last valid time, dimmed, and the error appears on the context line. A date that has passed shows its own time, dimmed, with "That time has passed", and can be scrolled forward. Interval repeats are dimmed and cannot be scrolled.
- The mouse wheel over the hour column steps ±1 hour; over the minute column it steps ±1 minute. Up/Down in either field steps ±1 minute, Shift+Up/Down ±1 hour.
- *when* stays the source of truth. A step rewrites its text with `TimeParser.shift`:
  - A trailing `HH:MM` is replaced in place and its prefix is kept (`fri 14:30` → `fri 14:31`, `every weekday 8:00` → `every weekday 08:01`). Minutes carry into the hour. Hours wrap from 23 to 00 without touching the prefix. A date scrolled into the past shows "That time has passed" and can still be scrolled back.
  - A duration stays a duration, with a 1 minute minimum (`30` → `31m`, `1h30m` → `1h29m`).
  - Empty text becomes the clock time now ± the step. The parser rolls a past clock time into tomorrow.
  - `every <duration>` and unrecognized text are not changed.
- A changed value rolls the drum column in the step's direction over 120 ms, unless `performanceMode` is on.

**Classic**: the v0.1.0 card, with a one-line preview and no drum:

```
→ Thu 14:30 · in 2h10m · daily      ← live preview / inline error
[ when:    tomorrow 9:00         ]
[ message: pay boleto            ]
```

Both styles:

- Tab / Shift+Tab move between fields.
- Enter in *when* moves to *message*. Enter in *message* submits.
- An invalid *when* shows the error inline, not as a notification.
- Escape clears the current field, then closes. Clicking the scrim closes.
- Edit from the panel opens this overlay with both fields prefilled.

## Panel

Opened from the bar widget or `ominder panel`. It always opens on the list view.

**List view.** The header reads *Reminders*, with icon buttons on the right:

- **Clear** removes one-time reminders immediately. **Reset** removes everything after an inline confirmation that replaces the header row, with no modal dialog. Both are hidden while the list is empty.
- **New** opens the create overlay.
- **Settings** (cog) switches to the settings view.

Below the header, upcoming reminders show time, message, and a repeat icon, each with edit and delete. The list scrolls once it passes about six rows, and the cursor row is kept in view.

**Settings view.** The header reads *Settings*, with a reset button that returns every setting to its default and an X that returns to the list. The sound file field has a folder button that opens a file chooser. The chooser runs as its own `qml6` process (`bin/pick-sound.qml`), because a GTK file dialog inside the shell process can crash the shell; the chosen path comes back on its output. Controls, in two groups: sound on/off, sound file, default snooze length; then style, the blur and dim sliders, the bell with no reminders, show count, and performance mode. Blur, dim, and performance mode only affect the floating style. While the blur or dim slider moves, and for 1.2 s after, the create overlay opens under the panel in preview mode: a sample reminder at the sliders' values, on the layer below the panel, with no keyboard focus and no input. Settings are mouse-only.

**Keys:** `j`/`k` move the cursor, Enter edits, `x` deletes, `n` creates. `s`, `l`, or Right opens settings. `h`, Left, or Escape returns to the list. `n` works only on the list, and Escape on the list closes the panel. Tab switches between bar panels.

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

## Bar widget

A bell, `󰢌`, followed by the number of upcoming reminders unless `showCount` is off. With no reminders the bell is dimmed, or hidden when `emptyBell` is `hidden`.

## Bar widget refresh

The bar widget watches `reminders.json` with a `FileView` (`watchChanges: true`). No polling, no IPC.

## Tests

- `test.js`: tables of time expressions with their expected fire times, and of `shift` steps with their rewritten text, run against `TimeParser.js`.
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
- Vim-style keyboard navigation in the panel's settings view, with a visible focus indicator on the current control.
