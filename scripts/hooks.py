#!/usr/bin/env python3
"""Install or remove the Agent Huddle hooks in a Claude Code settings file.

  hooks.py install   [settings.json]   (default: ~/.claude/settings.json)
  hooks.py uninstall [settings.json]

Install copies the relay script to ~/.agent-huddle and backs the settings file up first.
"""
import json, os, shutil, sys, time

HOME = os.path.expanduser("~")
RELAY = os.path.join(HOME, ".agent-huddle", "huddle-hook.sh")
CMD = '"$HOME/.agent-huddle/huddle-hook.sh"'
EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
          "Notification", "Stop", "SubagentStop", "SessionEnd"]


def ours(group):
    return any("huddle-hook.sh" in h.get("command", "") for h in group.get("hooks", []))


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HOME, ".claude", "settings.json")
    if action not in ("install", "uninstall"):
        sys.exit(__doc__)
    settings = json.load(open(path)) if os.path.exists(path) else {}
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.huddle-backup-{time.strftime('%Y%m%d-%H%M%S')}")
    hooks = settings.setdefault("hooks", {})
    for event in list(hooks):
        hooks[event] = [g for g in hooks[event] if not ours(g)]
        if not hooks[event]:
            del hooks[event]
    if action == "install":
        os.makedirs(os.path.dirname(RELAY), mode=0o700, exist_ok=True)
        shutil.copy2(os.path.join(os.path.dirname(__file__), "..", "hooks", "huddle-hook.sh"), RELAY)
        os.chmod(RELAY, 0o755)
        quick = {"type": "command", "command": CMD, "timeout": 10}
        wait = {"type": "command", "command": CMD + " 590", "timeout": 600}
        for event in EVENTS:
            hooks.setdefault(event, []).append({"hooks": [quick]})
        hooks.setdefault("PermissionRequest", []).append({"hooks": [wait]})
        hooks.setdefault("PreToolUse", []).append({"matcher": "AskUserQuestion", "hooks": [wait]})
    if not hooks:
        del settings["hooks"]
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"{action}ed Agent Huddle hooks in {path}")


main()
