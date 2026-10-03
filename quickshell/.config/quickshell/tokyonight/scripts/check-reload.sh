#!/usr/bin/env bash
# Did my .qml edit actually load? Prints ONLY the last reload attempt.
#
# Why this exists: `quickshell -c tokyonight log` replays the WHOLE journal
# since the instance started. Grepping it for "Configuration Loaded" matches
# stale lines from hours ago and fakes a successful reload. A failed reload
# leaves the OLD bar on screen, so the screen never tells you either.
#
# It also checks that the last load is NEWER than every .qml on disk. Without
# that second check the script answers "loaded" for a save that produced no
# reload at all, which is not hypothetical: a `git revert` that rewrote Bar.qml
# and deleted a widget printed a successful load from a quarter of an hour
# earlier, exit 0, and the stale bar kept rendering the deleted widget. A
# reload that never happened and a reload that happened last week look
# identical if you only ask "was the last one successful?".
#
# Usage: scripts/check-reload.sh     (run right after saving a .qml change)
# Exit:  0 = current config is loaded, 1 = broke / never reloaded / watcher dead.
set -o pipefail

CFG=$(cd "$(dirname "$0")/.." && pwd)
LOG=$(ls -t /run/user/1000/quickshell/by-id/*/log.log 2>/dev/null | head -1)
[ -n "$LOG" ] || { echo "check-reload: no live quickshell log found" >&2; exit 1; }

clean=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG")
last=$(echo "$clean" | grep -E "Reloading configuration|Configuration Loaded" | tail -2)
if [ -z "$last" ]; then
  echo "check-reload: no reload recorded yet — the watcher has not seen your save" >&2
  exit 1
fi
echo "$last"

if ! echo "$last" | grep -q "Configuration Loaded"; then
  echo "check-reload: reload started but did NOT finish — your edit broke the config" >&2
  exit 1
fi

# The bar is only running what is in the directory if the last successful load
# postdates every .qml. `touch` is a fine way to trip this: it changes the mtime
# without writing, so it never triggers a reload, which is the situation worth
# catching. Epochs are compared numerically on purpose — `find -newermt` does not
# accept the `@<epoch>` form and silently matches nothing, which looks exactly
# like "everything is current".
loaded=$(echo "$clean" | grep "Configuration Loaded" | tail -1 | awk '{print $1, $2}' \
  | xargs -I{} date -d "{}" +%s 2>/dev/null)
newest=$(find "$CFG" -name '*.qml' -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
newest_file=$(find "$CFG" -name '*.qml' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$loaded" ] && [ -n "$newest" ] && [ "$newest" -gt "$loaded" ]; then
  echo "check-reload: last load $(date -d "@$loaded" '+%T'), but ${newest_file#$CFG/} changed at $(date -d "@$newest" '+%T')." >&2
  echo "check-reload: the watcher never saw your save — the bar is running stale config." >&2
  echo "check-reload: restart it with 'quickshell -c tokyonight kill && quickshell -c tokyonight'" >&2
  exit 1
fi