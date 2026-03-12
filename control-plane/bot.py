#!/usr/bin/env python3
"""LEVER Build Agent — Telegram Bot"""

import os
import subprocess
import asyncio
import glob
from datetime import datetime
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

load_dotenv()
TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
ALLOWED_USER = int(os.getenv("TELEGRAM_USER_ID"))
REPO = "/root/lever-protocol"

def auth(func):
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if update.effective_user.id != ALLOWED_USER:
            return
        return await func(update, context)
    return wrapper

def run_cmd(cmd, cwd=REPO, timeout=60):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, timeout=timeout)
        output = (result.stdout + result.stderr).strip()
        return output if output else "(no output)"
    except subprocess.TimeoutExpired:
        return "timed out"
    except Exception as e:
        return f"Error: {e}"

def truncate(text, limit=3800):
    return text if len(text) <= limit else "...(truncated)...\n\n" + text[-limit:]

@auth
async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "LEVER Build Agent\n\n"
        "/status - Latest build progress\n"
        "/health - System health check\n"
        "/tasks - Task queue overview\n"
        "/sessions - Active agent sessions\n"
        "/go <agent> <worktree> - Launch agent on a task\n"
        "/approve <branch> - Merge branch to main\n"
        "/test - Run forge test suite\n"
        "/lessons - View accumulated lessons\n"
        "/brief - Latest daily planning brief\n"
        "/project <path> - Switch active project\n"
        "/help - Show this message"
    )

@auth
async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    log_file = f"{REPO}/BUILD_LOG.md"
    if not os.path.exists(log_file):
        await update.message.reply_text("No build log yet.")
        return
    with open(log_file) as f:
        lines = f.readlines()
    entries = [l.strip() for l in lines if l.strip() and not l.startswith("#") and not l.startswith("---") and "|" in l]
    recent = entries[-15:] if len(entries) > 15 else entries
    if not recent:
        await update.message.reply_text("Build log exists but no entries yet.")
        return
    await update.message.reply_text("Recent Build Activity:\n\n" + "\n".join(recent))

@auth
async def cmd_health(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Running health checks...")
    checks = []
    tmux_out = run_cmd("tmux list-panes -t lever:agents -F '#{pane_index}: #{pane_current_command}' 2>/dev/null")
    if "error" in tmux_out.lower() or "no server" in tmux_out.lower() or "no session" in tmux_out.lower():
        checks.append("tmux: No active session")
    else:
        panes = [l for l in tmux_out.strip().split('\n') if l.strip()]
        active = len([l for l in panes if 'claude' in l.lower() or 'launch' in l.lower()])
        checks.append(f"Agents: {active}/4 running")
    build_out = run_cmd("forge build 2>&1", timeout=120)
    if "nothing to compile" in build_out.lower() or "no files" in build_out.lower():
        checks.append("Forge: OK (no contracts yet)")
    elif "error" in build_out.lower():
        checks.append("Forge build: FAILING")
    else:
        checks.append("Forge build: passing")
    disk_out = run_cmd("df -h / | tail -1 | awk '{print $4}'")
    checks.append(f"Disk free: {disk_out.strip()}")
    commit_out = run_cmd("git log --oneline -1 --format='%ar: %s'")
    checks.append(f"Last commit: {commit_out.strip()}")
    log_file = f"{REPO}/BUILD_LOG.md"
    if os.path.exists(log_file):
        mtime = os.path.getmtime(log_file)
        age_hours = (datetime.now().timestamp() - mtime) / 3600
        checks.append(f"Build log: updated {age_hours:.1f}h ago")
    await update.message.reply_text("Health Report:\n\n" + "\n".join(checks))

@auth
async def cmd_test(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Running forge test... (may take a minute)")
    result = run_cmd("forge test --summary 2>&1", timeout=300)
    await update.message.reply_text(f"Test Results:\n\n{truncate(result, 3500)}")

@auth
async def cmd_approve(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.args:
        await update.message.reply_text("Usage: /approve branch-name")
        return
    branch = context.args[0]
    await update.message.reply_text(f"Merging {branch} into main...")
    run_cmd("git stash 2>/dev/null")
    run_cmd("git checkout main")
    run_cmd("git pull origin main")
    result = run_cmd(f"git merge origin/{branch} --no-edit 2>&1")
    if "conflict" in result.lower():
        await update.message.reply_text(f"Merge conflict!\n\n{truncate(result, 3000)}")
        return
    build = run_cmd("forge build 2>&1", timeout=120)
    if "error" in build.lower() and "nothing" not in build.lower():
        await update.message.reply_text(f"Merged but build fails:\n\n{truncate(build, 3000)}")
        return
    run_cmd("git push origin main")
    await update.message.reply_text(f"{branch} merged to main. Build passes. Pushed.")

@auth
async def cmd_go(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.args or len(context.args) < 2:
        await update.message.reply_text("Usage: /go <agent-number> <worktree-name>\nExample: /go 1 vault-build")
        return
    agent_num = context.args[0]
    worktree = context.args[1]
    pane = int(agent_num) - 1
    run_cmd(f"tmux send-keys -t lever:agents.{pane} C-c 2>/dev/null")
    run_cmd(f"tmux send-keys -t lever:agents.{pane} '/root/launch-agent.sh {agent_num} {worktree}' Enter")
    await update.message.reply_text(f"Agent {agent_num} launched on {worktree}")

@auth
async def cmd_sessions(update: Update, context: ContextTypes.DEFAULT_TYPE):
    pane_info = run_cmd("tmux list-panes -t lever:agents -F 'Pane #{pane_index}: #{pane_current_command}' 2>/dev/null")
    worktrees = run_cmd("cd /root/lever-protocol && git worktree list 2>/dev/null")
    msg = f"Sessions:\n{pane_info}\n\nWorktrees:\n{truncate(worktrees, 1500)}"
    await update.message.reply_text(msg)

@auth
async def cmd_tasks(update: Update, context: ContextTypes.DEFAULT_TYPE):
    tasks_file = f"{REPO}/TASK_QUEUE.md"
    if not os.path.exists(tasks_file):
        await update.message.reply_text("No task queue file found.")
        return
    with open(tasks_file) as f:
        lines = f.readlines()
    status_lines = [l.strip() for l in lines if "|" in l and any(s in l for s in ["TODO","IN_PROGRESS","REVIEW","FIXING","DONE"])]
    done = len([l for l in status_lines if "DONE" in l])
    in_progress = len([l for l in status_lines if "IN_PROGRESS" in l])
    review = len([l for l in status_lines if "REVIEW" in l])
    todo = len([l for l in status_lines if "TODO" in l])
    total = done + in_progress + review + todo
    pct = (done / total * 100) if total > 0 else 0
    filled = int(pct / 5)
    bar = "=" * filled + "-" * (20 - filled)
    msg = f"Task Progress:\n\n[{bar}] {pct:.0f}%\n\nDone: {done}/{total}\nBuilding: {in_progress}\nIn Review: {review}\nTodo: {todo}"
    active = [l.strip() for l in status_lines if any(s in l for s in ["IN_PROGRESS","REVIEW","FIXING"])]
    if active:
        msg += "\n\nActive:\n" + "\n".join(active[:8])
    await update.message.reply_text(msg)

@auth
async def cmd_lessons(update: Update, context: ContextTypes.DEFAULT_TYPE):
    lessons_file = f"{REPO}/KNOWLEDGE/lessons.md"
    if not os.path.exists(lessons_file):
        await update.message.reply_text("No lessons file yet.")
        return
    with open(lessons_file) as f:
        content = f.read()
    if len(content.strip()) < 100:
        await update.message.reply_text("Lessons file exists but no entries yet.")
        return
    await update.message.reply_text(f"Lessons Learned:\n\n{truncate(content)}")

@auth
async def cmd_brief(update: Update, context: ContextTypes.DEFAULT_TYPE):
    briefs = sorted(glob.glob("/root/daily-briefs/*.md"))
    if not briefs:
        await update.message.reply_text("No daily briefs yet. They appear once the daily planning cron runs.")
        return
    with open(briefs[-1]) as f:
        content = f.read()
    await update.message.reply_text(f"Daily Brief ({os.path.basename(briefs[-1])}):\n\n{truncate(content)}")

@auth
async def cmd_project(update: Update, context: ContextTypes.DEFAULT_TYPE):
    global REPO
    if not context.args:
        await update.message.reply_text(f"Active project: {REPO}\n\nUsage: /project <path>\nOr: /project list")
        return
    if context.args[0] == "list":
        projects = ["/root/lever-protocol"]
        for d in glob.glob("/root/workspace/*/"):
            if os.path.isdir(d):
                projects.append(d.rstrip("/"))
        await update.message.reply_text("Projects:\n\n" + "\n".join(projects))
        return
    path = context.args[0]
    if os.path.isdir(path):
        REPO = path
        await update.message.reply_text(f"Switched to {path}")
    else:
        await update.message.reply_text(f"Directory not found: {path}")

async def monitor_callback(context: ContextTypes.DEFAULT_TYPE):
    log_file = f"{REPO}/BUILD_LOG.md"
    try:
        if os.path.exists(log_file):
            mtime = os.path.getmtime(log_file)
            age_hours = (datetime.now().timestamp() - mtime) / 3600
            if age_hours >= 4:
                await context.bot.send_message(chat_id=ALLOWED_USER, text="No build activity in 4+ hours. Check /sessions and /health.")
    except Exception as e:
        print(f"Monitor error: {e}")

def main():
    print(f"[{datetime.now()}] Starting LEVER Build Agent bot...")
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", cmd_help))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("health", cmd_health))
    app.add_handler(CommandHandler("test", cmd_test))
    app.add_handler(CommandHandler("approve", cmd_approve))
    app.add_handler(CommandHandler("go", cmd_go))
    app.add_handler(CommandHandler("sessions", cmd_sessions))
    app.add_handler(CommandHandler("tasks", cmd_tasks))
    app.add_handler(CommandHandler("lessons", cmd_lessons))
    app.add_handler(CommandHandler("brief", cmd_brief))
    app.add_handler(CommandHandler("project", cmd_project))
    app.job_queue.run_repeating(monitor_callback, interval=1800, first=60)
    print(f"[{datetime.now()}] Bot running. Commands: /help")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
