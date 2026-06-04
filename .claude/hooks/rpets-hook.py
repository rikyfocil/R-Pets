#!/usr/bin/env python3
"""
RPets hook handler — bridges Claude Code hook events to the RPets pet app.
Called once per event: rpets-hook.py <EventName>

Transport: fire-and-forget JSON over loopback TCP (same protocol as RPetsTester).
If the RPets app is not running, every send silently no-ops within 1 second.

To make hooks fire across all projects (not just this one), copy or symlink this
script to ~/.claude/hooks/rpets-hook.py and add the hook config to
~/.claude/settings.json (use the same structure as .claude/settings.json here,
but replace ${CLAUDE_PROJECT_DIR}/.claude/hooks/ with ~/.claude/hooks/).
"""

import json
import os
import socket
import sys

PORT = int(os.environ.get("RPETS_PORT", "51789"))
EVENT = sys.argv[1] if len(sys.argv) > 1 else ""

# Shell substrings that indicate a test run inside a Bash command.
_TEST_KEYWORDS = (
    "pytest", "swift test", "npm test", "yarn test", "pnpm test",
    "jest", "vitest", "mocha", "cargo test", "go test",
    "xcodebuild test", "rspec", "mix test", "mvn test", "gradle test",
    "bundle exec rspec", "bundle exec cucumber",
)

# Characters/patterns that disqualify a string from appearing as a bubble message (SPEC §7).
_UNSAFE_PATTERNS = (
    "://", "/", "\\",
    "`", "=>", "!=", "==", "&&", "||",
    "import ", "const ", "let ", "var ", "function ", "class ",
    "api_key", "secret", "token", "password", "private_key", "begin ",
)


def send(session: str, **fields) -> None:
    """Fire-and-forget a PetCommand to the RPets control server."""
    if not session:
        return
    payload = (json.dumps({"session": session, **fields}) + "\n").encode()
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=1) as sock:
            sock.sendall(payload)
    except Exception:
        pass


def sanitize(text: str, max_len: int = 140) -> str:
    """
    Returns the first line of text if it is safe to show in a bubble, else "".
    Enforces SPEC §7: no code, paths, URLs, or secrets.
    """
    if not text:
        return ""
    line = text.strip().split("\n")[0][:max_len]
    low = line.lower()
    if any(pat in low for pat in _UNSAFE_PATTERNS):
        return ""
    return line.strip()


def main() -> None:
    try:
        hook = json.load(sys.stdin)
    except Exception:
        return

    session    = hook.get("session_id", "")
    tool_name  = hook.get("tool_name", "")
    tool_input = hook.get("tool_input", {})

    if EVENT == "SessionStart":
        source = hook.get("source", "startup")
        # Treat resume/compact as already-active sessions; startup/clear as fresh.
        state = "working" if source in ("resume", "compact") else "idle"
        send(session, action="create", state=state)

    elif EVENT == "UserPromptSubmit":
        # User sent a message — Claude is now thinking about it.
        send(session, state="thinking")

    elif EVENT == "PreToolUse":
        if tool_name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
            send(session, state="editing")
        elif tool_name == "Bash":
            cmd = tool_input.get("command", "")
            if any(kw in cmd for kw in _TEST_KEYWORDS):
                send(session, state="testing")
            else:
                send(session, state="running")
        else:
            # Read, Grep, Glob, LS, WebFetch, WebSearch, Agent, MCP tools, …
            send(session, state="thinking")

    elif EVENT == "PostToolBatch":
        # The full parallel batch settled — return to general working state.
        send(session, state="working")

    elif EVENT == "Stop":
        # Claude finished its turn — session is idle, awaiting next user prompt.
        send(session, state="idle")

    elif EVENT == "StopFailure":
        send(session, state="failure")

    elif EVENT == "Notification":
        # Bubble the notification message if it passes sanitization.
        raw = hook.get("message") or hook.get("notification_message") or ""
        msg = sanitize(str(raw))
        if msg:
            send(session, state="waiting", message=msg)
        else:
            send(session, state="waiting")

    elif EVENT in ("PermissionRequest", "Elicitation"):
        send(session, state="waiting")

    elif EVENT == "SessionEnd":
        send(session, action="close")


main()
