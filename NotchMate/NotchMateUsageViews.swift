//
//  NotchMateUsageViews.swift
//  NotchMate
//
//  One-row usage chips. Details stay in Settings and on tap.
//

import NookApp
import SwiftUI

struct NotchMateUsageHome: View {
    @ObservedObject private var usage = NotchMateUsage.shared
    @Environment(\.nookResolvedTheme) private var theme
    @State private var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if usage.tools.isEmpty {
                    Text("Usage")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                    Spacer(minLength: 0)
                    Text("Reading…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.tertiaryLabel)
                } else {
                    ForEach(usage.tools) { item in
                        NotchMateUsageChip(
                            item: item,
                            isSelected: selectedID == item.id
                        ) {
                            selectedID = selectedID == item.id ? nil : item.id
                        }
                    }
                }
            }

            if let selected = usage.tools.first(where: { $0.id == selectedID }) {
                Text(selected.today.caption)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(1)
                    .help(selected.honesty)
                    .transition(.opacity)
            }

            if let lastError = usage.lastError {
                Text(lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Usage today")
    }
}

private struct NotchMateUsageChip: View {
    let item: NotchMateToolUsage
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                NotchMateAgentGlyph(tool: item.tool, state: .idle, size: 14)
                Text(item.today.headline)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryLabel)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                theme.primaryLabel.opacity(isSelected ? 0.14 : 0.06),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help("\(item.tool.title): \(item.today.caption). \(item.honesty)")
        .accessibilityLabel("\(item.tool.title) \(item.today.headline) \(item.today.headlineUnit)")
        .accessibilityHint(item.honesty)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
