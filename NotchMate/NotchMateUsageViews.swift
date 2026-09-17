//
//  NotchMateUsageViews.swift
//  NotchMate
//
//  Expanded usage strip: Claude, Codex, Cursor today totals, NotchBuddy-style.
//

import NookApp
import SwiftUI

struct NotchMateUsageHome: View {
    @ObservedObject private var usage = NotchMateUsage.shared
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Usage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                Spacer()
                Text("Today")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.tertiaryLabel)
            }

            if usage.tools.isEmpty {
                Text("Reading local Claude, Codex, and Cursor logs…")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryLabel)
            } else {
                HStack(spacing: 6) {
                    ForEach(usage.tools) { tool in
                        NotchMateUsageCard(item: tool)
                    }
                }
            }

            if let lastError = usage.lastError {
                Text(lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotchMateUsageCard: View {
    let item: NotchMateToolUsage
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NotchMateAgentGlyph(tool: item.tool, state: .idle, size: 16)
                Text(item.tool.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(1)
            }
            Text(item.today.headline)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.primaryLabel)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(item.today.headlineUnit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.tertiaryLabel)
                .lineLimit(1)
            Text(item.today.caption)
                .font(.system(size: 9))
                .foregroundStyle(theme.secondaryLabel)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.primaryLabel.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(item.honesty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.tool.title) \(item.today.headline) \(item.today.headlineUnit). \(item.today.caption)")
        .accessibilityHint(item.honesty)
    }
}
