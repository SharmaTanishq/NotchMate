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
    @ObservedObject private var layout = NotchMateLayoutSettings.shared
    @ObservedObject private var usage = NotchMateUsage.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchMateNowPlayingHome()
            if usage.isEnabled {
                NotchMateUsageHome()
            }
            NotchMateAgentsHome()
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, max(0, layout.edgePadding - 8))
    }
}

#Preview {
    ContentView()
}
