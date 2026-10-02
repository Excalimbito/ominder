#!/bin/bash

# Runs bin/ominder against temporary XDG dirs, with systemctl, notifications,
# the shell, and sound stubbed out. Every stub call is logged to $LOG.
#   bash test.sh

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OMINDER="$ROOT/bin/ominder"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config" XDG_RUNTIME_DIR="$TMP/run"
export LOG="$TMP/log" TIMERS="$TMP/omarchy-timers.json"
STATE="$XDG_STATE_HOME/ominder/reminders.json"
UNITS="$XDG_CONFIG_HOME/systemd/user"
mkdir -p "$TMP/bin" "$XDG_CONFIG_HOME/omarchy" "$XDG_RUNTIME_DIR/omarchy-reminders"
echo '[]' >"$TIMERS"

for stub in omarchy-notification-send omarchy-shell omarchy-reminder pw-play hyprctl; do
  printf '#!/bin/bash\necho "%s $*" >>"$LOG"\n[[ $0 != *omarchy-shell ]]\n' "$stub" >"$TMP/bin/$stub"
done
cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >>"$LOG"
if [[ $* == *"list-timers"*"omarchy-reminder-"* ]]; then cat "$TIMERS"; elif [[ $* == *list-timers* ]]; then echo '[]'; fi
EOF
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

failures=0
check() {
  if eval "$2"; then return; fi
  failures=$((failures + 1))
  echo "FAIL: $1"
}
count() { jq length "$STATE"; }

enable_plugin() {
  echo "{\"version\":1,\"plugins\":[{\"id\":\"io.github.excalimbito.ominder\",\"snoozeMinutes\":10,\"sound\":$1}]}" >"$XDG_CONFIG_HOME/omarchy/shell.json"
}
enable_plugin true

# create
once=$("$OMINDER" 30 pay the boleto)
check "create one-time" '[[ $(count) == 1 && $(jq -r ".[0].message" "$STATE") == "pay the boleto" ]]'
check "one-time timer is an absolute OnCalendar" 'grep -qE "^OnCalendar=[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}$" "$UNITS/ominder-$once.timer"'
check "service runs ominder fire" 'grep -qF "$OMINDER" "$UNITS/ominder-$once.service" && grep -qF "fire" "$UNITS/ominder-$once.service"'
check "timer enabled" 'grep -q "enable --now --quiet ominder-$once.timer" "$LOG"'
check "confirmation notification" 'grep -q "omarchy-notification-send .* pay the boleto .*in 30m" "$LOG"'

daily=$("$OMINDER" "every day 8:00" stretch)
check "daily OnCalendar" 'grep -qx "OnCalendar=\*-\*-\* 08:00:00" "$UNITS/ominder-$daily.timer"'
interval=$("$OMINDER" "every 30m")
check "interval timer starts at an absolute time" 'grep -qx "OnUnitActiveSec=1800" "$UNITS/ominder-$interval.timer" && grep -qE "^OnCalendar=[0-9]{4}-" "$UNITS/ominder-$interval.timer"'
check "empty message defaults to Reminder" '[[ $(jq -r --arg id "$interval" ".[] | select(.id == \$id) | .message" "$STATE") == Reminder ]]'

check "invalid time is rejected" '! "$OMINDER" nonsense 2>/dev/null && [[ $(count) == 3 ]]'
check "parse prints a preview" '[[ $("$OMINDER" parse "every day 8:00") == *"· daily" ]]'
check "parse --json" '[[ $("$OMINDER" parse --json 90m | jq .at) -gt $(date +%s) ]]'

cp "$TMP/bin/omarchy-shell" "$TMP/omarchy-shell"
cat >"$TMP/bin/omarchy-shell" <<'EOF'
#!/bin/bash
echo "omarchy-shell $*" >>"$LOG"
echo '{"at":1,"repeat":"","onCalendar":"","everySeconds":0,"preview":"from shell"}'
EOF
check "parse asks the running shell first" '[[ $("$OMINDER" parse 30) == "from shell" ]] && grep -q "omarchy-shell shell call io.github.excalimbito.ominder parse 30" "$LOG"'
mv "$TMP/omarchy-shell" "$TMP/bin/omarchy-shell"

# list
check "list shows every reminder" '[[ $("$OMINDER" list | wc -l) == 3 ]]'
check "list --json" '[[ $("$OMINDER" list --json | jq length) == 3 ]]'

# edit
"$OMINDER" edit "$daily" "every 1st 10:00" >/dev/null
check "edit keeps the id and message" '[[ $(jq -r --arg id "$daily" ".[] | select(.id == \$id) | .message + \"|\" + .repeat" "$STATE") == "stretch|monthly" ]]'
check "edit rewrites the timer" 'grep -qx "OnCalendar=\*-\*-01 10:00:00" "$UNITS/ominder-$daily.timer"'

# rm
"$OMINDER" rm "$once"
check "rm removes entry and units" '[[ $(count) == 2 && ! -e $UNITS/ominder-$once.timer && ! -e $UNITS/ominder-$once.service ]]'
check "rm unknown id fails" '! "$OMINDER" rm nope 2>/dev/null'

# fire
once=$("$OMINDER" 5 tea)
: >"$LOG"
"$OMINDER" fire "$once"
check "fire notifies with snooze on click" 'grep -qF "omarchy-notification-send -g 󰢌 Reminder tea --exec $OMINDER snooze $once tea" "$LOG"'
check "fire plays sound" 'grep -q "^pw-play " "$LOG"'
check "fired one-time reminder is removed" '[[ $(count) == 2 && ! -e $UNITS/ominder-$once.timer ]]'
enable_plugin false
: >"$LOG"
"$OMINDER" fire "$interval"
check "sound setting off" '! grep -q "^pw-play " "$LOG"'
check "repeating reminder survives firing" '[[ $(count) == 2 && -e $UNITS/ominder-$interval.timer ]]'

# snooze, after the entry is gone
"$OMINDER" snooze "$once" tea
check "snooze creates a copy snoozeMinutes out" '[[ $(jq -r ".[] | select(.message == \"tea\") | .at - now | floor" "$STATE") -ge 595 ]]'

# clear
"$OMINDER" clear
check "clear keeps repeating reminders" '[[ $(count) == 2 && -z $(jq -r ".[] | select(.message == \"tea\")" "$STATE") ]]'

# reset
check "reset needs --yes without a terminal" '! "$OMINDER" reset </dev/null 2>/dev/null && [[ $(count) == 2 ]]'
"$OMINDER" reset --yes
check "reset --yes removes everything" '[[ $(count) == 0 && -z $(ls "$UNITS"/ominder-* 2>/dev/null) ]]'

# sweep: import an omarchy-reminder timer, drop past-due entries and orphans
next=$((($(date +%s) + 600) * 1000000))
echo "[{\"unit\":\"omarchy-reminder-10m-1.timer\",\"next\":$next},{\"unit\":\"omarchy-reminder-5m-2.timer\",\"next\":null}]" >"$TIMERS"
echo -n "call mom" >"$XDG_RUNTIME_DIR/omarchy-reminders/omarchy-reminder-10m-1.message"
past=$("$OMINDER" 1 old)
jq '.[0].at = 1000' "$STATE" >"$TMP/s" && mv "$TMP/s" "$STATE"
touch "$UNITS/ominder-orphan.timer" "$UNITS/ominder-orphan.service"
: >"$LOG"
"$OMINDER" sweep
check "sweep imports omarchy-reminder timers" '[[ $(count) == 1 && $(jq -r ".[0].message" "$STATE") == "call mom" && $(jq -r ".[0].at" "$STATE") == $((next / 1000000)) ]]'
check "sweep stops the imported timer" 'grep -q "systemctl --user stop omarchy-reminder-10m-1.timer" "$LOG" && [[ ! -e $XDG_RUNTIME_DIR/omarchy-reminders/omarchy-reminder-10m-1.message ]]'
check "sweep drops past-due entries" '[[ ! -e $UNITS/ominder-$past.timer ]]'
check "sweep drops orphaned units" '[[ ! -e $UNITS/ominder-orphan.timer && ! -e $UNITS/ominder-orphan.service ]]'
echo '[]' >"$TIMERS"

# disabled plugin passes legacy calls through
echo '{"version":1,"plugins":[]}' >"$XDG_CONFIG_HOME/omarchy/shell.json"
: >"$LOG"
"$OMINDER" clear
"$OMINDER" panel
check "disabled plugin passes clear and panel to omarchy-reminder" 'grep -qx "omarchy-reminder clear" "$LOG" && grep -qx "omarchy-reminder show" "$LOG" && [[ $(count) == 1 ]]'

# Hyprland stub
STUB="$XDG_STATE_HOME/omarchy/toggles/hypr/ominder.lua"
: >"$LOG"
"$OMINDER" hypr-stub
check "hypr-stub writes the stub and applies it live" '[[ $(grep -c "^hyprctl eval" "$LOG") == 1 ]] && grep -qF "o.bind(\"SUPER + SHIFT + CTRL + R\"" "$STUB" && ! grep -q reload "$LOG"'
"$OMINDER" hypr-stub
check "unchanged stub is not re-applied" '[[ $(grep -c "^hyprctl eval" "$LOG") == 1 ]]'
check "stub only binds while the plugin exists" 'grep -qF "local ominder = \"$XDG_CONFIG_HOME/omarchy/plugins/io.github.excalimbito.ominder/bin/ominder\"" "$STUB" && grep -q "^if file then" "$STUB"'

# uninstall
"$OMINDER" uninstall >/dev/null
check "uninstall removes units, state, and stub" '[[ ! -e $XDG_STATE_HOME/ominder && -z $(ls "$UNITS"/ominder-* 2>/dev/null) && ! -e $XDG_STATE_HOME/omarchy/toggles/hypr/ominder.lua ]]'

if ((failures)); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
