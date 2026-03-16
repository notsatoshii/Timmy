#!/usr/bin/env python3
"""
LEVER Protocol — Telegram Command Center + Claude Code Proxy
============================================================
Two modes:
  1. Slash commands (/status, /go, etc.) — existing functionality
  2. Natural language → Claude Code passthrough — any non-command message
     gets piped to `claude -p "..."` and the response sent back to TG.

Session Management:
  - Uses `claude -c -p` to continue sessions (memory between messages)
  - Every 25 messages, triggers automatic handoff:
    1. Asks Claude to summarize session state to session-handoff.md
    2. Resets session counter
    3. Next message starts fresh but loads handoff context

Security: Only AUTHORIZED_USER_ID can interact.
"""

import os
import sys
import json
import asyncio
import subprocess
import logging
import time
import signal
from datetime import datetime, timezone
from pathlib import Path

# ─── Configuration ────────────────────────────────────────────────────────────

BOT_TOKEN = os.environ.get("LEVER_BOT_TOKEN", "8541708860:AAGmNKlIeo5Acn6Wssk6HzQR1QfMNX2GXwk")
AUTHORIZED_USER_ID = 422985839
PROJECT_DIR = "/home/lever/lever-protocol"
CLAUDE_CODE_BIN = "claude"  # assumes claude is in PATH
MAX_TG_MESSAGE_LENGTH = 4000  # leave buffer under 4096
CLAUDE_TIMEOUT = 1800  # 10 minutes max per claude invocation
LOG_FILE = "/home/lever/lever-protocol/control-plane/bot.log"
HANDOFF_FILE = "/home/lever/lever-protocol/session-handoff.md"
SESSION_LIMIT = 25  # messages before auto-handoff
SESSION_STATE_FILE = "/home/lever/lever-protocol/control-plane/session-state.json"

# ─── Logging ──────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("lever-bot")

# ─── Session State ────────────────────────────────────────────────────────────

def load_session_state() -> dict:
    """Load session state from disk."""
    try:
        if Path(SESSION_STATE_FILE).exists():
            with open(SESSION_STATE_FILE, "r") as f:
                return json.load(f)
    except Exception as e:
        log.error(f"Error loading session state: {e}")
    return {"message_count": 0, "session_active": False}


def save_session_state(state: dict):
    """Save session state to disk."""
    try:
        Path(SESSION_STATE_FILE).parent.mkdir(parents=True, exist_ok=True)
        with open(SESSION_STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception as e:
        log.error(f"Error saving session state: {e}")


# ─── Telegram API (raw HTTP, no external deps beyond requests) ────────────────

import requests

API_BASE = f"https://api.telegram.org/bot{BOT_TOKEN}"


def tg_send(chat_id: int, text: str, parse_mode: str = None) -> dict:
    """Send a message, auto-chunking if too long."""
    chunks = chunk_text(text, MAX_TG_MESSAGE_LENGTH)
    result = None
    for chunk in chunks:
        payload = {"chat_id": chat_id, "text": chunk}
        if parse_mode:
            payload["parse_mode"] = parse_mode
        try:
            r = requests.post(f"{API_BASE}/sendMessage", json=payload, timeout=30)
            result = r.json()
        except Exception as e:
            log.error(f"TG send error: {e}")
    return result


def tg_send_typing(chat_id: int):
    """Show typing indicator."""
    try:
        requests.post(
            f"{API_BASE}/sendChatAction",
            json={"chat_id": chat_id, "action": "typing"},
            timeout=10,
        )
    except Exception:
        pass


def chunk_text(text: str, max_len: int) -> list[str]:
    """Split text into chunks that fit TG message limits."""
    if len(text) <= max_len:
        return [text]

    chunks = []
    lines = text.split("\n")
    current = ""

    for line in lines:
        if len(current) + len(line) + 1 > max_len:
            if current:
                chunks.append(current)
                current = ""
            # If single line exceeds limit, hard-split it
            while len(line) > max_len:
                chunks.append(line[:max_len])
                line = line[max_len:]
            current = line
        else:
            current = current + "\n" + line if current else line

    if current:
        chunks.append(current)

    return chunks if chunks else ["(empty response)"]


# ─── Claude Code Proxy ────────────────────────────────────────────────────────


def run_claude_code(prompt: str, continue_session: bool = True, cwd: str = PROJECT_DIR) -> str:
    """
    Run Claude Code and capture output.
    - continue_session=True: uses -c flag to continue most recent session
    - continue_session=False: starts a fresh session (no -c flag)
    """
    log.info(f"Claude Code invocation (continue={continue_session}): {prompt[:100]}...")

    cmd = [CLAUDE_CODE_BIN, "--dangerously-skip-permissions"]
    if continue_session:
        cmd.append("-c")
    cmd.extend(["-p", prompt])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=CLAUDE_TIMEOUT,
            cwd=cwd,
            env={
                **os.environ,
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            },
        )

        output = result.stdout.strip()
        stderr = result.stderr.strip()

        if result.returncode != 0 and not output:
            output = f"⚠️ Claude Code error (exit {result.returncode}):\n{stderr}"
        elif stderr and not output:
            output = stderr

        if not output:
            output = "(no output)"

        return output

    except subprocess.TimeoutExpired:
        return f"⏱️ Claude Code timed out after {CLAUDE_TIMEOUT}s. The task may be too complex for a single prompt. Try breaking it down."
    except FileNotFoundError:
        return "❌ Claude Code binary not found. Is `claude` in PATH?"
    except Exception as e:
        return f"❌ Error running Claude Code: {str(e)}"


def do_handoff(chat_id: int):
    """
    Trigger session handoff:
    1. Ask Claude to summarize current state to handoff file
    2. Reset session counter
    """
    log.info("Triggering session handoff...")
    tg_send(chat_id, "🔄 Session reaching context limit. Running automatic handoff...")
    tg_send_typing(chat_id)

    handoff_prompt = (
        f"IMPORTANT: This session is about to reset. Write a comprehensive handoff document to {HANDOFF_FILE}. "
        f"Include:\n"
        f"1. SUMMARY: What was accomplished this session (files created, modified, tested)\n"
        f"2. CURRENT STATE: What is working, what is broken, what tests pass/fail\n"
        f"3. OPEN ISSUES: Any errors, warnings, or unresolved problems\n"
        f"4. NEXT STEPS: What should be done next\n"
        f"5. KEY DECISIONS: Any design decisions or changes made this session\n"
        f"6. CONTEXT: Any important details the next session needs to know\n\n"
        f"Write it as a markdown file. Be specific — include file paths, function names, error messages. "
        f"The next session will ONLY have this file for context, so don't leave anything out."
    )

    result = run_claude_code(handoff_prompt, continue_session=True)
    log.info(f"Handoff result: {result[:200]}")

    # Reset session state
    state = {"message_count": 0, "session_active": False}
    save_session_state(state)

    tg_send(chat_id, f"✅ Session handoff complete. Context saved to session-handoff.md. Next message starts a fresh session.")
    return result


def get_handoff_context() -> str:
    """Load handoff file content for new session context."""
    try:
        if Path(HANDOFF_FILE).exists():
            content = Path(HANDOFF_FILE).read_text()
            if content.strip():
                return (
                    f"\n\n--- PREVIOUS SESSION HANDOFF ---\n"
                    f"The following is a summary from your previous session. Use it for context:\n\n"
                    f"{content}\n"
                    f"--- END HANDOFF ---\n\n"
                )
    except Exception as e:
        log.error(f"Error reading handoff file: {e}")
    return ""


# ─── Slash Command Handlers ───────────────────────────────────────────────────


def cmd_status(chat_id: int):
    """Show agent session status."""
    state = load_session_state()
    msg_count = state.get("message_count", 0)
    remaining = SESSION_LIMIT - msg_count

    try:
        result = subprocess.run(
            ["tmux", "list-sessions"], capture_output=True, text=True, timeout=10
        )
        sessions = result.stdout.strip() if result.stdout.strip() else "No active tmux sessions."
    except Exception as e:
        sessions = f"Error checking sessions: {e}"

    status_text = (
        f"📊 Session Status\n\n"
        f"💬 Messages this session: {msg_count}/{SESSION_LIMIT}\n"
        f"📝 Messages until handoff: {remaining}\n"
        f"📄 Handoff file exists: {'Yes' if Path(HANDOFF_FILE).exists() else 'No'}\n\n"
        f"{sessions}"
    )
    tg_send(chat_id, status_text)


def cmd_health(chat_id: int):
    """Server health check."""
    checks = []

    # Disk
    try:
        r = subprocess.run(["df", "-h", "/"], capture_output=True, text=True, timeout=5)
        lines = r.stdout.strip().split("\n")
        if len(lines) >= 2:
            checks.append(f"💾 Disk: {lines[1].split()[3]} free")
    except Exception:
        checks.append("💾 Disk: check failed")

    # Memory
    try:
        r = subprocess.run(["free", "-h"], capture_output=True, text=True, timeout=5)
        lines = r.stdout.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            checks.append(f"🧠 RAM: {parts[2]} used / {parts[1]} total")
    except Exception:
        checks.append("🧠 RAM: check failed")

    # Claude Code
    try:
        r = subprocess.run(
            [CLAUDE_CODE_BIN, "--version"], capture_output=True, text=True, timeout=10
        )
        checks.append(f"🤖 Claude Code: {r.stdout.strip()}")
    except Exception:
        checks.append("🤖 Claude Code: not found")

    # Forge
    try:
        r = subprocess.run(
            ["forge", "--version"], capture_output=True, text=True, timeout=10
        )
        checks.append(f"🔨 Forge: {r.stdout.strip().split(chr(10))[0]}")
    except Exception:
        checks.append("🔨 Forge: not found")

    # Git
    try:
        r = subprocess.run(
            ["git", "-C", PROJECT_DIR, "log", "--oneline", "-1"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        checks.append(f"📝 Last commit: {r.stdout.strip()}")
    except Exception:
        checks.append("📝 Git: check failed")

    tg_send(chat_id, "🏥 Health Check\n\n" + "\n".join(checks))


def cmd_lessons(chat_id: int):
    """Show lessons learned."""
    path = Path(PROJECT_DIR) / "KNOWLEDGE" / "lessons.md"
    if path.exists():
        content = path.read_text()[-6000:]  # last 6000 chars
        tg_send(chat_id, f"📚 Lessons (tail)\n\n{content}")
    else:
        tg_send(chat_id, "📚 No lessons.md found yet.")


def cmd_buildlog(chat_id: int):
    """Show build log."""
    path = Path(PROJECT_DIR) / "BUILD_LOG.md"
    if path.exists():
        content = path.read_text()[-6000:]
        tg_send(chat_id, f"🏗️ Build Log (tail)\n\n{content}")
    else:
        tg_send(chat_id, "🏗️ No BUILD_LOG.md found yet.")


def cmd_tasks(chat_id: int):
    """Show current task queue / spec files."""
    spec_dir = Path(PROJECT_DIR) / "SPEC"
    if spec_dir.exists():
        specs = sorted(spec_dir.glob("*.md"))
        lines = [f"{'✅' if (Path(PROJECT_DIR) / 'contracts' / 'src' / s.stem.split('-',1)[-1]).with_suffix('.sol').exists() else '⬜'} {s.name}" for s in specs]
        tg_send(chat_id, "📋 Contract Specs\n\n" + "\n".join(lines))
    else:
        tg_send(chat_id, "📋 No SPEC/ directory found.")


def cmd_go(chat_id: int, args: str):
    """Launch a build agent on a specific task."""
    if not args:
        tg_send(chat_id, "Usage: /go <task description>\n\nExample: /go build FixedPointMath library")
        return
    tg_send(chat_id, f"🚀 Launching Claude Code agent...\n\nTask: {args}")
    tg_send_typing(chat_id)

    # /go commands use session continuity
    state = load_session_state()
    msg_count = state.get("message_count", 0)
    continue_session = msg_count > 0 and state.get("session_active", False)

    result = run_claude_code(args, continue_session=continue_session)

    # Update state
    state["message_count"] = msg_count + 1
    state["session_active"] = True
    save_session_state(state)

    tg_send(chat_id, f"✅ Agent result:\n\n{result}")


def cmd_test(chat_id: int, args: str):
    """Run tests."""
    target = args if args else ""
    tg_send(chat_id, f"🧪 Running tests{' for ' + target if target else ''}...")
    tg_send_typing(chat_id)

    try:
        cmd = ["forge", "test", "-vv"]
        if target:
            cmd.extend(["--match-contract", target])
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=120, cwd=PROJECT_DIR
        )
        output = result.stdout[-6000:] if result.stdout else result.stderr[-6000:]
        tg_send(chat_id, f"🧪 Test Results\n\n{output}")
    except subprocess.TimeoutExpired:
        tg_send(chat_id, "⏱️ Tests timed out after 120s")
    except Exception as e:
        tg_send(chat_id, f"❌ Test error: {e}")


def cmd_reset(chat_id: int):
    """Manually reset session."""
    do_handoff(chat_id)


def cmd_help(chat_id: int):
    """Show available commands."""
    help_text = """🤖 LEVER Bot — Command Center + Claude Code Proxy

📌 Slash Commands:
/status — Session status + message count
/health — Server health check
/go <task> — Launch Claude Code on a task
/test [contract] — Run forge tests
/tasks — Show spec/build status
/lessons — Show lessons learned
/buildlog — Show build log
/reset — Force session handoff + reset
/help — This message

💬 Natural Language (Claude Code Proxy):
Just type anything without a / prefix and it goes straight to Claude Code.
Sessions continue for 25 messages, then auto-handoff and reset.

Claude Code has full access to the project at /root/lever-protocol
and can read, write, and execute code."""

    tg_send(chat_id, help_text)


# ─── Message Router ───────────────────────────────────────────────────────────

COMMANDS = {
    "/status": lambda cid, _: cmd_status(cid),
    "/health": lambda cid, _: cmd_health(cid),
    "/go": lambda cid, args: cmd_go(cid, args),
    "/test": lambda cid, args: cmd_test(cid, args),
    "/tasks": lambda cid, _: cmd_tasks(cid),
    "/lessons": lambda cid, _: cmd_lessons(cid),
    "/buildlog": lambda cid, _: cmd_buildlog(cid),
    "/reset": lambda cid, _: cmd_reset(cid),
    "/help": lambda cid, _: cmd_help(cid),
    "/start": lambda cid, _: cmd_help(cid),
}


def handle_message(update: dict):
    """Route incoming message to handler."""
    msg = update.get("message", {})
    chat_id = msg.get("chat", {}).get("id")
    user_id = msg.get("from", {}).get("id")
    text = msg.get("text", "").strip()

    if not chat_id or not text:
        return

    # Security: only authorized user
    if user_id != AUTHORIZED_USER_ID:
        tg_send(chat_id, "🔒 Unauthorized.")
        log.warning(f"Unauthorized access attempt from user {user_id}")
        return

    log.info(f"Message from {user_id}: {text[:100]}")

    # Slash command?
    if text.startswith("/"):
        parts = text.split(maxsplit=1)
        cmd = parts[0].lower().split("@")[0]  # handle /cmd@botname
        args = parts[1] if len(parts) > 1 else ""

        handler = COMMANDS.get(cmd)
        if handler:
            handler(chat_id, args)
        else:
            tg_send(chat_id, f"Unknown command: {cmd}\nType /help for available commands.")
        return

    # ─── Session Management ───────────────────────────────────────────────

    state = load_session_state()
    msg_count = state.get("message_count", 0)

    # Check if we need to handoff before processing
    if msg_count >= SESSION_LIMIT:
        do_handoff(chat_id)
        state = load_session_state()  # reload after reset
        msg_count = 0

    # Determine if this is a new session or continuation
    is_new_session = msg_count == 0 or not state.get("session_active", False)

    # Build the prompt
    if is_new_session:
        # Fresh session: include project context + handoff from previous session
        handoff_context = get_handoff_context()
        contextualized_prompt = (
            f"You are working on the LEVER Protocol project at {PROJECT_DIR}. "
            f"Read CLAUDE.md for full project context. "
            f"{handoff_context}"
            f"The user asks: {text}"
        )
        continue_session = False
        log.info(f"Starting NEW session (message 1/{SESSION_LIMIT})")
    else:
        # Continuing session: just pass the message, Claude has context
        contextualized_prompt = text
        continue_session = True
        log.info(f"Continuing session (message {msg_count + 1}/{SESSION_LIMIT})")

    # Send to Claude Code
    tg_send(chat_id, f"🤖 [{msg_count + 1}/{SESSION_LIMIT}] Sending to Claude Code...")
    tg_send_typing(chat_id)

    result = run_claude_code(contextualized_prompt, continue_session=continue_session)

    # Update session state
    state["message_count"] = msg_count + 1
    state["session_active"] = True
    save_session_state(state)

    tg_send(chat_id, result)


# ─── Polling Loop ─────────────────────────────────────────────────────────────


def poll():
    """Long-polling loop for Telegram updates."""
    log.info("Bot started. Polling for updates...")
    offset = 0

    while True:
        try:
            r = requests.get(
                f"{API_BASE}/getUpdates",
                params={"offset": offset, "timeout": 30},
                timeout=35,
            )
            data = r.json()

            if not data.get("ok"):
                log.error(f"TG API error: {data}")
                time.sleep(5)
                continue

            for update in data.get("result", []):
                offset = update["update_id"] + 1
                try:
                    handle_message(update)
                except Exception as e:
                    log.error(f"Error handling update: {e}", exc_info=True)

        except requests.exceptions.Timeout:
            continue
        except requests.exceptions.ConnectionError:
            log.warning("Connection error, retrying in 5s...")
            time.sleep(5)
        except Exception as e:
            log.error(f"Polling error: {e}", exc_info=True)
            time.sleep(5)


# ─── Entry Point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if BOT_TOKEN == "YOUR_TOKEN_HERE":
        print("ERROR: Set LEVER_BOT_TOKEN environment variable or edit BOT_TOKEN in this file.")
        print("  export LEVER_BOT_TOKEN='your-token-here'")
        sys.exit(1)

    # Graceful shutdown
    def sighandler(sig, frame):
        log.info("Shutting down...")
        sys.exit(0)

    signal.signal(signal.SIGINT, sighandler)
    signal.signal(signal.SIGTERM, sighandler)

    poll()
