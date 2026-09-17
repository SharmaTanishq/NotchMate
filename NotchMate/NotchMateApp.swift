//
//  NotchMateApp.swift
//  NotchMate
//
//  Created by Tanishq Sharma on 9/17/26.
//

import Combine
import NookApp
import NookComponents
import SwiftUI

/// Host configuration for NotchMate. `main.swift` boots OpenNook with this.
enum NotchMateApp {
    /// One-shot: leftover `.solid` from NotchMate's previous seed is upgraded to
    /// Liquid Glass. After this flag is set, Settings → Surface (Solid / Translucent /
    /// Liquid Glass) is left alone.
    private static let liquidGlassSeedMigrationKey = "notchmate.migratedSeedSolidToLiquidGlass"

    private static var settingsRouteCancellable: AnyCancellable?

    @MainActor
    static func configuration() -> NookConfiguration {
        let layout = NotchMateLayoutSettings.shared
        var configuration = NookConfiguration()
        configuration.setHome {
            NookActivityHost(queue: NotchMateActivities.shared.queue) {
                ContentView()
            }
        }
        configuration.setCompactLeading { NotchMateCompactChrome(slot: .leading) }
        configuration.setCompactTrailing { NotchMateCompactChrome(slot: .trailing) }
        configuration.setSettings { NotchMateInNotchSettingsRedirect() }
        configuration.metrics = layout.chromeMetrics
        configuration.expandedWidth = layout.expandedWidth
        configuration.branding = NookHostBranding(
            hostName: "NotchMate",
            hostTagline: "A notch companion built on OpenNook."
        )
        configuration.topBar.leadingTitle = { _ in "NotchMate" }
        // First-run seed: fused-to-top notch chrome with OpenNook Liquid Glass.
        // UserDefaults wins after the user picks a surface or shape. Seed is never
        // written, so later default tweaks still apply to people who never saved prefs.
        configuration.preferenceDefaults = NookPreferenceDefaults(
            appearance: NookAppearancePreferences(
                chromePalette: .dark,
                surfaceStyle: .liquidGlass,
                presentation: .notch
            )
        )
        configuration.onReady = { coordinator in
            migrateAutoPresentationToNotch(appState: coordinator.appState)
            migrateSeedSolidToLiquidGlass(appState: coordinator.appState)
            NotchMateNowPlaying.shared.bind(flags: NotchMateFeatureFlags.shared)
            NotchMateAgents.shared.bind(flags: NotchMateFeatureFlags.shared)
            NotchMateUsage.shared.bind(flags: NotchMateFeatureFlags.shared)
            NotchMateNotificationToasts.shared.bind(flags: NotchMateFeatureFlags.shared)
            NotchMateActivities.shared.queue.bind(to: coordinator)
            routeOpenNookSettingsToWindow(coordinator: coordinator)
        }
        return configuration
    }

    /// Gear and menu-bar “Settings…” still call OpenNook `showSettings()`. Bounce
    /// immediately to the native window and keep the notch on home.
    @MainActor
    private static func routeOpenNookSettingsToWindow(coordinator: AppCoordinator) {
        settingsRouteCancellable = coordinator.appState.$viewMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { mode in
                guard mode == .settings else { return }
                NotchMateSettingsWindowController.shared.present(appState: coordinator.appState)
                coordinator.appState.showHome()
                coordinator.hideNook()
            }
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

    /// Prior NotchMate seed used `.solid`. Untouched / seed-only blobs still on `.solid`
    /// move to `.liquidGlass` once. `.translucent` and `.liquidGlass` are treated as an
    /// explicit Settings choice and are not rewritten.
    @MainActor
    static func migrateSeedSolidToLiquidGlass(appState: AppState) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: liquidGlassSeedMigrationKey) {
            return
        }

        let style = appState.appearancePreferences.surfaceStyle
        if style == .translucent || style == .liquidGlass {
            defaults.set(true, forKey: liquidGlassSeedMigrationKey)
            return
        }

        guard style == .solid else {
            defaults.set(true, forKey: liquidGlassSeedMigrationKey)
            return
        }

        var preferences = appState.appearancePreferences
        preferences.surfaceStyle = .liquidGlass
        appState.replaceAppearancePreferences(preferences)
        defaults.set(true, forKey: liquidGlassSeedMigrationKey)
    }
}

/// OpenNook still requires a Settings view for the gear. This never stays on screen.
struct NotchMateInNotchSettingsRedirect: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }
}
