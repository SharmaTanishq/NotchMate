//
//  NotchMateAgentViews.swift
//  NotchMate
//
//  Compact: circular per-tool icons. Expanded: short session list.
//

import AppKit
import NookApp
import SwiftUI

struct NotchMateAgentsHome: View {
    @ObservedObject private var agents = NotchMateAgents.shared
    @ObservedObject private var usage = NotchMateUsage.shared
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                Spacer()
                Text(agents.isEnabled ? "Watching" : "Off")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.tertiaryLabel)
            }

            if !agents.isEnabled {
                empty(
                    title: "Agents are off",
                    detail: "Turn them on in Settings, then install hooks so Claude Code, Codex, Cursor, and Pi can report in."
                )
            } else if agents.visibleSessions.isEmpty {
                empty(
                    title: "No agent sessions",
                    detail: "Install hooks from Settings → Agents. Status files land in Application Support/NotchMate/agent-status."
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(agents.visibleSessions.prefix(8)) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionRow(_ session: NotchMateAgentSession) -> some View {
        Button {
            NotchMateAgentFocus.reveal(session)
        } label: {
            HStack(spacing: 10) {
                NotchMateAgentGlyph(tool: session.tool, state: session.state, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.tool.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.primaryLabel)
                    Text(sessionDetail(session))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(session.tool.title)")
        .accessibilityLabel("\(session.tool.title), \(sessionDetail(session))")
        .accessibilityHint("Opens \(session.tool.title)")
    }

    private func sessionDetail(_ session: NotchMateAgentSession) -> String {
        var parts = [session.projectName, session.state.title]
        if usage.isEnabled {
            if let live = usage.liveStats(for: session), live.billedTokens > 0 {
                parts.append("\(NotchMateUsageTotals.compact(live.billedTokens)) tok")
                parts.append("\(live.turns) turns")
            } else if session.tool == .cursor {
                if let extra = usage.tools.first(where: { $0.tool == .cursor })?.today.extraValue {
                    parts.append("\(extra) AI lines today")
                } else {
                    parts.append("no local tokens")
                }
            }
        }
        return parts.joined(separator: " · ")
    }

    private func empty(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryLabel)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

struct NotchMateCompactChrome: View {
    enum Slot {
        case leading
        case trailing
    }

    let slot: Slot

    @ObservedObject private var nowPlaying = NotchMateNowPlaying.shared
    @ObservedObject private var agents = NotchMateAgents.shared
    @ObservedObject private var layout = NotchMateLayoutSettings.shared
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if slot == .leading, showsNowPlaying, !nowPlayingIsTrailingOnly {
                NotchMateCompactNowPlaying()
            }
            if showsAgents {
                NotchMateAgentIconCluster(summaries: agentsForSlot, size: layout.compactSlotSize)
            }
            if slot == .trailing, showsNowPlaying, nowPlayingIsTrailingOnly {
                NotchMateCompactNowPlaying()
            }
            if !showsAgents && !showsNowPlaying {
                placeholder
            }
        }
        .padding(.horizontal, layout.compactExtraWidth / 2)
        .frame(minWidth: layout.compactSlotSize, minHeight: layout.compactSlotSize)
        .animation(.snappy(duration: 0.22), value: agents.compactSummaries.map(\.id))
        .animation(.snappy(duration: 0.22), value: layout.agentPlacement)
        .animation(.snappy(duration: 0.22), value: layout.compactSlotSize)
        .animation(.snappy(duration: 0.22), value: layout.compactExtraWidth)
    }

    private var showsNowPlaying: Bool {
        nowPlaying.showsCompactArtwork
    }

    private var nowPlayingIsTrailingOnly: Bool {
        layout.agentPlacement == .leading && !agents.compactSummaries.isEmpty
    }

    private var showsAgents: Bool {
        !agentsForSlot.isEmpty
    }

    private var agentsForSlot: [NotchMateAgentToolSummary] {
        let all = agents.compactSummaries
        guard !all.isEmpty else { return [] }
        switch layout.agentPlacement {
        case .leading:
            return slot == .leading ? all : []
        case .trailing:
            return slot == .trailing ? all : []
        case .center:
            if all.count == 1 {
                return all
            }
            let split = Int(ceil(Double(all.count) / 2))
            if slot == .leading {
                return Array(all.prefix(split))
            }
            return Array(all.dropFirst(split))
        }
    }

    private var placeholder: some View {
        Group {
            if slot == .leading {
                Image(systemName: "house")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryLabel.opacity(0.85))
            } else {
                Circle()
                    .stroke(theme.primaryLabel.opacity(0.22), lineWidth: 1.1)
                    .frame(width: 11, height: 11)
            }
        }
        .frame(width: layout.compactSlotSize, height: layout.compactSlotSize)
    }
}

struct NotchMateAgentIconCluster: View {
    let summaries: [NotchMateAgentToolSummary]
    let size: CGFloat

    var body: some View {
        HStack(spacing: max(2, size * 0.08)) {
            ForEach(summaries) { summary in
                Button {
                    NotchMateAgentFocus.reveal(summary)
                } label: {
                    NotchMateAgentGlyph(tool: summary.tool, state: summary.state, size: size - 4)
                }
                .buttonStyle(.plain)
                .help("Open \(summary.tool.title)")
                .accessibilityHint("Opens \(summary.tool.title)")
            }
        }
    }
}

struct NotchMateAgentGlyph: View {
    let tool: NotchMateAgentTool
    let state: NotchMateAgentState
    let size: CGFloat

    @Environment(\.nookResolvedTheme) private var theme
    @State private var bounce = false

    var body: some View {
        ZStack {
            logo
                .frame(width: size, height: size)
                .clipShape(Circle())
            Circle()
                .strokeBorder(ring, lineWidth: state == .approval ? 1.6 : 0.8)
        }
        .frame(width: size, height: size)
        .opacity(state == .idle || state == .done ? 0.7 : 1)
        .offset(y: bounce && state == .approval ? -3 : 0)
        .accessibilityLabel("\(tool.title), \(state.title)")
        .onChange(of: state) { _, newState in
            bounce = newState == .approval
        }
        .onAppear {
            bounce = state == .approval
        }
        .animation(
            state == .approval
                ? .easeInOut(duration: 0.32).repeatForever(autoreverses: true)
                : .snappy(duration: 0.2),
            value: bounce
        )
    }

    @ViewBuilder
    private var logo: some View {
        if let image = NotchMateAgentArtwork.image(for: tool) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            ZStack {
                Circle().fill(theme.secondaryLabel.opacity(0.22))
                Image(systemName: tool.fallbackSymbol)
                    .font(.system(size: max(9, size * 0.42), weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
            }
        }
    }

    private var ring: Color {
        switch state {
        case .approval:
            return Color.orange.opacity(0.95)
        case .running:
            return theme.primaryLabel.opacity(0.22)
        case .idle, .done:
            return theme.primaryLabel.opacity(0.12)
        }
    }
}
