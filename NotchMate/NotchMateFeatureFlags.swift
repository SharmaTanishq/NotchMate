//
//  NotchMateFeatureFlags.swift
//  NotchMate
//
//  Persisted product flags. Media/calendar/agent wiring is out of scope;
//  these toggles only remember intent for later slices.
//

import Combine
import Foundation

@MainActor
final class NotchMateFeatureFlags: ObservableObject {
    private enum Key {
        static let nowPlaying = "notchmate.feature.nowPlaying"
        static let calendar = "notchmate.feature.calendar"
        static let agents = "notchmate.feature.agents"
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

    init() {
        let defaults = UserDefaults.standard
        nowPlayingEnabled = defaults.bool(forKey: Key.nowPlaying)
        calendarEnabled = defaults.bool(forKey: Key.calendar)
        agentsEnabled = defaults.bool(forKey: Key.agents)
    }
}
