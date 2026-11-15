First public release of Agent Huddle: a small always-on-top macOS widget that shows every running Claude Code, Codex and Cursor session, lets you approve prompts and answer questions, and jumps to the right window.

## Install

1. Download `AgentHuddle-v0.1.0.zip` below and unzip it.
2. Move `AgentHuddle.app` to `/Applications`.
3. The app is not notarized by Apple, so macOS blocks it on first launch. Either right-click the app and choose **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/AgentHuddle.app
   ```
4. From the unzipped folder, install the hooks for the agents you use:
   ```bash
   python3 scripts/hooks.py install                    # Claude Code
   python3 scripts/hooks.py install --agent codex      # Codex
   python3 scripts/hooks.py install --agent cursor     # Cursor
   ```

Works on Apple Silicon and Intel Macs running macOS 13 or later.
