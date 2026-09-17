//
//  NotchMateAgentHookInstaller.swift
//  NotchMate
//
//  Consent-only merge of NotchMate status hooks. Never silently rewrites
//  ~/.claude, ~/.codex, or ~/.cursor.
//

import Foundation

struct NotchMateHookInstallResult: Equatable {
    var copiedScript: Bool
    var claude: String
    var cursor: String
    var codex: String
    var pi: String
    var notes: [String]
}

enum NotchMateAgentHookInstaller {
    static let marker = "notchmate-agent-hook.py"
    static let piFileName = "notchmate-status.ts"

    @discardableResult
    static func install() throws -> NotchMateHookInstallResult {
        NotchMateAgentPaths.ensureHooksDirectory()
        NotchMateAgentPaths.ensureStatusDirectory()
        try copyBundledHooks()

        var notes: [String] = []
        let claude = mergeClaude(notes: &notes)
        let cursor = mergeCursor(notes: &notes)
        let codex = mergeCodex(notes: &notes)
        let pi = installPiExtension(notes: &notes)
        return NotchMateHookInstallResult(
            copiedScript: true,
            claude: claude,
            cursor: cursor,
            codex: codex,
            pi: pi,
            notes: notes
        )
    }

    @discardableResult
    static func uninstall() throws -> NotchMateHookInstallResult {
        var notes: [String] = []
        let claude = stripClaude(notes: &notes)
        let cursor = stripCursor(notes: &notes)
        let codex = stripCodex(notes: &notes)
        let pi = removePiExtension(notes: &notes)
        return NotchMateHookInstallResult(
            copiedScript: FileManager.default.fileExists(atPath: NotchMateAgentPaths.pythonHook.path),
            claude: claude,
            cursor: cursor,
            codex: codex,
            pi: pi,
            notes: notes
        )
    }

    static func pythonCommand(tool: String) -> String {
        "/usr/bin/python3 \"\(NotchMateAgentPaths.pythonHook.path)\" \(tool)"
    }

    private static func copyBundledHooks() throws {
        let fm = FileManager.default
        if let source = bundledResource("notchmate-agent-hook", "py") {
            if fm.fileExists(atPath: NotchMateAgentPaths.pythonHook.path) {
                try fm.removeItem(at: NotchMateAgentPaths.pythonHook)
            }
            try fm.copyItem(at: source, to: NotchMateAgentPaths.pythonHook)
        } else {
            try Self.embeddedPython.write(to: NotchMateAgentPaths.pythonHook, atomically: true, encoding: .utf8)
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: NotchMateAgentPaths.pythonHook.path)

        let piDest = NotchMateAgentPaths.hooksDirectory.appendingPathComponent(piFileName)
        if let source = bundledResource("notchmate-pi-status", "ts") {
            if fm.fileExists(atPath: piDest.path) {
                try fm.removeItem(at: piDest)
            }
            try fm.copyItem(at: source, to: piDest)
        } else {
            try Self.embeddedPi.write(to: piDest, atomically: true, encoding: .utf8)
        }
    }

    private static func bundledResource(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "AgentHooks")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    // MARK: Claude Code — ~/.claude/settings.json

    private static func mergeClaude(notes: inout [String]) -> String {
        let url = Path.home.appendingPathComponent(".claude/settings.json")
        let command = pythonCommand(tool: "claude")
        var root = readJSON(url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let events: [(String, String)] = [
            ("Notification", ""),
            ("PermissionRequest", ""),
            ("Stop", ""),
            ("SessionStart", ""),
            ("UserPromptSubmit", ""),
            ("PreToolUse", ""),
        ]
        for (event, matcher) in events {
            hooks[event] = upsertClaudeEvent(hooks[event], command: command, matcher: matcher)
        }
        root["hooks"] = hooks
        do {
            try writeJSON(root, to: url)
            return "Merged Notification, PermissionRequest, Stop, SessionStart, UserPromptSubmit, and PreToolUse."
        } catch {
            notes.append("Claude Code: \(error.localizedDescription)")
            return "Could not write ~/.claude/settings.json"
        }
    }

    private static func stripClaude(notes: inout [String]) -> String {
        let url = Path.home.appendingPathComponent(".claude/settings.json")
        guard var root = readJSON(url) else { return "No Claude settings file." }
        guard var hooks = root["hooks"] as? [String: Any] else { return "No Claude hooks object." }
        for key in Array(hooks.keys) {
            hooks[key] = stripClaudeEvent(hooks[key])
            if let array = hooks[key] as? [Any], array.isEmpty {
                hooks.removeValue(forKey: key)
            }
        }
        root["hooks"] = hooks
        do {
            try writeJSON(root, to: url)
            return "Removed NotchMate entries from ~/.claude/settings.json."
        } catch {
            notes.append("Claude Code uninstall: \(error.localizedDescription)")
            return "Could not update Claude settings."
        }
    }

    private static func upsertClaudeEvent(_ existing: Any?, command: String, matcher: String) -> [Any] {
        var groups = existing as? [Any] ?? []
        groups = groups.filter { !claudeGroupContainsMarker($0) }
        groups.append(
            [
                "matcher": matcher,
                "hooks": [
                    [
                        "type": "command",
                        "command": command,
                        "timeout": 8,
                    ],
                ],
            ] as [String: Any]
        )
        return groups
    }

    private static func stripClaudeEvent(_ existing: Any?) -> [Any] {
        (existing as? [Any] ?? []).filter { !claudeGroupContainsMarker($0) }
    }

    private static func claudeGroupContainsMarker(_ value: Any) -> Bool {
        guard let group = value as? [String: Any] else { return false }
        if let command = group["command"] as? String, command.contains(marker) {
            return true
        }
        guard let hooks = group["hooks"] as? [Any] else { return false }
        return hooks.contains { hook in
            guard let dict = hook as? [String: Any], let command = dict["command"] as? String else {
                return false
            }
            return command.contains(marker)
        }
    }

    // MARK: Cursor — ~/.cursor/hooks.json

    private static func mergeCursor(notes: inout [String]) -> String {
        let url = Path.home.appendingPathComponent(".cursor/hooks.json")
        let command = pythonCommand(tool: "cursor")
        var root = readJSON(url) ?? [:]
        if root["version"] == nil {
            root["version"] = 1
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in ["sessionStart", "preToolUse", "afterAgentThought", "stop", "sessionEnd"] {
            hooks[event] = upsertCursorEvent(hooks[event], command: command)
        }
        root["hooks"] = hooks
        do {
            try writeJSON(root, to: url)
            return "Merged sessionStart, preToolUse, afterAgentThought, stop, and sessionEnd. Cursor has no approval hook."
        } catch {
            notes.append("Cursor: \(error.localizedDescription)")
            return "Could not write ~/.cursor/hooks.json"
        }
    }

    private static func stripCursor(notes: inout [String]) -> String {
        let url = Path.home.appendingPathComponent(".cursor/hooks.json")
        guard var root = readJSON(url) else { return "No Cursor hooks file." }
        guard var hooks = root["hooks"] as? [String: Any] else { return "No Cursor hooks object." }
        for key in Array(hooks.keys) {
            hooks[key] = stripCursorEvent(hooks[key])
            if let array = hooks[key] as? [Any], array.isEmpty {
                hooks.removeValue(forKey: key)
            }
        }
        root["hooks"] = hooks
        do {
            try writeJSON(root, to: url)
            return "Removed NotchMate entries from ~/.cursor/hooks.json."
        } catch {
            notes.append("Cursor uninstall: \(error.localizedDescription)")
            return "Could not update Cursor hooks."
        }
    }

    private static func upsertCursorEvent(_ existing: Any?, command: String) -> [Any] {
        var items = existing as? [Any] ?? []
        items = items.filter { !cursorItemContainsMarker($0) }
        items.append(["command": command] as [String: Any])
        return items
    }

    private static func stripCursorEvent(_ existing: Any?) -> [Any] {
        (existing as? [Any] ?? []).filter { !cursorItemContainsMarker($0) }
    }

    private static func cursorItemContainsMarker(_ value: Any) -> Bool {
        guard let dict = value as? [String: Any], let command = dict["command"] as? String else {
            return false
        }
        return command.contains(marker)
    }

    // MARK: Codex — ~/.codex/hooks.json

    private static func mergeCodex(notes: inout [String]) -> String {
        let url = Path.home.appendingPathComponent(".codex/hooks.json")
        let command = pythonCommand(tool: "codex")
        var root = readJSON(url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let events: [(String, String)] = [
            ("SessionStart", ""),
            ("PreToolUse", ""),
            ("PermissionRequest", ""),
            ("Stop", ""),
            ("UserPromptSubmit", ""),
        ]
        for (event, matcher) in events {
            hooks[event] = upsertClaudeEvent(hooks[event], command: command, matcher: matcher)
        }
        root["hooks"] = hooks
        if root["description"] == nil {
            root["description"] = "Includes NotchMate agent status hooks."
        }
        do {
            try writeJSON(root, to: url)
            notes.append("Codex only loads hooks.json when features.hooks is on in ~/.codex/config.toml. NotchMate does not edit that file.")
            return "Merged SessionStart, PreToolUse, PermissionRequest, Stop, and UserPromptSubmit."
        } catch {
            notes.append("Codex: \(error.localizedDescription)")
            return "Could not write ~/.codex/hooks.json"
        }
    }

    private static func stripCodex(notes: inout [String]) -> String {
        let url = Path.home.appendingPathComponent(".codex/hooks.json")
        guard var root = readJSON(url) else { return "No Codex hooks file." }
        guard var hooks = root["hooks"] as? [String: Any] else { return "No Codex hooks object." }
        for key in Array(hooks.keys) {
            hooks[key] = stripClaudeEvent(hooks[key])
            if let array = hooks[key] as? [Any], array.isEmpty {
                hooks.removeValue(forKey: key)
            }
        }
        root["hooks"] = hooks
        do {
            try writeJSON(root, to: url)
            return "Removed NotchMate entries from ~/.codex/hooks.json."
        } catch {
            notes.append("Codex uninstall: \(error.localizedDescription)")
            return "Could not update Codex hooks."
        }
    }

    // MARK: Pi — ~/.pi/agent/extensions/notchmate-status.ts

    private static func installPiExtension(notes: inout [String]) -> String {
        let dest = Path.home.appendingPathComponent(".pi/agent/extensions/\(piFileName)")
        let source = NotchMateAgentPaths.hooksDirectory.appendingPathComponent(piFileName)
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return "Installed ~/.pi/agent/extensions/\(piFileName). Pi has no approval hook."
        } catch {
            notes.append("Pi: \(error.localizedDescription)")
            return "Could not write Pi extension."
        }
    }

    private static func removePiExtension(notes: inout [String]) -> String {
        let dest = Path.home.appendingPathComponent(".pi/agent/extensions/\(piFileName)")
        guard FileManager.default.fileExists(atPath: dest.path) else {
            return "No Pi extension installed."
        }
        do {
            try FileManager.default.removeItem(at: dest)
            return "Removed ~/.pi/agent/extensions/\(piFileName)."
        } catch {
            notes.append("Pi uninstall: \(error.localizedDescription)")
            return "Could not remove Pi extension."
        }
    }

    // MARK: JSON helpers

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func writeJSON(_ root: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        var text = String(data: data, encoding: .utf8) ?? "{}"
        text.append("\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private enum Path {
        static var home: URL { URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) }
    }

    private static let embeddedPython = """
    #!/usr/bin/env python3
    import json, os, sys, time
    from pathlib import Path
    STATUS_DIR = Path.home() / "Library/Application Support/NotchMate/agent-status"
    def main():
        raw = sys.stdin.read() if not sys.stdin.isatty() else ""
        data = {}
        if raw.strip():
            try:
                data = json.loads(raw)
            except Exception:
                data = {}
        tool = next((a for a in sys.argv[1:] if a in ("claude","codex","cursor","pi")), "claude")
        event = str(data.get("hook_event_name") or data.get("hookEventName") or data.get("type") or "")
        ntype = str(data.get("notification_type") or "")
        blob = (event + " " + ntype).replace("-", "").replace("_", "").lower()
        state = "running"
        if tool in ("claude", "codex") and any(t in blob for t in ("permissionrequest", "permissionprompt", "needsinput", "elicitation")):
            state = "approval"
        elif any(t in blob for t in ("stop", "sessionend", "agentsettled")):
            state = "done"
        elif any(t in blob for t in ("idle", "agentturncomplete")):
            state = "idle"
        session = str(data.get("session_id") or data.get("sessionId") or data.get("thread_id") or data.get("cwd") or "default")
        cwd = str(data.get("cwd") or "")
        STATUS_DIR.mkdir(parents=True, exist_ok=True)
        name = "".join(c if c.isalnum() or c in "-_." else "_" for c in f"{tool}-{session}")[:140]
        path = STATUS_DIR / f"{name}.json"
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"tool": tool, "session": session, "cwd": cwd, "state": state, "updatedAt": time.time()}))
        tmp.replace(path)
        return 0
    if __name__ == "__main__":
        raise SystemExit(main())
    """

    private static let embeddedPi = """
    export default function (pi: any) {
      const HOOK = `${process.env.HOME}/Library/Application Support/NotchMate/hooks/notchmate-agent-hook.py`
      function write(event: string, ctx: any) {
        try {
          const { spawn } = require("node:child_process")
          const child = spawn("python3", [HOOK, "pi"], { stdio: ["pipe", "ignore", "ignore"] })
          child.stdin?.end(JSON.stringify({ hook_event_name: event, cwd: String(ctx?.cwd || process.cwd()), session_id: String(ctx?.cwd || "default") }))
        } catch {}
      }
      pi.on("session_start", (_e: unknown, ctx: any) => write("SessionStart", ctx))
      pi.on("agent_start", (_e: unknown, ctx: any) => write("SessionStart", ctx))
      pi.on("agent_end", (_e: unknown, ctx: any) => write("Stop", ctx))
      pi.on("agent_settled", (_e: unknown, ctx: any) => write("SessionEnd", ctx))
    }
    """
}
