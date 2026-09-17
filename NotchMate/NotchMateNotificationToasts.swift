//
//  NotchMateNotificationToasts.swift
//  NotchMate
//
//  Mirrors selected macOS Notification Center banners into NookActivityQueue.
//  Reads usernoted's SQLite (undocumented). Needs Full Disk Access.
//

import AppKit
import Combine
import Foundation
import NookComponents
import SQLite3

struct NotchMateNotificationSource: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let title: String
    let systemImage: String
}

@MainActor
final class NotchMateNotificationToasts: ObservableObject {
    static let shared = NotchMateNotificationToasts()

    static let catalog: [NotchMateNotificationSource] = [
        .init(bundleID: "com.tinyspeck.slackmacgap", title: "Slack", systemImage: "number"),
        .init(bundleID: "com.apple.mail", title: "Mail", systemImage: "envelope"),
        .init(bundleID: "com.apple.MobileSMS", title: "Messages", systemImage: "message"),
        .init(bundleID: "com.apple.iCal", title: "Calendar", systemImage: "calendar"),
    ]

    private enum Key {
        static let sources = "notchmate.notifications.sources"
        static let lastRecID = "notchmate.notifications.lastRecID"
    }

    @Published private(set) var isEnabled: Bool

    @Published var enabledBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(enabledBundleIDs), forKey: Key.sources)
        }
    }

    @Published private(set) var hasFullDiskAccess = false
    @Published private(set) var lastError: String?

    private var flagsCancellable: AnyCancellable?
    private var timer: Timer?
    private var lastRecID: Int
    private var queue: NookActivityQueue { NotchMateActivities.shared.queue }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = true
        if let stored = defaults.array(forKey: Key.sources) as? [String], !stored.isEmpty {
            enabledBundleIDs = Set(stored)
        } else {
            enabledBundleIDs = Set(Self.catalog.map(\.bundleID))
        }
        lastRecID = defaults.integer(forKey: Key.lastRecID)
    }

    func bind(flags: NotchMateFeatureFlags) {
        flagsCancellable = flags.$notificationToastsEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.isEnabled = enabled
                self?.refreshAccess()
                self?.setRunning(enabled)
            }
        isEnabled = flags.notificationToastsEnabled
        refreshAccess()
        setRunning(isEnabled)
    }

    func refreshAccess() {
        hasFullDiskAccess = FileManager.default.isReadableFile(atPath: Self.databasePath)
        lastError = hasFullDiskAccess ? nil : "Full Disk Access is required to read Notification Center."
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func preview() {
        queue.enqueue(
            NookActivity(
                coalescingKey: "notchmate.preview",
                priority: .normal,
                title: "Preview toast",
                subtitle: "This is how Slack or Mail will look.",
                systemImage: "bell",
                tint: .orange,
                dwell: .seconds(2.4)
            )
        )
    }

    private func setRunning(_ running: Bool) {
        timer?.invalidate()
        timer = nil
        guard running else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func poll() {
        refreshAccess()
        guard isEnabled, hasFullDiskAccess else { return }
        do {
            let rows = try NotchMateUsernotedStore.fetch(after: lastRecID)
            if lastRecID == 0 {
                lastRecID = NotchMateUsernotedStore.maxRecID()
                UserDefaults.standard.set(lastRecID, forKey: Key.lastRecID)
                return
            }
            for row in rows {
                lastRecID = max(lastRecID, row.recID)
                UserDefaults.standard.set(lastRecID, forKey: Key.lastRecID)
                guard enabledBundleIDs.contains(row.bundleID) else { continue }
                let source = Self.catalog.first { $0.bundleID == row.bundleID }
                queue.enqueue(
                    NookActivity(
                        coalescingKey: "nc.\(row.bundleID)",
                        priority: .high,
                        title: row.title.isEmpty ? (source?.title ?? row.bundleID) : row.title,
                        subtitle: row.subtitle.isEmpty ? row.body : row.subtitle,
                        systemImage: source?.systemImage ?? "bell",
                        tint: .orange,
                        dwell: .seconds(2.6)
                    )
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    static var databasePath: String {
        NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }
}

private struct NotchMateUsernotedRow {
    var recID: Int
    var bundleID: String
    var title: String
    var subtitle: String
    var body: String
}

private enum NotchMateUsernotedStore {
    static func fetch(after recID: Int) throws -> [NotchMateUsernotedRow] {
        try withCopiedDatabase { db in
            let sql = """
            SELECT r.rec_id, IFNULL(a.identifier, ''), r.data
            FROM record r
            LEFT JOIN app a ON r.app_id = a.app_id
            WHERE r.rec_id > ?
            ORDER BY r.rec_id ASC
            LIMIT 40;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw NSError(domain: "NotchMate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not query Notification Center."])
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, sqlite3_int64(recID))

            var rows: [NotchMateUsernotedRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int64(statement, 0))
                let bundle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let blob = sqlite3_column_blob(statement, 2)
                let bytes = Int(sqlite3_column_bytes(statement, 2))
                var title = ""
                var subtitle = ""
                var body = ""
                if let blob, bytes > 0 {
                    let data = Data(bytes: blob, count: bytes)
                    let parsed = parsePayload(data)
                    title = parsed.title
                    subtitle = parsed.subtitle
                    body = parsed.body
                }
                rows.append(NotchMateUsernotedRow(recID: id, bundleID: bundle, title: title, subtitle: subtitle, body: body))
            }
            return rows
        }
    }

    static func maxRecID() -> Int {
        (try? withCopiedDatabase { db -> Int in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(rec_id), 0) FROM record;", -1, &statement, nil) == SQLITE_OK, let statement else {
                return 0
            }
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                return Int(sqlite3_column_int64(statement, 0))
            }
            return 0
        }) ?? 0
    }

    private static func withCopiedDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let fm = FileManager.default
        let sourceDir = (NotchMateNotificationToasts.databasePath as NSString).deletingLastPathComponent
        let tempDir = fm.temporaryDirectory.appendingPathComponent("notchmate-nc-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        for name in ["db", "db-wal", "db-shm"] {
            let from = URL(fileURLWithPath: sourceDir).appendingPathComponent(name)
            let to = tempDir.appendingPathComponent(name)
            if fm.fileExists(atPath: from.path) {
                try fm.copyItem(at: from, to: to)
            }
        }

        let dbPath = tempDir.appendingPathComponent("db").path
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK, let db else {
            throw NSError(domain: "NotchMate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open Notification Center database."])
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private static func parsePayload(_ data: Data) -> (title: String, subtitle: String, body: String) {
        let object: Any?
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            object = plist
        } else {
            object = nil
        }
        let req = (object as? [String: Any])?["req"] as? [String: Any]
            ?? (object as? [String: Any])
        let title = string(req, "titl", "title")
        let subtitle = string(req, "subt", "subtitle")
        let body = string(req, "body")
        return (title, subtitle, body)
    }

    private static func string(_ dict: [String: Any]?, _ keys: String...) -> String {
        guard let dict else { return "" }
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return ""
    }
}
