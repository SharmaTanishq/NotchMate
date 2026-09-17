//
//  NotchMateAgentArtwork.swift
//  NotchMate
//
//  Compact/expanded glyphs use the installed app logos (NSWorkspace), not
//  letter monograms. Missing apps fall back to a symbol, never "C" / "X".
//

import AppKit

enum NotchMateAgentArtwork {
    private static var cache: [NotchMateAgentTool: NSImage] = [:]

    static func image(for tool: NotchMateAgentTool) -> NSImage? {
        if let cached = cache[tool] {
            return cached
        }
        guard let url = applicationURL(for: tool) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 128, height: 128)
        cache[tool] = icon
        return icon
    }

    static func applicationURL(for tool: NotchMateAgentTool) -> URL? {
        let workspace = NSWorkspace.shared
        for bundleID in tool.bundleIdentifiers {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
        }
        for name in tool.applicationFileNames {
            let url = URL(fileURLWithPath: "/Applications/\(name)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

extension NotchMateAgentTool {
    var bundleIdentifiers: [String] {
        switch self {
        case .claude:
            return [
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude",
                "com.anthropic.claude-code",
            ]
        case .codex:
            return [
                "com.openai.codex",
                "com.openai.chatgpt",
                "com.openai.chat",
            ]
        case .cursor:
            return [
                "com.todesktop.230313mzl4w4u92",
                "com.anysphere.cursor",
                "com.cursor.Cursor",
            ]
        case .pi:
            return [
                "ai.pi.coding-agent",
                "com.badlogic.pi",
                "sh.pi.agent",
            ]
        }
    }

    var applicationFileNames: [String] {
        switch self {
        case .claude:
            return ["Claude.app", "Claude Code.app"]
        case .codex:
            return ["ChatGPT.app", "Codex.app"]
        case .cursor:
            return ["Cursor.app"]
        case .pi:
            return ["Pi.app", "Pi Code.app"]
        }
    }

    /// Last resort when the app is not installed — a mark, not a letter.
    var fallbackSymbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "bubble.left.and.bubble.right.fill"
        case .cursor: return "cursorarrow.rays"
        case .pi: return "circle.hexagongrid.fill"
        }
    }
}
