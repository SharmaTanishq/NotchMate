//
//  ContentView.swift
//  NotchMate
//
//  Created by Tanishq Sharma on 9/17/26.
//

import NookApp
import SwiftUI

/// Expanded notch home surface. Hover the menu-bar notch or press ⌥⌘; to show it.
struct ContentView: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "menubar.dock.rectangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.secondaryLabel)
            Text("NotchMate")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.primaryLabel)
            Text("Hover the notch or press ⌥⌘;")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryLabel)
            Text("Open Settings from the gear or the menu bar extra.")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

#Preview {
    ContentView()
}
