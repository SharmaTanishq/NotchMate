//
//  NotchMateAgentFocus.swift
//  NotchMate
//
//  Click an agent glyph to activate that tool and, when we know the project
//  folder, try to raise the matching window.
//

import AppKit

enum NotchMateAgentFocus {
    static func reveal(tool: NotchMateAgentTool, cwd: String? = nil) {
        let folder = directory(from: cwd)
        guard let appURL = NotchMateAgentArtwork.applicationURL(for: tool) else {
            revealWithoutApp(tool: tool, folder: folder)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let finish = {
            Task { @MainActor in
                activateRunning(tool)
                raiseMatchingWindow(tool: tool, folder: folder)
            }
        }

        if opensFolderInApp(tool), let folder {
            NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: configuration) { _, _ in
                finish()
            }
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
                finish()
            }
        }
    }

    static func reveal(_ session: NotchMateAgentSession) {
        reveal(tool: session.tool, cwd: session.cwd)
    }

    static func reveal(_ summary: NotchMateAgentToolSummary) {
        reveal(tool: summary.tool, cwd: summary.cwd)
    }

    /// Cursor (and similar editors) should reopen the session folder. Chat-style
    /// apps just come to the front.
    private static func opensFolderInApp(_ tool: NotchMateAgentTool) -> Bool {
        switch tool {
        case .cursor: return true
        case .claude, .codex, .pi: return false
        }
    }

    private static func directory(from cwd: String?) -> URL? {
        guard let cwd, !cwd.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: cwd, isDirectory: true)
    }

    private static func activateRunning(_ tool: NotchMateAgentTool) {
        for bundleID in tool.bundleIdentifiers {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = running.first {
                app.activate()
                return
            }
        }
    }

    private static func revealWithoutApp(tool: NotchMateAgentTool, folder: URL?) {
        if let folder {
            NSWorkspace.shared.open(folder)
        }
        _ = tool
    }

    /// Best-effort: System Events raises a window whose title contains the project
    /// name. Fails silently if Automation isn't granted.
    private static func raiseMatchingWindow(tool: NotchMateAgentTool, folder: URL?) {
        guard let project = folder?.lastPathComponent, !project.isEmpty else { return }
        let escaped = project
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let ids = tool.bundleIdentifiers.map { "\"\($0)\"" }.joined(separator: ", ")
        guard !ids.isEmpty else { return }
        let source = """
        tell application "System Events"
          repeat with bid in {\(ids)}
            try
              tell (first process whose bundle identifier is bid)
                set frontmost to true
                if (count of windows) > 0 then
                  try
                    perform action "AXRaise" of (first window whose name contains "\(escaped)")
                  end try
                end if
              end tell
            end try
          end repeat
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
