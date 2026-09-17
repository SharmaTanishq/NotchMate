//
//  NotchMateFeatureFlags.swift
//  NotchMate
//

import Combine
import Foundation

@MainActor
final class NotchMateFeatureFlags: ObservableObject {
    static let shared = NotchMateFeatureFlags()

    private enum Key {
        static let nowPlaying = "notchmate.feature.nowPlaying"
        static let calendar = "notchmate.feature.calendar"
        static let agents = "notchmate.feature.agents"
        static let notificationToasts = "notchmate.feature.notificationToasts"
        static let usage = "notchmate.feature.usage"
    }

    @Published var nowPlayingEnabled: Bool {
        didSet { UserDefaults.standard.set(nowPlayingEnabled, forKey: Key.nowPlaying) }
    }

    @Published var calendarEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarEnabled, forKey: Key.calendar) }
    }

    @Published var agentsEnabled: Bool {
        didSet { UserDefaults.standard.set(agentsEnabled, forKey: Key.agents) }
    }

    @Published var notificationToastsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationToastsEnabled, forKey: Key.notificationToasts) }
    }

    @Published var usageEnabled: Bool {
        didSet { UserDefaults.standard.set(usageEnabled, forKey: Key.usage) }
    }

    private init() {
        let defaults = UserDefaults.standard
        nowPlayingEnabled = defaults.bool(forKey: Key.nowPlaying)
        calendarEnabled = defaults.bool(forKey: Key.calendar)
        agentsEnabled = defaults.bool(forKey: Key.agents)
        notificationToastsEnabled = Self.bool(defaults, Key.notificationToasts, fallback: true)
        usageEnabled = Self.bool(defaults, Key.usage, fallback: true)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
}
