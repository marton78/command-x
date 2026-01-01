// CommandXApp.swift
// Command X
//
// Main entry point for the Command X macOS app.

import SwiftUI

@main
struct CommandXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Pure menu bar app - no scenes needed, everything handled by AppDelegate
    }
}
