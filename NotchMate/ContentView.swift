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
    var body: some View {
        NotchMateNowPlayingHome()
    }
}

#Preview {
    ContentView()
}
