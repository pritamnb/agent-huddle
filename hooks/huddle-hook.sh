#!/bin/sh
# Agent Huddle hook relay.
# Forwards the hook's stdin JSON to the widget and prints whatever the widget
# answers (nothing for plain events, a decision for permission requests).
# If the widget is not running this exits silently and Claude Code carries on.
DIR="$HOME/.agent-huddle"
[ -r "$DIR/headers" ] || exit 0
PORT=$(cat "$DIR/port" 2>/dev/null || echo 47821)
TTY=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
curl -s --connect-timeout 1 --max-time "${1:-5}" -X POST \
  -H "Content-Type: application/json" -H "Expect:" \
  -H @"$DIR/headers" \
  -H "X-Huddle-Bundle: ${__CFBundleIdentifier:-}" \
  -H "X-Huddle-Term: ${TERM_PROGRAM:-}" \
  -H "X-Huddle-TTY: $TTY" \
  -H "X-Huddle-Host-Session: ${CLAUDE_CODE_HOST_SESSION_ID:-}" \
  -H "X-Huddle-Project: ${CLAUDE_PROJECT_DIR:-}" \
  -H "X-Huddle-Wait: ${1:+1}" \
  --data-binary @- "http://127.0.0.1:$PORT/hook" 2>/dev/null
exit 0
