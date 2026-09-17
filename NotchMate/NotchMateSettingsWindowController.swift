//
//  NotchMateSettingsWindowController.swift
//  NotchMate
//
//  Native titled Settings window (sidebar + detail). Accessory notch apps
//  briefly become regular so the window can key; they return to accessory on close.
//

import AppKit
import NookApp
import SwiftUI

@MainActor
final class NotchMateSettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = NotchMateSettingsWindowController()

    private var window: NSWindow?
    private var previousActivationPolicy: NSApplication.ActivationPolicy = .accessory
    private let featureFlags = NotchMateFeatureFlags()

    func present(appState: AppState) {
        if let window {
            bindContent(appState: appState, in: window)
            orderFront(window, center: false)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchMate Settings"
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("notchmate.settings")
        window.titlebarSeparatorStyle = .line
        window.toolbarStyle = .unified
        bindContent(appState: appState, in: window)
        self.window = window
        orderFront(window, center: true)
    }

    func windowWillClose(_ notification: Notification) {
        restoreAccessoryPolicyIfNeeded()
    }

    private func bindContent(appState: AppState, in window: NSWindow) {
        let root = NotchMateSettingsView()
            .environmentObject(appState)
            .environmentObject(featureFlags)
        window.contentView = NSHostingView(rootView: root)
    }

    private func orderFront(_ window: NSWindow, center: Bool) {
        previousActivationPolicy = NSApp.activationPolicy()
        if previousActivationPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        if center {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func restoreAccessoryPolicyIfNeeded() {
        guard previousActivationPolicy == .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
