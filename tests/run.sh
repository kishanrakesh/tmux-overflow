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
T send-keys -t "$LIVE" "$TOGGLE" Enter; pause 2

MID=$(T list-panes -t t -F '#{pane_id} #{pane_index}' | awk '$2 == 1 {print $1}')
LEFT=$(T list-panes -t t -F '#{pane_id} #{pane_index}' | awk '$2 == 0 {print $1}')
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
if [[ $(T display -p -t "$LIVE" '#{pane_in_mode}') == 1 ]]; then
  T send-keys -t "$LIVE" -X cancel
fi
pause 0.5

T send-keys -t "$LIVE" "$TOGGLE" Enter; pause 1
check "second press drops the farthest column" "$(T display -p -t t '#{window_panes}'):$(T list-panes -t t -F '#{@overflow_n}' | sort | tr -d '\n')" "2:1"
check "two left share the width evenly" "$(T list-panes -t t -F '#{pane_width}' | sort -n | awk 'NR==1{lo=$1} {hi=$1} END{print (hi-lo<=1)}')" "1"
T run-shell -t "$(T list-panes -t t -F '#{pane_id} #{@overflow_n}' | awk '$2 == 1 {print $1}')" "$TOGGLE '#{pane_id}'"; pause 1
check "third press closes the columns, even pressed inside a column" "$(T display -p -t t '#{window_panes}')" "1"

T resize-window -t t -x 130; pause 0.5
T send-keys -t "$LIVE" "$TOGGLE" Enter; pause 1.5
check "130 columns gives two columns" "$(T display -p -t t '#{window_width}:#{window_panes}')" "130:2"
T send-keys -t "$LIVE" "$TOGGLE" Enter; pause 1
T resize-window -t t -x 100; pause 0.5
T send-keys -t "$LIVE" "$TOGGLE" Enter; pause 1
check "too narrow: refuses" "$(T display -p -t t '#{window_panes}')" "1"

T resize-window -t t -x 200; pause 0.5
T send-keys -t "$LIVE" "$TOGGLE" Enter; pause 1.5
T resize-window -t t -x 150; pause 1.5
check "narrowing the window drops a column" "$(T display -p -t t '#{window_panes}')" "2"
check "columns refit evenly after a resize" "$(T list-panes -t t -F '#{pane_width}' | sort -n | awk 'NR==1{lo=$1} {hi=$1} END{print (hi-lo<=1)}')" "1"
T resize-window -t t -x 220; pause 1.5
check "widening keeps the columns even" "$(T display -p -t t '#{window_panes}'):$(T list-panes -t t -F '#{pane_width}' | sort -n | awk 'NR==1{lo=$1} {hi=$1} END{print (hi-lo<=1)}')" "2:1"
T kill-pane -t "$LIVE"; pause 1.5
sessions=$(T list-sessions 2>/dev/null || true)
check "columns close when the live pane goes" "$sessions" ""
printf '\n%d checks: %d passed, %d failed\n' "$checks" "$(( checks - fail ))" "$fail"
(( fail == 0 ))
