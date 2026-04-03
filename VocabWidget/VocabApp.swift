// VocabApp.swift
// The entry point for your main iOS app target.
//
// LEARNING NOTE:
// @main marks the struct that starts the app. SwiftUI's App protocol
// requires a `body` property that returns one or more Scenes.
// WindowGroup is the standard scene for an iOS app — it manages
// the root window and handles things like multi-window on iPad.

import SwiftUI

@main
struct VocabApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
