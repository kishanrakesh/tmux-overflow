# overflow

`overflow` shows the scrollback above a tmux pane as read-only columns to its left, so long output reads left → middle → right like newspaper columns. Press prefix + O to open or close them. The columns follow the live pane when you scroll in copy mode and close when that pane closes. It works with any long terminal output, including build logs, test results, and conversations printed by terminal tools.

Demo GIF: to be recorded and added here.

## Requirements

- tmux 3.4 (the tested version).
- Bash 4 or newer.
- `readlink -f`, `awk`, and `sleep` with fractional-second support. These are available on typical Linux installations; on other systems, provide compatible tools on `PATH`.

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add this before TPM's initialization line in `~/.tmux.conf`, then press prefix + I:

```tmux
set -g @plugin 'kishanrakesh/tmux-overflow'
```

For a manual install, clone the repository:

```sh
git clone https://github.com/kishanrakesh/tmux-overflow.git ~/.tmux/plugins/tmux-overflow
```

Then add this one line to `~/.tmux.conf`:

```tmux
run-shell '~/.tmux/plugins/tmux-overflow/overflow.tmux'
```

Reload the config with `tmux source-file ~/.tmux.conf`.

The default key is prefix + O. To change it, set this before loading the plugin:

```tmux
set -g @overflow-key 'o'
```

The plugin installs both wheel bindings, replacing any existing `WheelUpPane` and `WheelDownPane` bindings. It forwards the wheel over a column to the live pane and uses tmux's normal mouse handling elsewhere. Enable mouse events with `set -g mouse on` to use wheel scrolling.

For more scrollback, add this to `~/.tmux.conf` before creating your windows:

```tmux
set -g history-limit 20000
```

## Usage

1. Start in a tmux window containing one pane, with some output already in its scrollback.
2. Press prefix + O (uppercase O). One or two columns open to the left; keep working in the original pane on the right.
3. Scroll the live pane in copy mode, or use the wheel over a column. Each wheel event over a column scrolls the live pane by three lines.
4. Press prefix + O again from the live pane to close the columns. They also close when the live pane closes.

The prefix is Ctrl-b unless you changed it. You can also run the script directly from inside tmux:

```sh
~/.tmux/plugins/tmux-overflow/overflow
~/.tmux/plugins/tmux-overflow/overflow '%3'
```

The optional argument selects a pane by its tmux pane ID. Without it, the script uses the current pane. Running the script directly does not install key or wheel bindings; load `overflow.tmux` for those.

## How it works

Each column is a tmux pane running the same Bash script in an internal drawing mode. The live pane's height and copy-mode scroll position determine negative `capture-pane` offsets into its history. The nearest column shows the screenful immediately above the live pane, and the next column shows the screenful above that. Captured lines are bottom-aligned so the last line of one column leads into the first line of the next. Long lines are clipped to the column width.

Each column checks the live pane for changes and redraws only when the captured text changes. A check takes about 6 ms on the original setup. Refresh is adaptive: about 20 checks per second while text moves, dropping to about two per second after roughly a second without changes. These timings are approximate and depend on the machine and output.

Columns carry an `@overflow_of` pane option pointing at the live pane. The wheel bindings use it to redirect scrolling. Each drawing loop also checks that tmux still returns the expected live pane ID and exits when it disappears.

## Limits

- Opening columns needs a window with one pane. Existing multi-pane windows are left alone.
- Each column needs at least 60 characters of width. Two columns need a window at least 121 characters wide; three need at least 182. At most three columns, including the live pane, are shown.
- Only text in tmux's scrollback can appear. Fullscreen applications that keep their own history may leave the columns empty.
- Claude Code users need the classic display, `"tui": "default"`. Its fullscreen display does not put the conversation into tmux's scrollback.
- The display copies terminal lines, so long lines may be clipped after the window is split. Resizing or changing layouts while columns are open may also leave narrow columns; close them and reopen at the desired window size.

## Development

Run from the repository root:

```sh
./tests/run.sh
shellcheck overflow overflow.tmux tests/run.sh
```

The 17 integration checks create a uniquely named private tmux server with `-L`, load no user config, and clean up only that server. They cover column alignment, copy-mode following, toggling, width limits, pane cleanup, plugin bindings, a custom key, and wheel redirection. They require Bash, tmux, and the usual shell tools (`seq`, `grep`, `head`, `tail`, and `sed`); ShellCheck is a separate check.

## License

[MIT](LICENSE).
