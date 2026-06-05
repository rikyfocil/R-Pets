#!/usr/bin/env python3
"""
Install or remove RPets Claude Code hooks and instructions globally.

    python3 .claude/hooks/install.py install   # deploy hook script, merge settings, inject instructions
    python3 .claude/hooks/install.py remove    # undo everything, leaving other tools untouched

Safe to run multiple times (install is idempotent; re-running updates files in place).
~/.claude/settings.json is backed up to settings.json.bak before every write.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

_CLAUDE_DIR = Path.home() / ".claude"

HOOK_SCRIPT_SRC    = Path(__file__).parent / "rpets-hook.py"
HOOK_SCRIPT_DST    = _CLAUDE_DIR / "hooks" / "rpets-hook.py"

INSTRUCTIONS_SRC   = Path(__file__).parent.parent / "rpets.md"   # .claude/rpets.md
INSTRUCTIONS_DST   = _CLAUDE_DIR / "rpets.md"
CLAUDE_MD_PATH     = _CLAUDE_DIR / "CLAUDE.md"
# Import line added to CLAUDE.md — uses ~ so it matches the existing @~/.claude/… style.
IMPORT_LINE        = "@~/.claude/rpets.md"

SETTINGS_PATH      = _CLAUDE_DIR / "settings.json"

# Identifies our entries in settings.json so remove() is surgical.
HOOK_MARKER = str(HOOK_SCRIPT_DST)

# MCP server binary — resolved relative to install.py so it works from any clone location.
# .claude/hooks/install.py → ../../ = repo root → .build/…/RPetsMCP
_REPO_ROOT      = Path(__file__).parent.parent.parent
MCP_BINARY_SRC  = _REPO_ROOT / ".build/arm64-apple-macosx/release/RPetsMCP"
MCP_BINARY_DST  = _CLAUDE_DIR / "RPetsMCP"
MCP_SERVER_NAME = "rpets"

# Events → async flag.  SessionEnd is synchronous so the close command
# reaches the RPets app before the Claude Code process exits.
EVENTS: dict[str, bool] = {
    "SessionStart":     True,
    "UserPromptSubmit": True,
    "PreToolUse":       True,
    "PostToolBatch":    True,
    "Stop":             True,
    "StopFailure":      True,
    "Notification":     True,
    "PermissionRequest":True,
    "Elicitation":      True,
    "SessionEnd":       False,
}


# ---------------------------------------------------------------------------
# settings.json helpers
# ---------------------------------------------------------------------------

def load_settings() -> dict:
    if SETTINGS_PATH.exists():
        try:
            return json.loads(SETTINGS_PATH.read_text())
        except json.JSONDecodeError:
            print(f"  Warning: {SETTINGS_PATH} is not valid JSON — treating as empty.",
                  file=sys.stderr)
    return {}


def save_settings(data: dict) -> None:
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    if SETTINGS_PATH.exists():
        backup = SETTINGS_PATH.with_suffix(".json.bak")
        shutil.copy(SETTINGS_PATH, backup)
        print(f"  Backed up settings → {backup}")
    SETTINGS_PATH.write_text(json.dumps(data, indent=2) + "\n")


def make_hook_entry(event: str, is_async: bool) -> dict:
    return {
        "type": "command",
        "command": HOOK_MARKER,
        "args": [event],
        "async": is_async,
        "timeout": 5,
    }


def is_our_hook(hook: dict) -> bool:
    return HOOK_MARKER in hook.get("command", "")


# ---------------------------------------------------------------------------
# mcpServers helpers
# ---------------------------------------------------------------------------

def _run_claude_mcp(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["claude", "mcp", *args], capture_output=True, text=True)


def install_mcp() -> None:
    """Copy the RPetsMCP binary to ~/.claude and register it via the claude CLI (user scope)."""
    if not MCP_BINARY_SRC.exists():
        print(f"  Warning: MCP binary not found at {MCP_BINARY_SRC} — skipping MCP registration.")
        print(f"           Run 'swift build -c release --product RPetsMCP' first.")
        return
    shutil.copy(MCP_BINARY_SRC, MCP_BINARY_DST)
    MCP_BINARY_DST.chmod(0o755)
    print(f"  MCP binary → {MCP_BINARY_DST}")
    # Remove first so re-running install is idempotent (add fails if name already exists).
    _run_claude_mcp("remove", "--scope", "user", MCP_SERVER_NAME)
    result = _run_claude_mcp("add", "--scope", "user", MCP_SERVER_NAME, str(MCP_BINARY_DST))
    if result.returncode == 0:
        print(f"  Registered '{MCP_SERVER_NAME}' via 'claude mcp add --scope user'")
    else:
        print(f"  Warning: 'claude mcp add' failed: {(result.stderr or result.stdout).strip()}")


def remove_mcp() -> None:
    """Unregister RPetsMCP via the claude CLI and delete the copied binary."""
    result = _run_claude_mcp("remove", "--scope", "user", MCP_SERVER_NAME)
    if result.returncode == 0:
        print(f"  Unregistered '{MCP_SERVER_NAME}' via 'claude mcp remove --scope user'")
    else:
        print(f"  Warning: 'claude mcp remove' failed: {(result.stderr or result.stdout).strip()}")
    if MCP_BINARY_DST.exists():
        MCP_BINARY_DST.unlink()
        print(f"  Removed binary: {MCP_BINARY_DST}")


# ---------------------------------------------------------------------------
# CLAUDE.md helpers
# ---------------------------------------------------------------------------

def add_import() -> None:
    """Append @~/.claude/rpets.md to CLAUDE.md if not already present."""
    existing = CLAUDE_MD_PATH.read_text() if CLAUDE_MD_PATH.exists() else ""
    if IMPORT_LINE in existing:
        return
    with open(CLAUDE_MD_PATH, "a") as f:
        if existing and not existing.endswith("\n"):
            f.write("\n")
        f.write(IMPORT_LINE + "\n")
    print(f"  Added '{IMPORT_LINE}' to {CLAUDE_MD_PATH}")


def remove_import() -> None:
    """Remove our @import line from CLAUDE.md."""
    if not CLAUDE_MD_PATH.exists():
        return
    lines = CLAUDE_MD_PATH.read_text().splitlines(keepends=True)
    cleaned = [l for l in lines if l.rstrip() != IMPORT_LINE]
    if len(cleaned) < len(lines):
        CLAUDE_MD_PATH.write_text("".join(cleaned))
        print(f"  Removed '{IMPORT_LINE}' from {CLAUDE_MD_PATH}")


# ---------------------------------------------------------------------------
# install / remove
# ---------------------------------------------------------------------------

def install() -> None:
    # 1. Hook script.
    HOOK_SCRIPT_DST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(HOOK_SCRIPT_SRC, HOOK_SCRIPT_DST)
    HOOK_SCRIPT_DST.chmod(0o755)
    print(f"  Hook script → {HOOK_SCRIPT_DST}")

    # 2. Hook entries in settings.json.
    settings = load_settings()
    event_hooks: dict = settings.setdefault("hooks", {})
    added: list[str] = []

    for event, is_async in EVENTS.items():
        groups: list = event_hooks.setdefault(event, [])
        if any(is_our_hook(h) for g in groups for h in g.get("hooks", [])):
            continue  # already present
        groups.append({"hooks": [make_hook_entry(event, is_async)]})
        added.append(event)

    save_settings(settings)

    # 3. MCP server (after save_settings to avoid conflicting writes to settings.json).
    install_mcp()

    if added:
        print(f"  Added hooks for: {', '.join(added)}")
    else:
        print("  Hook entries already present — script updated in place.")

    # 4. Instructions.
    shutil.copy(INSTRUCTIONS_SRC, INSTRUCTIONS_DST)
    print(f"  Instructions → {INSTRUCTIONS_DST}")
    add_import()

    print("Done. RPets hooks, MCP server, and instructions are now active globally.")


def remove() -> None:
    # 1. Hook entries from settings.json.
    settings = load_settings()
    event_hooks: dict = settings.get("hooks", {})
    removed_events: set[str] = set()

    for event in list(event_hooks.keys()):
        before = sum(len(g.get("hooks", [])) for g in event_hooks[event])
        cleaned = []
        for group in event_hooks[event]:
            remaining = [h for h in group.get("hooks", []) if not is_our_hook(h)]
            if remaining:
                cleaned.append({**group, "hooks": remaining})
        event_hooks[event] = cleaned
        after = sum(len(g.get("hooks", [])) for g in cleaned)
        if after < before:
            removed_events.add(event)

    for event in [e for e, v in event_hooks.items() if not v]:
        del event_hooks[event]
    if not event_hooks:
        settings.pop("hooks", None)

    save_settings(settings)

    if removed_events:
        print(f"  Removed hooks for: {', '.join(sorted(removed_events))}")
    else:
        print("  No RPets hook entries found in settings.")

    # 2. MCP server (after save_settings to avoid conflicting writes to settings.json).
    remove_mcp()

    # 3. Hook script.
    if HOOK_SCRIPT_DST.exists():
        HOOK_SCRIPT_DST.unlink()
        print(f"  Removed hook script: {HOOK_SCRIPT_DST}")

    # 3. Instructions.
    remove_import()
    if INSTRUCTIONS_DST.exists():
        INSTRUCTIONS_DST.unlink()
        print(f"  Removed instructions: {INSTRUCTIONS_DST}")

    print("Done.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("install", "remove"):
        print(f"Usage: {Path(sys.argv[0]).name} install|remove", file=sys.stderr)
        sys.exit(1)

    action = sys.argv[1]
    print(f"{'Installing' if action == 'install' else 'Removing'} RPets...")
    install() if action == "install" else remove()
