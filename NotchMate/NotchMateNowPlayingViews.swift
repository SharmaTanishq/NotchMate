//
//  NotchMateNowPlayingViews.swift
//  NotchMate
//

import NookApp
import SwiftUI

struct NotchMateNowPlayingHome: View {
    @ObservedObject private var nowPlaying = NotchMateNowPlaying.shared
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Group {
            if !nowPlaying.isEnabled {
                NotchMateNowPlayingEmpty(
                    title: "Now Playing is off",
                    detail: "Turn it on in Settings to show the current macOS track."
                )
            } else if nowPlaying.listenerFailed, nowPlaying.item == nil {
                NotchMateNowPlayingEmpty(
                    title: "Can’t read Now Playing",
                    detail: "The MediaRemote helper stopped. Try toggling Now Playing off and on."
                )
            } else if nowPlaying.item != nil {
                NotchMateNowPlayingCard()
                    .id(nowPlaying.item?.identity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                NotchMateNowPlayingEmpty(
                    title: "Nothing playing",
                    detail: "Start something in Music, Spotify, YouTube, or any player Control Center can see."
                )
            }
        }
        .animation(.snappy(duration: 0.28), value: nowPlaying.item?.identity)
        .animation(.snappy(duration: 0.18), value: nowPlaying.item?.isPlaying)
    }
}

private struct NotchMateNowPlayingEmpty: View {
    @Environment(\.nookResolvedTheme) private var theme
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.secondaryLabel)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.primaryLabel)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct NotchMateNowPlayingCard: View {
    @ObservedObject private var nowPlaying = NotchMateNowPlaying.shared
    @Environment(\.nookResolvedTheme) private var theme

    private var item: NotchMateNowPlayingItem? { nowPlaying.item }

    var body: some View {
        if let item {
            HStack(alignment: .center, spacing: 14) {
                artwork(item)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryLabel)
                        .lineLimit(1)
                    if !item.artist.isEmpty {
                        Text(item.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryLabel)
                            .lineLimit(1)
                    }
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        progress(item)
                    }
                    controls(item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }

    private func artwork(_ item: NotchMateNowPlayingItem) -> some View {
        Group {
            if let image = item.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    theme.secondaryLabel.opacity(0.12)
                    Image(systemName: item.isPlaying ? "music.note" : "pause.fill")
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func progress(_ item: NotchMateNowPlayingItem) -> some View {
        if let duration = item.duration, duration > 0, let elapsed = item.elapsedNow {
            let fraction = min(max(elapsed / duration, 0), 1)
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.secondaryLabel.opacity(0.18))
                        Capsule()
                            .fill(theme.primaryLabel.opacity(0.85))
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text(Self.format(duration))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.tertiaryLabel)
            }
        }
    }

    private func controls(_ item: NotchMateNowPlayingItem) -> some View {
        HStack(spacing: 18) {
            Button(action: nowPlaying.skipPrevious) {
                Image(systemName: "backward.fill")
            }
            .help("Previous")
            Button(action: nowPlaying.togglePlayPause) {
                Image(systemName: item.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .help(item.isPlaying ? "Pause" : "Play")
            Button(action: nowPlaying.skipNext) {
                Image(systemName: "forward.fill")
            }
            .help("Next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primaryLabel)
        .font(.system(size: 12, weight: .semibold))
        .padding(.top, 2)
    }

    private static func format(_ time: TimeInterval) -> String {
        let total = Int(time.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct NotchMateCompactNowPlaying: View {
    @ObservedObject private var nowPlaying = NotchMateNowPlaying.shared
    @ObservedObject private var layout = NotchMateLayoutSettings.shared
    @Environment(\.nookResolvedTheme) private var theme

    private var slot: CGFloat { layout.compactSlotSize }

    var body: some View {
        Group {
            if nowPlaying.showsCompactArtwork, let item = nowPlaying.item {
                compactArtwork(item)
            } else {
                Image(systemName: "house")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryLabel.opacity(0.85))
            }
        }
        .frame(width: slot, height: slot)
        .animation(.snappy(duration: 0.22), value: nowPlaying.item?.identity)
        .animation(.snappy(duration: 0.18), value: nowPlaying.item?.isPlaying)
    }

    private func compactArtwork(_ item: NotchMateNowPlayingItem) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = item.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: slot - 4, height: slot - 4)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.secondaryLabel.opacity(0.18))
                    .frame(width: slot - 4, height: slot - 4)
            }
            Image(systemName: item.isPlaying ? "play.fill" : "pause.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(theme.primaryLabel)
                .padding(2)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
