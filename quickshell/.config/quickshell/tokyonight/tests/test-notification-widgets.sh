#!/usr/bin/env bash
# test-notification-widgets.sh — the two empty states of the notification widgets.
#
#   bell   : with 0 unread the pill must be glyph + padding, so the badge
#            fragment has to leave the row (visible:false) rather than sit in
#            it as an empty string still collecting the Row's 10px spacing.
#   centre : with 0 entries the ListView must have zero height, not a reserved
#            band above "Nothing yet".
#
# The width probe needs quickshell and is skipped without it; the greps do not.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0

check() { # check <description> <file> <regex>
    if grep -qE "$3" "$2"; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        fail=1
    fi
}
check "bell badge hides itself, not just its text" NotificationBell.qml 'visible: unread > 0'
check "bell badge is not an empty-string placeholder"  NotificationBell.qml \
      'text: unread > 9 \? "9\+" : String\(unread\)'
check "toast exits funnel through the once-only leave guard" ToastRow.qml \
      'function leave\(\)'
check "the × dismiss is idempotent (leave, not done)" ToastRow.qml \
      'onClicked: root.leave\(\)'
check "expiry + daemon close cannot double-remove (leave, not done)" \
      ToastRow.qml 'onTriggered: root.leave\(\)'
check "a daemon-released toast leaves once (leave, not done)" \
      ToastRow.qml 'onNChanged:'
check "toast removal carries the row's own index, not a stale one" \
      Toast.qml 'onDone: root.remove\(index\)'
# the height expression wraps across lines, so the two halves are matched apart
if grep -A1 'entries.length === 0' NotificationCenter.qml | grep -qE '^[[:space:]]*\? 0'; then
    echo "ok   centre reserves no list height when empty"
else
    echo "FAIL centre reserves no list height when empty"
    fail=1
fi

if ! command -v quickshell >/dev/null; then
    echo "skip width probe (no quickshell)"
    exit $fail
fi

# Module.qml and Tokyo.qml sit next to the probe as symlinks so it resolves them
# from its own directory.
ln -sf ../Tokyo.qml ../Module.qml tests/
out=$(timeout 20 env QT_QPA_PLATFORM=offscreen \
      quickshell -p "$PWD/tests/bellprobe.qml" 2>&1)
empty=$(sed -n 's/.*bellprobe empty=\([0-9.]*\).*/\1/p' <<<"$out")
# The empty pill is glyph + 2 * 12 padding and stops there: 35px on this shell.
# 40 is the ceiling, so a fragment left in the row when it should not be is
# caught rather than eyeballed.
if [[ -n $empty ]] && awk "BEGIN{exit !($empty <= 40)}"; then
    echo "ok   bell is glyph + padding when empty (${empty}px)"
else
    echo "FAIL bell empty=${empty}px (empty must be <= 40px)"
    fail=1
fi

exit $fail