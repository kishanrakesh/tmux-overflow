#!/usr/bin/env bash
# End-to-end tests on a unique private tmux server; never use the default server.
set -euo pipefail
unset TMUX TMUX_PANE
SOCKET="overflow-test-$$-$RANDOM"
T() { tmux -L "$SOCKET" "$@"; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OV="$ROOT/overflow"
printf -v TOGGLE '%q' "$OV"
pause() { sleep "$1"; }
fail=0
checks=0
started=0
cleanup() { if (( started )); then T kill-server 2>/dev/null || true; fi; }
trap cleanup EXIT
check() {
  checks=$(( checks + 1 ))
  if [[ $2 == "$3" ]]; then
    echo "PASS $1 ($2)"
  else
    echo "FAIL $1: got '$2', want '$3'"
    fail=$(( fail + 1 ))
  fi
}
check_contains() {
  local found=no
  [[ $2 == *"$3"* ]] && found=yes
  check "$1" "$found" yes
}
# list-keys emits a complete bind-key command; run its body in a chosen pane's context.
bound_command() {
  T list-keys -T "$1" "$2" |
    sed -E 's/^bind-key[[:space:]]+-T[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+//'
}
num() { grep -o 'line [0-9]*' | head -1 | grep -o '[0-9]*'; }   # first "line N" number in the input
lastnum() { grep -o 'line [0-9]*' | tail -1 | grep -o '[0-9]*'; }

if ! T -f /dev/null new-session -d -s t -x 200 -y 40 'bash --norc --noprofile'; then
  echo "FAIL private tmux server could not start (0 checks run)" >&2
  exit 1
fi
started=1
T set -g history-limit 20000
LIVE=$(T display -p -t t '#{pane_id}')
printf -v LOAD_PLUGIN '%q' "$ROOT/overflow.tmux"
T run-shell "$LOAD_PLUGIN"
binding=$(T list-keys -T prefix O)
check_contains "plugin binds prefix + O to the bundled script" "$binding" "$OV"
check_contains "toggle binding targets the invoking pane" "$binding" '#{pane_id}'
WHEEL_UP=$(bound_command root WheelUpPane)
WHEEL_DOWN=$(bound_command root WheelDownPane)
check_contains "plugin installs WheelUpPane redirection" "$WHEEL_UP" 'scroll-up'
check_contains "plugin installs WheelDownPane redirection" "$WHEEL_DOWN" 'scroll-down'
T set -g @overflow-key U
T run-shell "$LOAD_PLUGIN"
check_contains "plugin honors @overflow-key" "$(T list-keys -T prefix U)" "$OV"
T set -gu @overflow-key
T run-shell "$LOAD_PLUGIN"

T send-keys -t "$LIVE" 'clear; seq -f "line %g" 1 300' Enter; pause 1
press() { T send-keys -t "$LIVE" "$TOGGLE" Enter; pause "${1:-1.5}"; }
panes() { T display -p -t t '#{window_panes}'; }
even() { T list-panes -t t -F '#{pane_width}' | sort -n | awk 'NR==1{lo=$1} {hi=$1} END{print (hi-lo<=1)}'; }
col() { T list-panes -t t -F '#{pane_id} #{@overflow_n}' | awk -v n="$1" '$2 == n {print $1}'; }

press; check "first press adds one column" "$(panes)" "2"
press; check "second press adds another" "$(panes):$(even)" "3:1"

MID=$(col 1); LEFT=$(col 2)
top=$(T capture-pane -p -t "$LIVE" | num)
check "middle ends just above the live pane" "$(T capture-pane -p -t "$MID" | lastnum)" "$(( top - 1 ))"
mtop=$(T capture-pane -p -t "$MID" | num)
check "left ends just above the middle" "$(T capture-pane -p -t "$LEFT" | lastnum)" "$(( mtop - 1 ))"
check "middle is a full screen" "$(( $(T capture-pane -p -t "$MID" | lastnum) - mtop + 1 ))" "40"

T copy-mode -t "$LIVE"; T send-keys -t "$LIVE" -X -N 10 scroll-up; pause 1.5
check "columns follow a scroll" "$(T capture-pane -p -t "$MID" | lastnum)" "$(( top - 11 ))"
T send-keys -t "$LIVE" -X cancel; pause 1

T run -t "$MID" -C "$WHEEL_UP"; pause 1
check "wheel-up on a column scrolls the live pane" "$(T display -p -t "$LIVE" '#{scroll_position}')" "3"
check "wheel-up leaves the column read-only" "$(T display -p -t "$MID" '#{pane_in_mode}')" "0"
check "columns follow wheel scrolling" "$(T capture-pane -p -t "$MID" | lastnum)" "$(( top - 4 ))"
T run -t "$MID" -C "$WHEEL_DOWN"; pause 1
check "wheel-down on a column scrolls the live pane back" "$(T display -p -t "$LIVE" '#{?pane_in_mode,#{scroll_position},0}')" "0"
T send-keys -t "$LIVE" -X cancel 2>/dev/null || true; pause 0.5

T run-shell -t "$MID" "$TOGGLE '#{pane_id}'"; pause 1
check "at 200 wide a third press closes them, even pressed inside a column" "$(panes)" "1"

T resize-window -t t -x 260; pause 0.5
press; press; press
check "at 260 wide three presses give four panes" "$(panes):$(even)" "4:1"
top=$(T capture-pane -p -t "$LIVE" | num)
check "the farthest column continues the flow" "$(T capture-pane -p -t "$(col 3)" | lastnum)" "$(( top - 81 ))"
press; check "a fourth press closes them" "$(panes)" "1"

T resize-window -t t -x 130; pause 0.5
press; check "130 wide: one column" "$(panes)" "2"
press; check "130 wide: next press closes" "$(panes)" "1"
T resize-window -t t -x 100; pause 0.5
press 1; check "too narrow: refuses" "$(panes)" "1"

T resize-window -t t -x 260; pause 0.5
press; press; press
T resize-window -t t -x 150; pause 1.5
check "narrowing the window drops columns that no longer fit" "$(panes):$(even)" "2:1"
T resize-window -t t -x 220; pause 1.5
check "widening keeps the columns even" "$(panes):$(even)" "2:1"
T kill-pane -t "$LIVE"; pause 1.5
sessions=$(T list-sessions 2>/dev/null || true)
check "columns close when the live pane goes" "$sessions" ""
printf '\n%d checks: %d passed, %d failed\n' "$checks" "$(( checks - fail ))" "$fail"
(( fail == 0 ))
