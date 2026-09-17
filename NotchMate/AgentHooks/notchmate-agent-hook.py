#!/usr/bin/env python3
"""NotchMate agent status hook. Writes JSON into Application Support.

Invoked by Claude Code, Codex, or Cursor hooks. Never blocks the agent:
always exit 0, never print a deny/allow decision.
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

STATUS_DIR = (
    Path.home()
    / "Library"
    / "Application Support"
    / "NotchMate"
    / "agent-status"
)


def _argv_tool() -> str | None:
    for arg in sys.argv[1:]:
        if arg in ("claude", "codex", "cursor", "pi"):
            return arg
        if arg.startswith("--tool="):
            return arg.split("=", 1)[1]
    return None


def _load_payload() -> dict:
    raw = ""
    try:
        if not sys.stdin.isatty():
            raw = sys.stdin.read()
    except Exception:
        raw = ""
    if raw and raw.strip():
        try:
            data = json.loads(raw)
            if isinstance(data, dict):
                return data
        except Exception:
            pass
    for arg in reversed(sys.argv[1:]):
        if arg.startswith("{") and arg.endswith("}"):
            try:
                data = json.loads(arg)
                if isinstance(data, dict):
                    return data
            except Exception:
                continue
    return {}


def _first_str(data: dict, *keys: str) -> str:
    for key in keys:
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _norm(value: str) -> str:
    return value.replace("-", "").replace("_", "").lower()


def _event_name(data: dict) -> str:
    return _norm(
        _first_str(
            data,
            "hook_event_name",
            "hookEventName",
            "event_name",
            "eventName",
            "event",
            "type",
            "hook_event",
        )
    )


def _notification_type(data: dict) -> str:
    return _norm(
        _first_str(
            data,
            "notification_type",
            "notificationType",
            "title",
        )
    )


def _infer_tool(data: dict, explicit: str | None) -> str:
    if explicit:
        return explicit
    env = os.environ
    if env.get("CLAUDE_CODE") or env.get("CLAUDE_PLUGIN_ROOT") or env.get("CLAUDECODE"):
        return "claude"
    if env.get("CURSOR_TRACE_ID") or env.get("CURSOR_AGENT"):
        return "cursor"
    if env.get("CODEX_HOME") or env.get("CODEX_THREAD_ID"):
        return "codex"
    if env.get("PI_CODING_AGENT") or "pi-coding-agent" in env.get("npm_package_name", ""):
        return "pi"
    cwd_hint = _first_str(data, "cwd", "workspace_roots")
    return "claude"


def _session_id(data: dict) -> str:
    sid = _first_str(
        data,
        "session_id",
        "sessionId",
        "conversation_id",
        "conversationId",
        "thread_id",
        "thread-id",
        "threadId",
        "generation_id",
        "chatId",
    )
    if sid:
        return sid
    cwd = _first_str(data, "cwd")
    if cwd:
        return cwd.replace("/", "_")[-80:]
    return "default"


def _cwd(data: dict) -> str:
    cwd = _first_str(data, "cwd", "workspace_root", "workspaceRoot")
    if cwd:
        return cwd
    roots = data.get("workspace_roots") or data.get("workspaceRoots")
    if isinstance(roots, list) and roots:
        first = roots[0]
        if isinstance(first, str):
            return first
    return os.environ.get("PWD") or ""


def _state_for(tool: str, data: dict) -> str:
    event = _event_name(data)
    ntype = _notification_type(data)
    combined = f"{event} {ntype}"

    approval_tokens = (
        "permissionrequest",
        "permissionprompt",
        "permission_prompt",
        "needsinput",
        "elicitation",
        "approvalrequested",
        "approval-requested",
        "askuser",
    )
    if tool in ("claude", "codex") and any(token in combined for token in approval_tokens):
        return "approval"

    running_tokens = (
        "sessionstart",
        "userpromptsubmit",
        "beforesubmitprompt",
        "pretooluse",
        "posttooluse",
        "subagentstart",
        "afteragentthought",
        "afteragentresponse",
        "agentstart",
        "taskcreated",
    )
    if any(token in event for token in running_tokens):
        return "running"

    idle_tokens = (
        "idleprompt",
        "idle",
        "agentcompleted",
        "agentturncomplete",
        "agent-turn-complete",
    )
    if any(token in combined for token in idle_tokens):
        return "idle"

    done_tokens = (
        "stop",
        "sessionend",
        "subagentstop",
        "agentend",
        "agentsettled",
    )
    if any(token in event for token in done_tokens):
        return "done"

    if tool == "codex" and data.get("type") == "agent-turn-complete":
        return "idle"

    return "running"


def _safe_name(tool: str, session: str) -> str:
    raw = f"{tool}-{session}"
    return "".join(ch if ch.isalnum() or ch in "-_." else "_" for ch in raw)[:140]


def write_status(tool: str, session: str, cwd: str, state: str) -> None:
    STATUS_DIR.mkdir(parents=True, exist_ok=True)
    path = STATUS_DIR / f"{_safe_name(tool, session)}.json"
    payload = {
        "tool": tool,
        "session": session,
        "cwd": cwd,
        "state": state,
        "updatedAt": time.time(),
    }
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload), encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    data = _load_payload()
    tool = _infer_tool(data, _argv_tool())
    session = _session_id(data)
    cwd = _cwd(data)
    state = _state_for(tool, data)
    try:
        write_status(tool, session, cwd, state)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
