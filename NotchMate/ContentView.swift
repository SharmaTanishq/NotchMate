//
//  ContentView.swift
//  NotchMate
//
//  Created by Tanishq Sharma on 9/17/26.
//

import NookApp
import SwiftUI

/// Expanded notch home surface. Hover the menu-bar notch or press ⌥⌘; to show it.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(theme.secondaryLabel)
                Text("NotchMate")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.primaryLabel)
                Text("Hover the notch or press ⌥⌘;")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryLabel)
            }

            NotchMateShapePicker()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// Maps OpenNook's presentation API onto the two shapes NotchMate ships:
/// **Notch** (fused to the top edge) and **Pill** (capsule island).
struct NotchMateShapePicker: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shape")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)

            Picker("Shape", selection: shapeBinding) {
                Text("Notch").tag(NookPresentation.notch)
                Text("Pill").tag(NookPresentation.floating)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Shape")

            Text(shapeCaption)
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
    }

    private var shapeBinding: Binding<NookPresentation> {
        Binding(
            get: {
                switch appState.appearancePreferences.presentation {
                case .floating:
                    return .floating
                case .notch, .auto:
                    return .notch
                }
            },
            set: { next in
                var preferences = appState.appearancePreferences
                preferences.presentation = next
                appState.replaceAppearancePreferences(preferences)
            }
        )
    }

    private var shapeCaption: String {
        switch appState.appearancePreferences.presentation {
        case .floating:
            return "Pill is a rounded island just under the menu bar."
        case .notch, .auto:
            return "Notch hugs the top edge like the laptop camera housing."
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState(preferenceDefaults: .default))
}
