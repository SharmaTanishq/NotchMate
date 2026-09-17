//
//  NotchMateLayoutSettings.swift
//  NotchMate
//
//  Compact placement and OpenNook layout knobs. Compact slot size and extra
//  width apply live in host compact views. Expanded width is applied at launch
//  via NookConfiguration.expandedWidth (OpenNook pins the panel there).
//

import Combine
import Foundation
import NookApp

enum NotchMateAgentPlacement: String, CaseIterable, Identifiable {
    case center
    case leading
    case trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center: return "Center"
        case .leading: return "Leading"
        case .trailing: return "Trailing"
        }
    }

    var caption: String {
        switch self {
        case .center:
            return "Icons hug both sides of the camera cutout. OpenNook has no true center slot."
        case .leading:
            return "All agent icons sit in the compact slot left of the notch."
        case .trailing:
            return "All agent icons sit in the compact slot right of the notch."
        }
    }
}

@MainActor
final class NotchMateLayoutSettings: ObservableObject {
    static let shared = NotchMateLayoutSettings()

    enum Key {
        static let placement = "notchmate.layout.agentPlacement"
        static let compactSlotSize = "notchmate.layout.compactSlotSize"
        static let compactExtraWidth = "notchmate.layout.compactExtraWidth"
        static let expandedWidth = "notchmate.layout.expandedWidth"
        static let edgePadding = "notchmate.layout.edgePadding"
    }

    static let defaultCompactSlotSize: Double = 24
    static let defaultCompactExtraWidth: Double = 0
    static let defaultExpandedWidth: Double = 520
    static let defaultEdgePadding: Double = 8

    @Published var agentPlacement: NotchMateAgentPlacement {
        didSet { UserDefaults.standard.set(agentPlacement.rawValue, forKey: Key.placement) }
    }

    @Published var compactSlotSize: Double {
        didSet { UserDefaults.standard.set(compactSlotSize, forKey: Key.compactSlotSize) }
    }

    @Published var compactExtraWidth: Double {
        didSet { UserDefaults.standard.set(compactExtraWidth, forKey: Key.compactExtraWidth) }
    }

    @Published var expandedWidth: Double {
        didSet { UserDefaults.standard.set(expandedWidth, forKey: Key.expandedWidth) }
    }

    @Published var edgePadding: Double {
        didSet { UserDefaults.standard.set(edgePadding, forKey: Key.edgePadding) }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Key.placement),
           let placement = NotchMateAgentPlacement(rawValue: raw) {
            agentPlacement = placement
        } else {
            agentPlacement = .center
        }
        compactSlotSize = Self.double(defaults, Key.compactSlotSize, Self.defaultCompactSlotSize)
        compactExtraWidth = Self.double(defaults, Key.compactExtraWidth, Self.defaultCompactExtraWidth)
        expandedWidth = Self.double(defaults, Key.expandedWidth, Self.defaultExpandedWidth)
        edgePadding = Self.double(defaults, Key.edgePadding, Self.defaultEdgePadding)
    }

    var chromeMetrics: NookChromeMetrics {
        var metrics = NookChromeMetrics.default
        metrics.compactSlotSize = compactSlotSize
        metrics.edgePadding = edgePadding
        return metrics
    }

    private static func double(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        if defaults.object(forKey: key) == nil {
            return fallback
        }
        return defaults.double(forKey: key)
    }
}
