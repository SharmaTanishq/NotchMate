//
//  NotchMateAgents.swift
//  NotchMate
//
//  Watches Application Support JSON written by opt-in agent hooks.
//

import Combine
import Foundation

enum NotchMateAgentTool: String, CaseIterable, Identifiable, Codable {
    case claude
    case codex
    case cursor
    case pi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .pi: return "Pi"
        }
    }

    /// Only Claude Code and Codex expose a permission-request hook we can honor.
    var canSignalApproval: Bool {
        switch self {
        case .claude, .codex: return true
        case .cursor, .pi: return false
        }
    }
}

enum NotchMateAgentState: String, Codable {
    case running
    case idle
    case done
    case approval

    var title: String {
        switch self {
        case .running: return "Running"
        case .idle: return "Idle"
        case .done: return "Done"
        case .approval: return "Needs approval"
        }
    }
}

struct NotchMateAgentSession: Identifiable, Equatable, Codable {
    var tool: NotchMateAgentTool
    var session: String
    var cwd: String
    var state: NotchMateAgentState
    var updatedAt: Date

    var id: String { "\(tool.rawValue)-\(session)" }

    var projectName: String {
        let trimmed = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty { return "Unknown project" }
        return (trimmed as NSString).lastPathComponent
    }
}

struct NotchMateAgentToolSummary: Identifiable, Equatable {
    var tool: NotchMateAgentTool
    var state: NotchMateAgentState
    var count: Int
    var cwd: String

    var id: String { tool.rawValue }

    var needsApproval: Bool { state == .approval }
}

@MainActor
final class NotchMateAgents: ObservableObject {
    static let shared = NotchMateAgents()

    @Published private(set) var isEnabled = false
    @Published private(set) var sessions: [NotchMateAgentSession] = []
    @Published private(set) var statusFolder: URL
    @Published private(set) var lastReadError: String?

    private var flagsCancellable: AnyCancellable?
    private var watcher: DispatchSourceFileSystemObject?
    private var folderDescriptor: Int32 = -1
    private var pollTimer: Timer?
    private let staleAfter: TimeInterval = 60 * 60 * 12

    private init() {
        statusFolder = NotchMateAgentPaths.statusDirectory
    }

    func bind(flags: NotchMateFeatureFlags) {
        flagsCancellable = flags.$agentsEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.setEnabled(enabled)
            }
        setEnabled(flags.agentsEnabled)
    }

    var compactSummaries: [NotchMateAgentToolSummary] {
        guard isEnabled else { return [] }
        let active = sessions.filter { $0.state != .done }
        return NotchMateAgentTool.allCases.compactMap { tool in
            let matches = active.filter { $0.tool == tool }
            guard !matches.isEmpty else { return nil }
            let state: NotchMateAgentState
            if matches.contains(where: { $0.state == .approval }) {
                state = .approval
            } else if matches.contains(where: { $0.state == .running }) {
                state = .running
            } else {
                state = .idle
            }
            return NotchMateAgentToolSummary(
                tool: tool,
                state: state,
                count: matches.count,
                cwd: matches.sorted { $0.updatedAt > $1.updatedAt }.first?.cwd ?? ""
            )
        }
    }

    var visibleSessions: [NotchMateAgentSession] {
        guard isEnabled else { return [] }
        return sessions.sorted { lhs, rhs in
            if lhs.state == .approval && rhs.state != .approval { return true }
            if rhs.state == .approval && lhs.state != .approval { return false }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
            reload()
        } else {
            stop()
            sessions = []
            lastReadError = nil
        }
    }

    private func start() {
        NotchMateAgentPaths.ensureStatusDirectory()
        startWatcher()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        watcher?.cancel()
        watcher = nil
        if folderDescriptor >= 0 {
            close(folderDescriptor)
            folderDescriptor = -1
        }
    }

    private func startWatcher() {
        watcher?.cancel()
        if folderDescriptor >= 0 {
            close(folderDescriptor)
        }
        let path = statusFolder.path
        folderDescriptor = open(path, O_EVTONLY)
        guard folderDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: folderDescriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .link, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reload()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.folderDescriptor >= 0 else { return }
            close(self.folderDescriptor)
            self.folderDescriptor = -1
        }
        watcher = source
        source.resume()
    }

    func reload() {
        guard isEnabled else { return }
        NotchMateAgentPaths.ensureStatusDirectory()
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: statusFolder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let now = Date()
            var next: [NotchMateAgentSession] = []
            for url in urls where url.pathExtension == "json" {
                if let session = Self.decode(url, now: now, staleAfter: staleAfter) {
                    next.append(session)
                }
            }
            sessions = next
            lastReadError = nil
        } catch {
            lastReadError = error.localizedDescription
        }
    }

    private static func decode(_ url: URL, now: Date, staleAfter: TimeInterval) -> NotchMateAgentSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let toolRaw = json["tool"] as? String,
              let tool = NotchMateAgentTool(rawValue: toolRaw) else { return nil }
        let session = (json["session"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url.deletingPathExtension().lastPathComponent
        let cwd = json["cwd"] as? String ?? ""
        var state = NotchMateAgentState(rawValue: json["state"] as? String ?? "") ?? .idle
        if !tool.canSignalApproval, state == .approval {
            state = .running
        }
        let updatedAt: Date
        if let epoch = json["updatedAt"] as? Double {
            updatedAt = Date(timeIntervalSince1970: epoch)
        } else if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate {
            updatedAt = modified
        } else {
            updatedAt = now
        }
        if now.timeIntervalSince(updatedAt) > staleAfter {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return NotchMateAgentSession(tool: tool, session: session, cwd: cwd, state: state, updatedAt: updatedAt)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum NotchMateAgentPaths {
    static var applicationSupport: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent("NotchMate", isDirectory: true)
    }

    static var statusDirectory: URL {
        applicationSupport.appendingPathComponent("agent-status", isDirectory: true)
    }

    static var hooksDirectory: URL {
        applicationSupport.appendingPathComponent("hooks", isDirectory: true)
    }

    static var pythonHook: URL {
        hooksDirectory.appendingPathComponent("notchmate-agent-hook.py")
    }

    static var pythonCommand: String {
        "/usr/bin/python3 \"\(pythonHook.path)\" "
    }

    static func ensureStatusDirectory() {
        try? FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
    }

    static func ensureHooksDirectory() {
        try? FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
    }
}
