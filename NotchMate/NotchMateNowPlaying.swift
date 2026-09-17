//
//  NotchMateNowPlaying.swift
//  NotchMate
//
//  Now Playing is the macOS current item, not a streaming-account integration.
//
//  Source: ejbills/mediaremote-adapter (SPM). It bundles ungive's Perl helper
//  (`/usr/bin/perl` + MediaRemoteAdapter.framework). Apple's signed perl process
//  still has MediaRemote access after macOS 15.4; linking MediaRemote in this
//  app would return empty. The helper must NOT inherit App Sandbox — sandbox
//  is off for NotchMate. No extra MediaRemote entitlement exists.
//
//  Spotify/YouTube/Music: whatever Control Center shows. Spotify is the desktop
//  app via MediaRemote, never OAuth. Skip uses MediaRemote next/previous.
//

import AppKit
import Combine
import MediaRemoteAdapter
import SwiftUI

@MainActor
final class NotchMateNowPlaying: ObservableObject {
    static let shared = NotchMateNowPlaying()

    @Published private(set) var isEnabled = false
    @Published private(set) var item: NotchMateNowPlayingItem?
    @Published private(set) var listenerFailed = false

    private let controller = MediaController()
    private var flagsCancellable: AnyCancellable?
    private var isListening = false

    private init() {
        controller.onTrackInfoReceived = { [weak self] info in
            Task { @MainActor in
                self?.listenerFailed = false
                self?.item = NotchMateNowPlayingItem(track: info)
            }
        }
        controller.onListenerTerminated = { [weak self] in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                self.listenerFailed = true
            }
        }
    }

    func bind(flags: NotchMateFeatureFlags) {
        flagsCancellable = flags.$nowPlayingEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.setEnabled(enabled)
            }
        setEnabled(flags.nowPlayingEnabled)
    }

    var showsCompactArtwork: Bool {
        isEnabled && item != nil
    }

    func togglePlayPause() {
        controller.togglePlayPause()
    }

    func skipNext() {
        controller.nextTrack()
    }

    func skipPrevious() {
        controller.previousTrack()
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
            item = nil
            listenerFailed = false
        }
    }

    private func start() {
        guard !isListening else { return }
        isListening = true
        controller.startListening()
    }

    private func stop() {
        guard isListening else { return }
        isListening = false
        controller.stopListening()
    }
}

struct NotchMateNowPlayingItem: Equatable {
    let identity: String
    let title: String
    let artist: String
    let bundleIdentifier: String?
    let isPlaying: Bool
    let duration: TimeInterval?
    let elapsedAtUpdate: TimeInterval?
    let playbackRate: Double
    let updatedAt: Date
    let artwork: NSImage?

    var canSkip: Bool { true }

    var elapsedNow: TimeInterval? {
        guard let elapsedAtUpdate else { return nil }
        guard isPlaying else { return elapsedAtUpdate }
        let drifted = elapsedAtUpdate + Date().timeIntervalSince(updatedAt) * playbackRate
        if let duration {
            return min(max(drifted, 0), duration)
        }
        return max(drifted, 0)
    }

    init?(track: TrackInfo?) {
        guard let payload = track?.payload else { return nil }
        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        identity = payload.uniqueIdentifier
        self.title = title
        artist = payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        bundleIdentifier = payload.bundleIdentifier
        isPlaying = payload.isPlaying ?? ((payload.playbackRate ?? 0) > 0)
        if let micros = payload.durationMicros, micros > 0 {
            duration = micros / 1_000_000
        } else {
            duration = nil
        }
        elapsedAtUpdate = payload.currentElapsedTime
        playbackRate = payload.playbackRate ?? (isPlaying ? 1 : 0)
        updatedAt = Date()
        artwork = payload.artwork
    }

    static func == (lhs: NotchMateNowPlayingItem, rhs: NotchMateNowPlayingItem) -> Bool {
        lhs.identity == rhs.identity
            && lhs.isPlaying == rhs.isPlaying
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
    }
}
