//
//  NotchMateApp.swift
//  NotchMate
//
//  Created by Tanishq Sharma on 9/17/26.
//

import NookApp
import SwiftUI

/// Host configuration for NotchMate. `main.swift` boots OpenNook with this.
enum NotchMateApp {
    @MainActor
    static func configuration() -> NookConfiguration {
        var configuration = NookConfiguration()
        configuration.setHome { ContentView() }
        configuration.branding = NookHostBranding(
            hostName: "NotchMate",
            hostTagline: "A notch companion built on OpenNook."
        )
        configuration.topBar.leadingTitle = { _ in "NotchMate" }
        // First-run seed: fused-to-top notch chrome (not Auto, which floats a pill on
        // displays OpenNook doesn't treat as notched). UserDefaults wins after the user
        // picks Pill vs Notch. Seed is never written, so later default tweaks still apply
        // to people who never opened Settings.
        configuration.preferenceDefaults = NookPreferenceDefaults(
            appearance: NookAppearancePreferences(
                chromePalette: .dark,
                surfaceStyle: .solid,
                presentation: .notch
            )
        )
        configuration.onReady = { coordinator in
            migrateAutoPresentationToNotch(appState: coordinator.appState)
        }
        return configuration
    }

    /// OpenNook's `.auto` becomes a floating island on many setups (external display,
    /// undetected notch). NotchMate's idle chrome should hug the top edge, so treat a
    /// leftover `.auto` as `.notch` and persist it through OpenNook's appearance store.
    @MainActor
    static func migrateAutoPresentationToNotch(appState: AppState) {
        guard appState.appearancePreferences.presentation == .auto else { return }
        var preferences = appState.appearancePreferences
        preferences.presentation = .notch
        appState.replaceAppearancePreferences(preferences)
    }
}
