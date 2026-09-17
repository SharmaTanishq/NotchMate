//
//  NotchMateUsage.swift
//  NotchMate
//
//  Local usage only. Claude Code JSONL (deduped message ids), Codex
//  token_usage_record events, Cursor conversation/line stats (no token log).
//

import Combine
import Foundation
import SQLite3

struct NotchMateUsageTotals: Equatable, Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var turns: Int = 0
    var sessions: Int = 0
    var extraLabel: String?
    var extraValue: String?

    var billedTokens: Int { inputTokens + outputTokens }

    var headline: String {
        if billedTokens > 0 {
            return Self.compact(billedTokens)
        }
        if let extraValue {
            return extraValue
        }
        return "—"
    }

    var headlineUnit: String {
        if billedTokens > 0 { return "tokens today" }
        if let extraLabel { return extraLabel }
        return "today"
    }

    var caption: String {
        if billedTokens > 0 {
            return "\(Self.compact(inputTokens)) in · \(Self.compact(outputTokens)) out · \(turns) turns"
        }
        if let extraLabel, let extraValue {
            return "\(extraValue) \(extraLabel)"
        }
        return "No local usage yet"
    }

    mutating func merge(_ other: NotchMateUsageTotals) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        turns += other.turns
        sessions += other.sessions
        if extraLabel == nil {
            extraLabel = other.extraLabel
            extraValue = other.extraValue
        }
    }

    static func compact(_ value: Int) -> String {
        let number = Double(value)
        switch number {
        case 1_000_000_000...:
            return String(format: "%.1fB", number / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", number / 1_000_000)
        case 1_000...:
            return String(format: "%.1fk", number / 1_000)
        default:
            return "\(value)"
        }
    }
}

struct NotchMateToolUsage: Identifiable, Equatable, Sendable {
    var tool: NotchMateAgentTool
    var today: NotchMateUsageTotals
    var honesty: String

    var id: String { tool.rawValue }
}

@MainActor
final class NotchMateUsage: ObservableObject {
    static let shared = NotchMateUsage()

    @Published private(set) var isEnabled = false
    @Published private(set) var tools: [NotchMateToolUsage] = []
    @Published private(set) var liveByKey: [String: NotchMateUsageTotals] = [:]
    @Published private(set) var lastError: String?

    private var flagsCancellable: AnyCancellable?
    private var agentsCancellable: AnyCancellable?
    private var timer: Timer?
    private var scanTask: Task<Void, Never>?

    private init() {}

    func bind(flags: NotchMateFeatureFlags) {
        flagsCancellable = flags.$usageEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.setEnabled(enabled)
            }
        agentsCancellable = NotchMateAgents.shared.$sessions
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard self?.isEnabled == true else { return }
                self?.refresh()
            }
        setEnabled(flags.usageEnabled)
    }

    func liveStats(for session: NotchMateAgentSession) -> NotchMateUsageTotals? {
        liveByKey[Self.key(session.tool, session.cwd)]
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        timer?.invalidate()
        timer = nil
        scanTask?.cancel()
        guard enabled else {
            tools = []
            liveByKey = [:]
            return
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func refresh() {
        scanTask?.cancel()
        let liveSessions = NotchMateAgents.shared.visibleSessions
        scanTask = Task.detached(priority: .utility) {
            let snapshot = NotchMateUsageScanner.scan(liveSessions: liveSessions)
            await MainActor.run {
                self.tools = snapshot.tools
                self.liveByKey = snapshot.live
                self.lastError = snapshot.error
            }
        }
    }

    nonisolated static func key(_ tool: NotchMateAgentTool, _ cwd: String) -> String {
        "\(tool.rawValue)|\(cwd)"
    }
}

private struct NotchMateUsageScan: Sendable {
    var tools: [NotchMateToolUsage]
    var live: [String: NotchMateUsageTotals]
    var error: String?
}

private nonisolated enum NotchMateUsageScanner {
    static func scan(liveSessions: [NotchMateAgentSession]) -> NotchMateUsageScan {
        let claude = scanClaude(live: liveSessions)
        let cursor = scanCursor()
        let codex = scanCodex(live: liveSessions)
        var live: [String: NotchMateUsageTotals] = [:]
        live.merge(claude.live) { _, new in new }
        live.merge(codex.live) { _, new in new }

        let tools: [NotchMateToolUsage] = [
            .init(
                tool: .claude,
                today: claude.today,
                honesty: "From ~/.claude/projects JSONL. Input + output tokens, deduped by message id. Cache reads are omitted so the number matches /stats."
            ),
            .init(
                tool: .cursor,
                today: cursor,
                honesty: "Cursor does not store token counts locally. Today is conversations updated and AI lines from Cursor’s tracking database."
            ),
            .init(
                tool: .codex,
                today: codex.today,
                honesty: "From ~/.codex/sessions token_usage_record events, summed per response id."
            ),
        ]
        return NotchMateUsageScan(tools: tools, live: live, error: nil)
    }

    private static func startOfToday() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    // MARK: Claude

    private static func scanClaude(live: [NotchMateAgentSession]) -> (today: NotchMateUsageTotals, live: [String: NotchMateUsageTotals]) {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        let todayStart = startOfToday()
        var today = NotchMateUsageTotals()
        var seenIDs = Set<String>()
        var sessionIDs = Set<String>()
        var liveTotals: [String: NotchMateUsageTotals] = [:]
        let liveCwds = Set(live.filter { $0.tool == .claude }.map(\.cwd))

        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return (today, [:])
        }
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let mtime = values?.contentModificationDate
            let maybeToday = (mtime ?? .distantPast) >= todayStart
            let projectCWD = claudeCWD(fromProjectURL: url)
            let watchLive = liveCwds.contains(where: { $0 == projectCWD || projectCWD.hasPrefix($0) || $0.hasPrefix(projectCWD) })
            guard maybeToday || watchLive else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var fileTotals = NotchMateUsageTotals()
            var fileSeen = Set<String>()
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let timestamp = (json["timestamp"] as? String).flatMap(parseTimestamp)
                let isToday = timestamp.map { $0 >= todayStart } ?? maybeToday
                if let sid = json["sessionId"] as? String, isToday {
                    sessionIDs.insert(sid)
                }
                guard json["type"] as? String == "assistant" else { continue }
                guard let message = json["message"] as? [String: Any] else { continue }
                guard let usage = message["usage"] as? [String: Any] else { continue }
                let mid = (message["id"] as? String) ?? (json["uuid"] as? String) ?? UUID().uuidString
                if fileSeen.contains(mid) { continue }
                fileSeen.insert(mid)
                let input = int(usage["input_tokens"])
                let output = int(usage["output_tokens"])
                fileTotals.inputTokens += input
                fileTotals.outputTokens += output
                fileTotals.turns += 1
                if isToday, !seenIDs.contains(mid) {
                    seenIDs.insert(mid)
                    today.inputTokens += input
                    today.outputTokens += output
                    today.turns += 1
                }
            }
            if watchLive {
                for session in live where session.tool == .claude {
                    let cwd = session.cwd
                    let matches = cwd == projectCWD
                        || (!projectCWD.isEmpty && (cwd.hasPrefix(projectCWD) || projectCWD.hasPrefix(cwd)))
                    guard matches else { continue }
                    var current = liveTotals[NotchMateUsage.key(.claude, cwd)] ?? NotchMateUsageTotals()
                    current.merge(fileTotals)
                    liveTotals[NotchMateUsage.key(.claude, cwd)] = current
                }
            }
        }
        today.sessions = sessionIDs.count
        return (today, liveTotals)
    }

    private static func claudeCWD(fromProjectURL url: URL) -> String {
        let folder = url.deletingLastPathComponent().lastPathComponent
        if folder.hasPrefix("-") {
            return folder.replacingOccurrences(of: "-", with: "/")
        }
        return folder
    }

    // MARK: Codex

    private static func scanCodex(live: [NotchMateAgentSession]) -> (today: NotchMateUsageTotals, live: [String: NotchMateUsageTotals]) {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        let todayStart = startOfToday()
        var today = NotchMateUsageTotals()
        var seen = Set<String>()
        var sessions = Set<String>()
        var liveTotals: [String: NotchMateUsageTotals] = [:]
        let liveCwds = Set(live.filter { $0.tool == .codex }.map(\.cwd))

        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return (today, [:])
        }
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let maybeToday = (mtime ?? .distantPast) >= todayStart
            guard maybeToday || !liveCwds.isEmpty else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var cwd = ""
            var fileTotals = NotchMateUsageTotals()
            var fileSeen = Set<String>()
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let type = json["type"] as? String
                let payload = json["payload"] as? [String: Any] ?? [:]
                if type == "session_meta" {
                    cwd = payload["cwd"] as? String ?? ""
                    if let sid = payload["session_id"] as? String {
                        let ts = (json["timestamp"] as? String).flatMap(parseTimestamp)
                        if ts.map({ $0 >= todayStart }) ?? maybeToday {
                            sessions.insert(sid)
                        }
                    }
                }
                guard type == "token_usage_record" else { continue }
                let rid = (payload["response_id"] as? String) ?? UUID().uuidString
                let usage = payload["usage"] as? [String: Any] ?? [:]
                let input = int(usage["input_tokens"])
                let output = int(usage["output_tokens"])
                if !fileSeen.contains(rid) {
                    fileSeen.insert(rid)
                    fileTotals.inputTokens += input
                    fileTotals.outputTokens += output
                    fileTotals.turns += 1
                }
                let ts = (json["timestamp"] as? String).flatMap(parseTimestamp)
                if (ts.map { $0 >= todayStart } ?? maybeToday), !seen.contains(rid) {
                    seen.insert(rid)
                    today.inputTokens += input
                    today.outputTokens += output
                    today.turns += 1
                }
            }
            fileTotals.sessions = 1
            if liveCwds.contains(cwd) {
                liveTotals[NotchMateUsage.key(.codex, cwd)] = fileTotals
            }
        }
        today.sessions = sessions.count
        return (today, liveTotals)
    }

    // MARK: Cursor

    private static func scanCursor() -> NotchMateUsageTotals {
        var totals = NotchMateUsageTotals()
        let db = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cursor/ai-tracking/ai-code-tracking.db")
        guard FileManager.default.fileExists(atPath: db.path) else { return totals }
        var handle: OpaquePointer?
        let uri = "file:\(db.path)?mode=ro"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let handle else {
            return totals
        }
        defer { sqlite3_close(handle) }
        let startMs = Int64(startOfToday().timeIntervalSince1970 * 1000)
        totals.sessions = intQuery(handle, "SELECT COUNT(*) FROM conversation_summaries WHERE updatedAt >= \(startMs)")
        totals.turns = intQuery(handle, "SELECT COUNT(*) FROM ai_code_hashes WHERE createdAt >= \(startMs)")
        let lines = intQuery(handle, "SELECT IFNULL(SUM(composerLinesAdded),0) FROM scored_commits WHERE scoredAt >= \(startMs)")
        totals.extraLabel = "AI lines today"
        totals.extraValue = NotchMateUsageTotals.compact(lines)
        return totals
    }

    private static func intQuery(_ db: OpaquePointer, _ sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return 0 }
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }
        return 0
    }

    private static func int(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? Int64 { return Int(n) }
        if let n = value as? Double { return Int(n) }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }
}

