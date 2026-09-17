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
                self?.applyTrackInfo(info)
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
        // Explicit play/pause from the last MediaRemote snapshot. Toggle on a
        // stale icon sends the opposite command of what the user sees.
        if var item {
            let shouldPlay = !item.isPlaying
            item.setPlaying(shouldPlay)
            self.item = item
            if shouldPlay {
                controller.play()
            } else {
                controller.pause()
            }
        } else {
            controller.togglePlayPause()
        }
    }

    func skipNext() {
        controller.nextTrack()
    }

    func skipPrevious() {
        controller.previousTrack()
    }

    private func applyTrackInfo(_ info: TrackInfo?) {
        listenerFailed = false
        guard let payload = info?.payload else {
            item = nil
            return
        }

        if var existing = item, existing.canApplyPlayback(from: payload) {
            existing.applyPlayback(from: payload)
            item = existing
            return
        }

        item = NotchMateNowPlayingItem(track: info)
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
    var identity: String
    var title: String
    var artist: String
    var bundleIdentifier: String?
    var isPlaying: Bool
    var duration: TimeInterval?
    var elapsedAtUpdate: TimeInterval?
    var playbackRate: Double
    var updatedAt: Date
    var artwork: NSImage?

    var elapsedNow: TimeInterval? {
        guard let elapsedAtUpdate else { return nil }
        guard isPlaying, playbackRate > 0 else { return elapsedAtUpdate }
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
        isPlaying = Self.playingState(from: payload, previous: nil)
        duration = Self.duration(from: payload)
        elapsedAtUpdate = payload.currentElapsedTime
        playbackRate = Self.rate(from: payload, isPlaying: isPlaying)
        updatedAt = Date()
        artwork = payload.artwork
    }

    func canApplyPlayback(from payload: TrackInfo.Payload) -> Bool {
        let incomingTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if incomingTitle.isEmpty {
            return true
        }
        return incomingTitle == title
            || payload.uniqueIdentifier == identity
            || (
                payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines) == artist
                    && incomingTitle == title
            )
    }

    mutating func applyPlayback(from payload: TrackInfo.Payload) {
        let incomingTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !incomingTitle.isEmpty {
            title = incomingTitle
            identity = payload.uniqueIdentifier
        }
        if let artist = payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            self.artist = artist
        }
        if let bundleIdentifier = payload.bundleIdentifier {
            self.bundleIdentifier = bundleIdentifier
        }
        isPlaying = Self.playingState(from: payload, previous: isPlaying)
        if let duration = Self.duration(from: payload) {
            self.duration = duration
        }
        if let elapsed = payload.currentElapsedTime {
            elapsedAtUpdate = elapsed
        } else if !isPlaying, let elapsedAtUpdate {
            self.elapsedAtUpdate = elapsedAtUpdate
        }
        playbackRate = Self.rate(from: payload, isPlaying: isPlaying)
        updatedAt = Date()
        if let artwork = payload.artwork {
            self.artwork = artwork
        }
    }

    mutating func setPlaying(_ playing: Bool) {
        isPlaying = playing
        playbackRate = playing ? max(playbackRate, 1) : 0
        if let elapsed = elapsedNow {
            elapsedAtUpdate = elapsed
        }
        updatedAt = Date()
    }

    /// `playbackRate` is the transport for the current item; `isPlaying` is often
    /// "does this app still own Now Playing" and can stay true after a pause.
    private static func playingState(from payload: TrackInfo.Payload, previous: Bool?) -> Bool {
        if let rate = payload.playbackRate {
            return rate > 0.01
        }
        if let playing = payload.isPlaying {
            return playing
        }
        return previous ?? false
    }

    private static func rate(from payload: TrackInfo.Payload, isPlaying: Bool) -> Double {
        if let rate = payload.playbackRate {
            return rate
        }
        return isPlaying ? 1 : 0
    }

    private static func duration(from payload: TrackInfo.Payload) -> TimeInterval? {
        guard let micros = payload.durationMicros, micros > 0 else { return nil }
        return micros / 1_000_000
    }

    static func == (lhs: NotchMateNowPlayingItem, rhs: NotchMateNowPlayingItem) -> Bool {
        lhs.identity == rhs.identity
            && lhs.isPlaying == rhs.isPlaying
            && lhs.playbackRate == rhs.playbackRate
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.elapsedAtUpdate == rhs.elapsedAtUpdate
    }
}
