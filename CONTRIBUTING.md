# Adding an agent

Agent Huddle supports Claude Code, Codex and Cursor through one adapter each. Adding
another agent (Gemini CLI, Windsurf, Copilot, …) needs three pieces.

## 1. Check what the agent's hooks can do

Before writing code, find out from the agent's docs:

- **Which events it has**, and the fields on stdin (a session or conversation id, the
  working directory, the tool name and input).
- **Whether a hook can wait for a decision**, and the exact stdout for allow, deny and
  "no decision". Note whether the hook fires only when the agent would ask the user, or
  before every action.
- **What happens on empty output, invalid output, a crash or a timeout.** If any of these
  can block or approve an action, the relay must print a safe reply instead (see
  `FALLBACK` in `hooks/huddle-hook.sh`).

## 2. Write the adapter

Add `Sources/AgentHuddle/<Name>Adapter.swift` implementing `AgentAdapter` (see
`Adapters.swift`), and add a case to the `Agent` enum.

- **`normalize(_:)`** turns the agent's payload into the widget's event shape. It must
  set `session_id` and `hook_event_name` and return `nil` for events the widget doesn't
  show. The event names the store understands are listed above `HuddleEvent` in
  `Adapters.swift`:
  - `PermissionRequest` for a prompt that waits for a decision
  - `ToolRan` for a tool that only reports once it finished
  - `AgentMessage` for a reply from the agent
- **`reply(_:raw:event:)`** returns the exact stdout for each `Decision`.
  - **`.handBack` must never approve anything.** It means "let the agent's own approval
    flow decide", for example empty output or `{"permission":"ask"}`.
  - **Every reply must be valid** for the event it answers. Some agents treat bad output as
    a block.

## 3. Install the hooks

In `scripts/hooks.py`, add the agent's default config path to `DEFAULT_CONFIG` and a
function that adds its hooks. Use `wrapper(agent, wait)` for the command so it's a bare
path with no arguments. Set the hook timeout above `WAIT` (590 s) for events that wait
for a decision.

## Testing

You don't need the agent installed to test the plumbing. With the widget running:

```bash
printf '%s' '{"session_id":"t1","cwd":"/tmp/demo","hook_event_name":"..."}' \
  | sh hooks/huddle-hook.sh --agent <name> 30
```

The `/debug/state`, `/debug/shot?path=…` and `/debug/click?x=…&y=…` endpoints (send the
token from `~/.agent-huddle/headers`) show what the widget recorded. They let you click its
buttons from a script and check the exact reply the hook printed.

Then try it with the real agent, and say in the pull request which versions you tested.
