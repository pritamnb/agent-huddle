#!/usr/bin/env python3
"""Install or remove the Agent Huddle hooks for Claude Code, Codex or Cursor.

  hooks.py install   [--agent claude|codex|cursor] [--approvals] [config file]
  hooks.py uninstall [--agent claude|codex|cursor] [config file]

Default config files:
  claude  ~/.claude/settings.json
  codex   ~/.codex/hooks.json   (Codex runs new hooks only after you trust them:
                                 /hooks in the CLI, or Settings > Hooks in the app)
  cursor  ~/.cursor/hooks.json

--approvals (Cursor only) also routes every shell command and MCP call through the widget.
Claude Code and Codex always send approvals, but only for actions they would ask you about.

Install copies the relay script to ~/.agent-huddle and backs the config file up first.
"""
import json, os, shutil, sys, time

HOME = os.path.expanduser("~")
DIR = os.path.join(HOME, ".agent-huddle")
RELAY = os.path.join(DIR, "huddle-hook.sh")
WAIT = 590  # seconds the relay holds a prompt open, under the 600 s hook timeout
DEFAULT_CONFIG = {
    "claude": os.path.join(HOME, ".claude", "settings.json"),
    "codex": os.path.join(HOME, ".codex", "hooks.json"),
    "cursor": os.path.join(HOME, ".cursor", "hooks.json"),
}


def wrapper(agent, wait):
    """A one-line script per agent and mode, so the hook command is a bare path with no
    arguments (Codex and Cursor don't document whether commands run through a shell)."""
    path = os.path.join(DIR, "hooks", f"{agent}-{'wait' if wait else 'event'}.sh")
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    with open(path, "w") as f:
        f.write('#!/bin/sh\nexec "$HOME/.agent-huddle/huddle-hook.sh" --agent '
                f'{agent}{" " + str(WAIT) if wait else ""}\n')
    os.chmod(path, 0o755)
    if " " in path:
        print(f"warning: {path} contains a space; the hook command may not run")
    return path


def is_ours(entry):
    commands = [h.get("command", "") for h in entry.get("hooks", [])] + [entry.get("command", "")]
    return any("agent-huddle" in c or "huddle-hook.sh" in c for c in commands)


def strip(hooks):
    for event in list(hooks):
        hooks[event] = [e for e in hooks[event] if not is_ours(e)]
        if not hooks[event]:
            del hooks[event]


def claude_hooks(hooks):
    cmd = '"$HOME/.agent-huddle/huddle-hook.sh"'
    quick = {"type": "command", "command": cmd, "timeout": 10}
    wait = {"type": "command", "command": f"{cmd} {WAIT}", "timeout": 600}
    for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                  "Notification", "Stop", "SubagentStop", "SessionEnd"]:
        hooks.setdefault(event, []).append({"hooks": [quick]})
    hooks.setdefault("PermissionRequest", []).append({"hooks": [wait]})
    hooks.setdefault("PreToolUse", []).append({"matcher": "AskUserQuestion", "hooks": [wait]})


def codex_hooks(hooks):
    quick = wrapper("codex", False)
    for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "Interrupt"]:
        hooks.setdefault(event, []).append({"hooks": [{"type": "command", "command": quick, "timeout": 10}]})
    # Codex caps SessionEnd hooks at 3 seconds.
    hooks.setdefault("SessionEnd", []).append({"hooks": [{"type": "command", "command": quick, "timeout": 3}]})
    hooks.setdefault("PermissionRequest", []).append({"hooks": [
        {"type": "command", "command": wrapper("codex", True), "timeout": 600,
         "statusMessage": "Waiting for Agent Huddle"}]})


def cursor_hooks(hooks, approvals):
    quick = wrapper("cursor", False)
    for event in ["sessionStart", "beforeSubmitPrompt", "postToolUse", "postToolUseFailure", "afterFileEdit",
                  "afterAgentResponse", "stop", "sessionEnd"]:
        hooks.setdefault(event, []).append({"command": quick, "timeout": 10})
    if approvals:
        wait = wrapper("cursor", True)
        for event in ["beforeShellExecution", "beforeMCPExecution"]:
            hooks.setdefault(event, []).append({"command": wait, "timeout": 600})


def main():
    args = sys.argv[1:]
    action = args.pop(0) if args else ""
    agent, approvals = "claude", False
    if "--agent" in args:
        i = args.index("--agent")
        agent = args[i + 1] if i + 1 < len(args) else ""
        del args[i:i + 2]
    if "--approvals" in args:
        approvals = True
        args.remove("--approvals")
    if action not in ("install", "uninstall") or agent not in DEFAULT_CONFIG:
        sys.exit(__doc__)
    if approvals and agent != "cursor":
        print("note: --approvals only applies to Cursor; ignoring it")
    path = os.path.abspath(os.path.expanduser(args[0] if args else DEFAULT_CONFIG[agent]))

    config = json.load(open(path)) if os.path.exists(path) else {}
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.huddle-backup-{time.strftime('%Y%m%d-%H%M%S')}")
    hooks = config.setdefault("hooks", {})
    strip(hooks)

    if action == "install":
        os.makedirs(DIR, mode=0o700, exist_ok=True)
        shutil.copy2(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hooks", "huddle-hook.sh"), RELAY)
        os.chmod(RELAY, 0o755)
        if agent == "claude":
            claude_hooks(hooks)
        elif agent == "codex":
            codex_hooks(hooks)
        else:
            config.setdefault("version", 1)
            cursor_hooks(hooks, approvals)
    if not hooks:
        del config["hooks"]

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
    print(f"{action}ed Agent Huddle hooks for {agent} in {path}")
    if action == "install" and agent == "codex":
        print("Codex runs new hooks only after you trust them: /hooks in the CLI, or Settings > Hooks in the app.")


main()
