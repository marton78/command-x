// FileBrowserView.swift
// Command X
//
// File browser UI for selecting files/folders to cut and paste.

import SwiftUI
import AppKit

struct FileBrowserView: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> NSOpenPanelViewController {
        return NSOpenPanelViewController()
    }
    
    func updateNSViewController(_ nsViewController: NSOpenPanelViewController, context: Context) {}
}

class NSOpenPanelViewController: NSViewController {
    override func loadView() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.prompt = "Select"
        openPanel.begin { _ in }
        self.view = NSView()
    }
}
