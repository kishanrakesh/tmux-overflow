#!/usr/bin/env bash
# TPM entry point; also usable from a tmux run-shell command.
set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
key=$(tmux show-option -gqv @overflow-key)
key=${key:-O}

# Quote the script path for the shell that tmux uses, including spaces and apostrophes.
script="$PLUGIN_DIR/overflow"
script=${script//\'/\'\\\'\'}
tmux bind-key "$key" run-shell -b "'$script' '#{pane_id}'"
tmux source-file "$PLUGIN_DIR/overflow.conf"
