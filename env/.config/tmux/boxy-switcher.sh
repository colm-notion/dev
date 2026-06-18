#!/usr/bin/env bash
# Boxy dev boxes in the *native* tmux session switcher (choose-tree).
#
# choose-tree only lists real sessions, so to surface boxes we pre-create a thin
# local wrapper session "boxy-<name>" for each running box. The wrapper does NOT
# ssh in immediately (that would open a connection to every box on every press);
# it polls cheaply until you actually switch into it, then execs
# `notion boxy attach <name>` (ssh + attach to the box's shared tmux).
#
# Usage (driven from .tmux.conf, prefix + S):
#   boxy-switcher.sh sync          -> reconcile wrapper sessions, then caller runs choose-tree
#   boxy-switcher.sh __attach NAME -> wrapper pane command: wait-for-attach, then connect
#
# Defensive: also synced onto boxes, where `notion` may be absent -> sync is a
# no-op and you just get local sessions in choose-tree.
set -uo pipefail

# Prefer the real node (brew, /usr/local/bin) over mise shims: the shims
# re-resolve node per-call from notion-next's .node-version and trip a mise
# newline bug that breaks the `notion` CLI from a non-interactive shell.
[ -x /usr/local/bin/node ] && export PATH="/usr/local/bin:$PATH"

self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# List names of running boxes (empty if notion is missing/broken; never errors).
running_boxes() {
	command -v notion >/dev/null 2>&1 || return 0
	notion boxy ls </dev/null 2>/dev/null \
		| awk 'sep && tolower($0) ~ /running/ { print $1 } /^----/ { sep = 1 }'
}

case "${1:-sync}" in
__attach)
	# Wrapper pane command. Wait until a client actually switches into this
	# session, then hand off to the real attach. Detaching from the box exits
	# the attach -> this pane exits -> the wrapper session self-destructs.
	box="${2:?box name required}"
	# Target our own pane ($TMUX_PANE) to read whether the session is attached --
	# pane-id targets are always unambiguous (session-name targets are flaky here).
	while [ "$(tmux display-message -p -t "$TMUX_PANE" '#{session_attached}' 2>/dev/null || echo 0)" = "0" ]; do
		sleep 0.3
	done
	echo "Connecting to $box ..."
	exec notion boxy attach "$box"
	;;

sync)
	# Reconcile: a wrapper session per running box; prune stale, unattached ones.
	mapfile -t boxes < <(running_boxes)

	for b in "${boxes[@]}"; do
		[ -z "$b" ] && continue
		sess="boxy-$b"
		tmux has-session -t "=$sess" 2>/dev/null && continue
		# Capture the new session id; use it to set options (name targets are flaky).
		sid="$(tmux new-session -d -P -F '#{session_id}' -s "$sess" "$self __attach $b")"
		# Persistent "you are nested" strip on the wrapper's (outer) bar. It reads
		# the client's key table live, so it always shows which layer keystrokes go
		# to and flips itself the instant F12 toggles -- no work needed in the bind.
		#   key-table == passthrough -> keys reach the INNER box tmux
		#   key-table == root        -> keys stay on the OUTER laptop tmux
		# NB: no commas inside the #{?...} branches -- tmux splits branches on commas,
		# so style codes there must be #[reverse]#[bold], never #[reverse,bold].
		ind='#[reverse,bold] ⧉ nested #[default] keys → #{?#{==:#{client_key_table},passthrough},#[reverse]#[bold] inner · box ,#[reverse]#[bold] outer · laptop }#[default]'
		tmux set-option -t "$sid" status on
		tmux set-option -t "$sid" status-left "$ind"
		tmux set-option -t "$sid" status-left-length 60
		tmux set-option -t "$sid" status-right ''
		tmux set-option -t "$sid" window-status-format ''
		tmux set-option -t "$sid" window-status-current-format ''
	done

	# Drop wrappers for boxes that are gone, but only if no client is attached
	# (never yank a session out from under you).
	tmux list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null \
		| awk '$1 ~ /^boxy-/ && $2 == 0 { print substr($1, 6) }' \
		| while read -r b; do
			printf '%s\n' "${boxes[@]}" | grep -qxF "$b" || tmux kill-session -t "boxy-$b" 2>/dev/null || true
		done
	;;
esac
