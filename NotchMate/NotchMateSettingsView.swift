//
//  NotchMateSettingsView.swift
//  NotchMate
//
//  Sidebar settings: General, Appearance, Now Playing, Calendar, Agents.
//  Appearance writes OpenNook AppState so the notch updates live.
//

import AppKit
import NookApp
import SwiftUI

enum NotchMateSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case nowPlaying
    case calendar
    case agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .nowPlaying: return "Now Playing"
        case .calendar: return "Calendar"
        case .agents: return "Agents"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .nowPlaying: return "play.circle"
        case .calendar: return "calendar"
        case .agents: return "sparkles"
        }
    }
}

struct NotchMateSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var featureFlags: NotchMateFeatureFlags
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var section: NotchMateSettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(NotchMateSettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .navigationTitle("Settings")
        } detail: {
            Group {
                switch section ?? .general {
                case .general:
                    NotchMateGeneralSettingsPane()
                case .appearance:
                    NotchMateAppearanceSettingsPane()
                case .nowPlaying:
                    NotchMateComingSoonPane(
                        title: "Now Playing",
                        explanation: "Shows only the current item from macOS Now Playing. NotchMate never signs into Spotify or other streaming accounts.",
                        isOn: $featureFlags.nowPlayingEnabled
                    )
                case .calendar:
                    NotchMateComingSoonPane(
                        title: "Calendar",
                        explanation: "Upcoming events from the Mac Calendar app, shown in the notch when you opt in.",
                        isOn: $featureFlags.calendarEnabled
                    )
                case .agents:
                    NotchMateComingSoonPane(
                        title: "Agents",
                        explanation: "An assistant hub in the notch. Wiring and model hooks ship in a later slice.",
                        isOn: $featureFlags.agentsEnabled
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(settingsBackground)
            .navigationTitle((section ?? .general).title)
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var settingsBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

private struct NotchMateGeneralSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Stay expanded after hover", isOn: keepOpenBinding)
            } footer: {
                Text("When on, the notch stays open after the pointer leaves. You can also use the lock in the notch.")
            }

            Section {
                LabeledContent("Show / hide shortcut", value: appState.hotkey.display)
            } footer: {
                Text("Change this later from a dedicated shortcut editor. Default is ⌥⌘;.")
            }

            Section {
                Button("Quit NotchMate") {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var keepOpenBinding: Binding<Bool> {
        Binding(
            get: { appState.keepNookOpen },
            set: { appState.keepNookOpen = $0 }
        )
    }
}

private struct NotchMateAppearanceSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Shape", selection: shapeBinding) {
                    Text("Notch").tag(NookPresentation.notch)
                    Text("Pill").tag(NookPresentation.floating)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(shapeCaption)
            }

            Section {
                Picker("Surface", selection: surfaceBinding) {
                    Text("Solid").tag(NookSurfaceStyle.solid)
                    Text("Translucent").tag(NookSurfaceStyle.translucent)
                    Text("Liquid Glass").tag(NookSurfaceStyle.liquidGlass)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(surfaceCaption)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var shapeBinding: Binding<NookPresentation> {
        Binding(
            get: {
                switch appState.appearancePreferences.presentation {
                case .floating: return .floating
                case .notch, .auto: return .notch
                }
            },
            set: { next in
                var preferences = appState.appearancePreferences
                preferences.presentation = next
                appState.replaceAppearancePreferences(preferences)
            }
        )
    }

    private var surfaceBinding: Binding<NookSurfaceStyle> {
        Binding(
            get: { appState.appearancePreferences.surfaceStyle },
            set: { next in
                var preferences = appState.appearancePreferences
                preferences.surfaceStyle = next
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

    private var surfaceCaption: String {
        switch appState.appearancePreferences.surfaceStyle {
        case .solid:
            return "Opaque chrome that matches the hardware notch."
        case .translucent:
            return "Frosted material over the wallpaper."
        case .liquidGlass:
            return "macOS 26 uses real Liquid Glass; earlier versions use OpenNook’s approximation."
        }
    }
}

private struct NotchMateComingSoonPane: View {
    let title: String
    let explanation: String
    @Binding var isOn: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Enable \(title)", isOn: $isOn)
            } footer: {
                Text("Coming soon. The switch is saved so a later update can honor it. \(explanation)")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560, alignment: .leading)
    }
}

#Preview {
    NotchMateSettingsView()
        .environmentObject(AppState(preferenceDefaults: .default))
        .environmentObject(NotchMateFeatureFlags())
}
