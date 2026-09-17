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
    @EnvironmentObject private var layout: NotchMateLayoutSettings
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
                        explanation: "Shows the current macOS Now Playing item (Music, Spotify app, YouTube in a browser, and anything else Control Center can see). NotchMate never signs into Spotify. Skip uses system next/previous when the player allows it.",
                        isOn: $featureFlags.nowPlayingEnabled,
                        comingSoon: false
                    )
                case .calendar:
                    NotchMateComingSoonPane(
                        title: "Calendar",
                        explanation: "Upcoming events from the Mac Calendar app, shown in the notch when you opt in.",
                        isOn: $featureFlags.calendarEnabled,
                        comingSoon: true
                    )
                case .agents:
                    NotchMateAgentsSettingsPane()
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
    @EnvironmentObject private var layout: NotchMateLayoutSettings

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

            Section {
                Picker("Agent icons", selection: $layout.agentPlacement) {
                    ForEach(NotchMateAgentPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(layout.agentPlacement.caption)
            }

            Section {
                slider(
                    "Compact slot size",
                    value: $layout.compactSlotSize,
                    range: 18...36,
                    step: 1
                )
                slider(
                    "Compact extra width",
                    value: $layout.compactExtraWidth,
                    range: 0...80,
                    step: 2
                )
                slider(
                    "Expanded width",
                    value: $layout.expandedWidth,
                    range: 420...720,
                    step: 10
                )
                slider(
                    "Edge padding",
                    value: $layout.edgePadding,
                    range: 4...20,
                    step: 1
                )
            } footer: {
                Text("Slot size and extra width change the collapsed island immediately. Expanded width and OpenNook edge padding are applied when NotchMate launches, because OpenNook pins those on NookConfiguration.")
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

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

private struct NotchMateAgentsSettingsPane: View {
    @EnvironmentObject private var featureFlags: NotchMateFeatureFlags
    @ObservedObject private var agents = NotchMateAgents.shared
    @State private var lastResult: NotchMateHookInstallResult?
    @State private var lastError: String?
    @State private var isBusy = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Agents", isOn: $featureFlags.agentsEnabled)
            } footer: {
                Text("When on, the collapsed notch shows circular icons for Claude Code, Codex, Cursor, and Pi sessions that have reported in. The expanded notch lists tool, project, and state.")
            }

            Section {
                LabeledContent("Status folder") {
                    Text(agents.statusFolder.path)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("Install hooks…") {
                    confirmInstall()
                }
                .disabled(isBusy)
                Button("Remove NotchMate hooks") {
                    runUninstall()
                }
                .disabled(isBusy)
            } footer: {
                Text("Install copies a Python reporter into Application Support, then merges NotchMate commands into ~/.claude/settings.json, ~/.cursor/hooks.json, and ~/.codex/hooks.json, and writes ~/.pi/agent/extensions/notchmate-status.ts. Existing hooks stay. NotchMate never edits those files unless you click Install.")
            }

            SwiftUI.Section {
                LabeledContent("Claude Code") {
                    Text("Running, idle, done, approval")
                }
                LabeledContent("Codex") {
                    Text("Running, idle, done, approval")
                }
                LabeledContent("Cursor") {
                    Text("Running, idle, done — no approval bounce")
                }
                LabeledContent("Pi") {
                    Text("Running, idle, done — no approval bounce")
                }
            } header: {
                Text("What each tool can signal")
            } footer: {
                Text("Icons jump only when a tool actually fires a permission-request hook. Cursor and Pi have no such event, so they stay quiet.")
            }

            if let lastResult {
                SwiftUI.Section {
                    Text(lastResult.claude)
                    Text(lastResult.cursor)
                    Text(lastResult.codex)
                    Text(lastResult.pi)
                    ForEach(lastResult.notes, id: \.self) { note in
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Last install")
                }
            }

            if let lastError {
                Section {
                    Text(lastError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func confirmInstall() {
        let alert = NSAlert()
        alert.messageText = "Install agent hooks?"
        alert.informativeText = "NotchMate will merge status commands into your Claude, Cursor, and Codex hook files and add a Pi extension. It will not replace those files. You can remove the NotchMate entries later from this pane."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isBusy = true
        lastError = nil
        do {
            lastResult = try NotchMateAgentHookInstaller.install()
            if !featureFlags.agentsEnabled {
                featureFlags.agentsEnabled = true
            }
            agents.reload()
        } catch {
            lastError = error.localizedDescription
        }
        isBusy = false
    }

    private func runUninstall() {
        isBusy = true
        lastError = nil
        do {
            lastResult = try NotchMateAgentHookInstaller.uninstall()
        } catch {
            lastError = error.localizedDescription
        }
        isBusy = false
    }
}

private struct NotchMateComingSoonPane: View {
    let title: String
    let explanation: String
    @Binding var isOn: Bool
    var comingSoon: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable \(title)", isOn: $isOn)
            } footer: {
                if comingSoon {
                    Text("Coming soon. The switch is saved so a later update can honor it. \(explanation)")
                } else {
                    Text(explanation)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560, alignment: .leading)
    }
}

#Preview {
    NotchMateSettingsView()
        .environmentObject(AppState(preferenceDefaults: .default))
        .environmentObject(NotchMateFeatureFlags.shared)
        .environmentObject(NotchMateLayoutSettings.shared)
}
