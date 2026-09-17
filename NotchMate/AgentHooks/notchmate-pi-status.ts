// NotchMate status extension for Pi.
// Pi has no permission-request hook. Maps start / tool / end / settled
// to running / idle / done and never reports approval.
const HOOK = `${process.env.HOME}/Library/Application Support/NotchMate/hooks/notchmate-agent-hook.py`

function cwdFrom(ctx: any): string {
  try {
    return String(ctx?.cwd || process.cwd() || "")
  } catch {
    return process.cwd()
  }
}

function sessionFrom(ctx: any): string {
  try {
    const file = ctx?.sessionManager?.getSessionFile?.()
    if (file) return String(file)
  } catch {
    /* ignore */
  }
  const cwd = cwdFrom(ctx)
  return cwd ? cwd.replace(/\//g, "_").slice(-80) : "default"
}

function write(state: string, ctx: any): void {
  try {
    const { spawn } = require("node:child_process") as typeof import("node:child_process")
    const payload = JSON.stringify({
      hook_event_name: state === "running" ? "SessionStart" : state === "idle" ? "Stop" : "SessionEnd",
      session_id: sessionFrom(ctx),
      cwd: cwdFrom(ctx),
      tool: "pi",
    })
    const child = spawn("python3", [HOOK, "pi"], {
      stdio: ["pipe", "ignore", "ignore"],
    })
    child.stdin?.end(payload)
  } catch {
    /* never block Pi */
  }
}

export default function (pi: any) {
  pi.on("session_start", (_event: unknown, ctx: any) => write("running", ctx))
  pi.on("agent_start", (_event: unknown, ctx: any) => write("running", ctx))
  pi.on("tool_call", (_event: unknown, ctx: any) => write("running", ctx))
  pi.on("agent_end", (_event: unknown, ctx: any) => write("idle", ctx))
  pi.on("agent_settled", (_event: unknown, ctx: any) => write("done", ctx))
  pi.on("session_shutdown", (_event: unknown, ctx: any) => write("done", ctx))
}
