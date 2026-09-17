//
//  NotchMateAgentViews.swift
//  NotchMate
//
//  Compact: circular per-tool icons. Expanded: short session list.
//

import NookApp
import SwiftUI

struct NotchMateAgentsHome: View {
    @ObservedObject private var agents = NotchMateAgents.shared
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
        HStack(spacing: 10) {
            NotchMateAgentGlyph(tool: session.tool, state: session.state, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.tool.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryLabel)
                Text("\(session.projectName) · \(session.state.title)")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.tool.title), \(session.projectName), \(session.state.title)")
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
                NotchMateAgentGlyph(tool: summary.tool, state: summary.state, size: size - 4)
                    .help("\(summary.tool.title) · \(summary.state.title)")
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
            Circle()
                .fill(fill)
            Circle()
                .strokeBorder(theme.primaryLabel.opacity(0.18), lineWidth: 0.8)
            Text(tool.monogram)
                .font(.system(size: max(8, size * 0.42), weight: .semibold, design: .rounded))
                .foregroundStyle(label)
        }
        .frame(width: size, height: size)
        .opacity(state == .idle || state == .done ? 0.72 : 1)
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

    private var fill: Color {
        switch state {
        case .approval:
            return Color.orange.opacity(0.92)
        case .running:
            return Color.accentColor.opacity(0.85)
        case .idle, .done:
            return theme.secondaryLabel.opacity(0.22)
        }
    }

    private var label: Color {
        switch state {
        case .approval, .running:
            return Color.white.opacity(0.95)
        case .idle, .done:
            return theme.primaryLabel.opacity(0.85)
        }
    }
}
