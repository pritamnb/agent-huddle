#!/bin/sh
# Agent Huddle hook relay.
# Forwards the hook's stdin JSON to the widget and prints whatever the widget answers
# (a decision for permission requests, otherwise nothing or the agent's neutral reply).
# If the widget is not running or does not answer, the agent carries on as normal.
#
# Usage: huddle-hook.sh [--agent claude|codex|cursor] [seconds to wait for a decision]
AGENT=claude
if [ "$1" = "--agent" ]; then AGENT="$2"; shift 2; fi
INPUT=$(cat)

# Cursor treats missing or invalid output from some hooks as "block", so for Cursor the
# fallback is the reply that means "carry on as normal". Claude Code and Codex need none:
# empty output already means "no decision".
FALLBACK=""
if [ "$AGENT" = "cursor" ]; then
  EVENT=$(printf '%s' "$INPUT" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  case "$EVENT" in
    beforeShellExecution|beforeMCPExecution) FALLBACK='{"permission":"ask"}' ;;
    beforeSubmitPrompt) FALLBACK='{"continue":true}' ;;
    *) FALLBACK='{}' ;;
  esac
fi

DIR="$HOME/.agent-huddle"
if [ ! -r "$DIR/headers" ]; then printf '%s' "$FALLBACK"; exit 0; fi
PORT=$(cat "$DIR/port" 2>/dev/null || echo 47821)
TTY=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
OUT=$(printf '%s' "$INPUT" | curl -s --connect-timeout 1 --max-time "${1:-5}" -X POST \
  -H "Content-Type: application/json" -H "Expect:" \
  -H @"$DIR/headers" \
  -H "X-Huddle-Agent: $AGENT" \
  -H "X-Huddle-Wait: ${1:+1}" \
  -H "X-Huddle-Bundle: ${__CFBundleIdentifier:-}" \
  -H "X-Huddle-Term: ${TERM_PROGRAM:-}" \
  -H "X-Huddle-TTY: $TTY" \
  -H "X-Huddle-Host-Session: ${CLAUDE_CODE_HOST_SESSION_ID:-}" \
  -H "X-Huddle-Project: ${CLAUDE_PROJECT_DIR:-${CURSOR_PROJECT_DIR:-}}" \
  --data-binary @- "http://127.0.0.1:$PORT/hook" 2>/dev/null)
if [ -n "$OUT" ]; then printf '%s' "$OUT"; else printf '%s' "$FALLBACK"; fi
exit 0
