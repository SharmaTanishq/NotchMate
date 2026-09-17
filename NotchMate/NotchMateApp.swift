//
//  NotchMateApp.swift
//  NotchMate
//
//  Created by Tanishq Sharma on 9/17/26.
//

import NookApp
import SwiftUI

/// Host configuration for NotchMate. `main.swift` boots OpenNook with this.
enum NotchMateApp {
    @MainActor
    static func configuration() -> NookConfiguration {
        var configuration = NookConfiguration()
        configuration.setHome { ContentView() }
        configuration.branding = NookHostBranding(
            hostName: "NotchMate",
            hostTagline: "A notch companion built on OpenNook."
        )
        configuration.topBar.leadingTitle = { _ in "NotchMate" }
        return configuration
    }
}
