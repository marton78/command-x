// AppDelegate.swift
// Command X
//
// Handles app lifecycle and global shortcut registration.

import Cocoa
import UserNotifications
import SwiftUI
import os

private let logger = Logger(subsystem: "enablestartup.CommandX", category: "main")

// MARK: - Timing / retry constants

/// Number of times to retry launching Finder before giving up.
private let finderLaunchRetryAttempts = 20
/// Seconds to wait between Finder-launch retry attempts.
private let finderLaunchRetryDelay: TimeInterval = 0.5

/// Number of times to retry the AppleScript selection query while Finder is still starting.
private let finderSelectionPollAttempts = 10
/// Seconds to wait between Finder-selection poll attempts.
private let finderSelectionPollDelay: TimeInterval = 0.75

/// Number of times to retry launching System Events before giving up.
private let systemEventsLaunchRetryAttempts = 10
/// Seconds to wait between System Events launch retry attempts.
private let systemEventsLaunchRetryDelay: TimeInterval = 0.5

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var finderRunning = false
    var finderIsFrontmost = false
    var workspaceNotificationCenter: NotificationCenter?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register default values so bool(forKey:) returns the correct fallback
        // without needing nil-coalescing at every read site.
        UserDefaults.standard.register(defaults: ["cutSoundEnabled": true])

        // Check if this is first launch
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            // Request permissions on first launch
            requestInitialPermissions()
            // Launch at Login defaults to off; the user can enable it from Settings.
        }
        
        // Check accessibility permission status
        checkAccessibilityPermission()
        
        // Set up menu bar icon and popover (initially hidden)
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // Use scissors icon from SF Symbols
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Command X")
            } else {
                // Fallback for older macOS versions
                button.image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        popover = NSPopover()
        popover?.contentViewController = NSHostingController(rootView: ContentView())
        popover?.behavior = .transient
        
        // Set up Finder monitoring
        setupFinderMonitoring()
        
        // Check initial Finder status
        updateFinderStatus()
        
        // Delay launch at login setup to avoid issues during app launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let shouldLaunch = UserDefaults.standard.bool(forKey: "launchAtLogin")
            LaunchAtLoginManager.shared.isEnabled = shouldLaunch
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterHotKeys()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc func togglePopover(_ sender: Any?) {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(sender)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func handleCut() {
        // Hotkey triggered
        logger.debug("handleCut: Command+X pressed")
        
        // Double-check that Finder is running and frontmost (should already be true since hotkeys are only registered then)
        let finderRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.finder" }
        let frontApp = NSWorkspace.shared.frontmostApplication
        let isFinderFrontmost = frontApp?.bundleIdentifier == "com.apple.finder"
        
        if !finderRunning || !isFinderFrontmost {
            logger.debug("Finder not active, ignoring cut command")
            return
        }
        
        // Play sound if enabled
        let soundEnabled = UserDefaults.standard.bool(forKey: "cutSoundEnabled")
        if soundEnabled {
            NSSound(named: NSSound.Name("Funk"))?.play()
        }
        tryGetFinderSelectionAndCut(retryCount: 0)
    }

    private func ensureFinderIsRunningAndCut(retryCount: Int) {
        let finderRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.finder" }
        if finderRunning {
            tryGetFinderSelectionAndCut(retryCount: 0)
            return
        }
        // Try to launch Finder if not running
        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: finderURL, configuration: config, completionHandler: nil)
        }
        // Wait and retry up to finderLaunchRetryAttempts times
        if retryCount < finderLaunchRetryAttempts {
            NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: "Waiting for Finder to launch... (\(retryCount+1)/\(finderLaunchRetryAttempts))")
            DispatchQueue.main.asyncAfter(deadline: .now() + finderLaunchRetryDelay) {
                self.ensureFinderIsRunningAndCut(retryCount: retryCount + 1)
            }
        } else {
            let msg = "Finder did not launch in time. Please open Finder and try again."
            NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
            showUserNotification(title: "Command X", message: msg)
        }
    }

    private func tryGetFinderSelectionAndCut(retryCount: Int) {
        var error: NSDictionary?
        // AppleScript to get Finder selection
        let script = """
        tell application "Finder"
            activate
            try
                if exists front window then
                    set sel to selection of front window
                else
                    set sel to selection
                end if
            on error
                set sel to selection
            end try
            if (count of sel) is 0 then
                return "NO_SELECTION"
            end if
            set output to ""
            repeat with f in sel
                set output to output & POSIX path of (f as alias) & "\0"
            end repeat
            return output
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            if let output = appleScript.executeAndReturnError(&error).stringValue {
                if output == "NO_SELECTION" {
                    showUserNotification(title: "Command X", message: "No files or folders selected in Finder.")
                    NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: "No files or folders selected in Finder.")
                } else {
                    // Parse POSIX paths and set pasteboard with URLs and cut flag
                    let paths = output.split(separator: "\0").map { String($0) }.filter { !$0.isEmpty }
                    let urls = paths.map { URL(fileURLWithPath: $0) }
                    if !urls.isEmpty {
                        // Store in our manager
                        FileOperationManager.shared.cut(urls: urls)
                        // Write to general pasteboard
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        _ = pb.writeObjects(urls as [NSPasteboardWriting])
                        pb.setString("1", forType: NSPasteboard.PasteboardType("com.apple.finder.cut"))

                        showUserNotification(title: "Command X", message: "Cut: Finder selection copied. Use Command+V to paste (move).")
                        NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: "Cut: Finder selection copied. Use Command+V to paste (move).")
                    } else {
                        showUserNotification(title: "Command X", message: "No files or folders selected in Finder.")
                        NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: "No files or folders selected in Finder.")
                    }
                }
            } else if let errorDict = error, let errorNum = errorDict[NSAppleScript.errorNumber] as? Int, errorNum == -600, retryCount < finderSelectionPollAttempts {
                // Finder not running yet, retry after delay
                NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: "Finder not running yet, retrying \(retryCount+1)/\(finderSelectionPollAttempts)...")
                DispatchQueue.main.asyncAfter(deadline: .now() + finderSelectionPollDelay) {
                    self.tryGetFinderSelectionAndCut(retryCount: retryCount + 1)
                }
                return
            } else if let errorDict = error {
                let errorNum = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
                let errorMsg = errorDict[NSAppleScript.errorMessage] as? String ?? String(describing: errorDict)
                logger.error("AppleScript error \(errorNum): \(errorMsg)")
                if errorNum == -1743 {
                    // errAEEventNotPermitted: app lacks Automation permission for Finder.
                    let msg = "Grant CommandX permission to control Finder in System Settings → Privacy & Security → Automation."
                    showUserNotification(title: "Command X – Permission Required", message: msg)
                    NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
                    NotificationCenter.default.post(name: Notification.Name("CommandXPermissionError"), object: nil)
                } else {
                    NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: "AppleScript error \(errorNum): \(errorMsg)")
                    showUserNotification(title: "Command X", message: "Failed to get Finder selection. AppleScript error \(errorNum).")
                    NotificationCenter.default.post(name: Notification.Name("CommandXPermissionError"), object: nil)
                }
            }
        } else {
            let msg = "Failed to create AppleScript"
            logger.error("Failed to create AppleScript")
            showUserNotification(title: "Command X", message: msg)
            NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
        }
    }

    private func showUserNotification(title: String, message: String) {
        // Use UserNotifications framework for modern notifications
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func showImmediateAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            if let window = NSApp.windows.first {
                alert.beginSheetModal(for: window) { _ in }
            } else {
                // Fallback modal dialog for debugging
                alert.runModal()
            }
        }
    }

    private func logPasteDiagnostics() {
        let pb = NSPasteboard.general
        let cutFlag = pb.string(forType: NSPasteboard.PasteboardType("com.apple.finder.cut")) ?? ""
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontAppName = frontApp?.localizedName ?? "(none)"
        let frontAppBundle = frontApp?.bundleIdentifier ?? "(unknown)"
        let msg = "Diagnostics: frontmost=\(frontAppName) [\(frontAppBundle)], cutFlag=\(cutFlag.isEmpty ? "no" : "yes")"
        logger.debug("Diagnostics: frontmost=\(frontAppName) [\(frontAppBundle)], cutFlag=\(cutFlag.isEmpty ? "no" : "yes")")
        NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
    }

    private func ensureSystemEventsRunning(retryCount: Int = 0, completion: @escaping (Bool) -> Void) {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.systemevents" }
        if running {
            completion(true)
            return
        }
        // Try to launch System Events
        if let seURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systemevents") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: seURL, configuration: config, completionHandler: nil)
        }
        if retryCount < systemEventsLaunchRetryAttempts {
            NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: "Waiting for System Events to launch... (\(retryCount+1)/\(systemEventsLaunchRetryAttempts))")
            DispatchQueue.main.asyncAfter(deadline: .now() + systemEventsLaunchRetryDelay) {
                self.ensureSystemEventsRunning(retryCount: retryCount + 1, completion: completion)
            }
        } else {
            completion(false)
        }
    }

    /// Errors surfaced from `runAppleScript(_:)`.
    enum AppleScriptError: LocalizedError {
        /// The AppleScript source could not be compiled.
        case compilationFailed
        /// The script executed but returned an Apple Events error.
        case executionFailed(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .compilationFailed:
                return "AppleScript compilation failed."
            case .executionFailed(let code, let message):
                return "AppleScript error \(code): \(message)"
            }
        }
    }

    /// Run an AppleScript source string and return the string result, or a typed error.
    ///
    /// Error code -1743 (`errAEEventNotPermitted`) means the user has not granted
    /// Automation permission for this app in System Settings → Privacy & Security → Automation.
    private func runAppleScript(_ source: String) -> Result<String, Error> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(AppleScriptError.compilationFailed)
        }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let errorDict = errorDict {
            let code = (errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
            let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? String(describing: errorDict)
            logger.error("AppleScript error \(code): \(message)")
            return .failure(AppleScriptError.executionFailed(code: code, message: message))
        }
        return .success(result.stringValue ?? "")
    }

    private func handlePaste() {
        logger.debug("handlePaste: Command+V pressed")
        NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: "Command+V pressed")
        logPasteDiagnostics()
        let pb = NSPasteboard.general
        let cutFlag = pb.string(forType: NSPasteboard.PasteboardType("com.apple.finder.cut")) ?? ""

        // Only intercept paste if Finder is running and frontmost and we have a cut flag
        let frontApp = NSWorkspace.shared.frontmostApplication
        let isFinderFront = frontApp?.bundleIdentifier == "com.apple.finder"
        let finderRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.finder" }

        func performMovePaste() {
            // Only proceed if Finder is running
            if !finderRunning {
                let msg = "Finder is not running. Cannot perform move paste."
                showUserNotification(title: "Command X", message: msg)
                NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
                return
            }
            // Get file URLs from pasteboard
            let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
            // Get target folder from Finder
            let targetScript = """
            tell application "Finder"
                try
                    set sel to selection
                    if (count of sel) = 1 and class of item 1 of sel = folder then
                        set targetFolder to item 1 of sel
                    else
                        set targetFolder to insertion location
                    end if
                    return POSIX path of (targetFolder as alias)
                on error
                    return ""
                end try
            end tell
            """
            switch runAppleScript(targetScript) {
            case .success(let targetPath) where !targetPath.isEmpty:
                let targetURL = URL(fileURLWithPath: targetPath)
                var failedNames: [String] = []
                for url in fileURLs {
                    let dest = targetURL.appendingPathComponent(url.lastPathComponent)
                    do {
                        try FileManager.default.moveItem(at: url, to: dest)
                    } catch {
                        logger.error("Failed to move \(url) to \(dest): \(error)")
                        failedNames.append(url.lastPathComponent)
                    }
                }
                if !failedNames.isEmpty {
                    let list = failedNames.joined(separator: ", ")
                    let msg = "Failed to move: \(list)"
                    showUserNotification(title: "Command X – Move Failed", message: msg)
                    NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
                }
                // Clear the cut flag
                pb.setString("", forType: NSPasteboard.PasteboardType("com.apple.finder.cut"))
                FileOperationManager.shared.clear()

            case .failure(let error as AppleScriptError):
                // errAEEventNotPermitted (-1743): app is not allowed to control Finder.
                if case .executionFailed(let code, _) = error, code == -1743 {
                    let msg = "Grant CommandX permission to control Finder in System Settings → Privacy & Security → Automation."
                    logger.error("AppleScript permission denied (-1743) getting Finder target folder")
                    showUserNotification(title: "Command X – Permission Required", message: msg)
                    NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
                    NotificationCenter.default.post(name: Notification.Name("CommandXPermissionError"), object: nil)
                } else {
                    let msg = "Failed to get Finder target folder: \(error.localizedDescription)"
                    logger.error("Failed to get Finder target folder: \(error.localizedDescription)")
                    NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
                }

            case .failure(let error):
                let msg = "Failed to get Finder target folder: \(error.localizedDescription)"
                logger.error("Failed to get Finder target folder: \(error.localizedDescription)")
                NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)

            default:
                // Empty path — no Finder window open or no recognisable location.
                let msg = "No Finder window open; cannot determine paste destination."
                logger.info("No Finder window open; cannot determine paste destination.")
                NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
            }
        }

        // Hotkeys are only registered while Finder is frontmost (see updateFinderStatus()),
        // so if Finder is not front or there is no cut flag, there is nothing to do.
        guard isFinderFront && !cutFlag.isEmpty && finderRunning else {
            logger.debug("handlePaste: Finder not frontmost or no cut flag — ignoring")
            return
        }

        ensureSystemEventsRunning { ok in
            if ok {
                performMovePaste()
            } else {
                let msg = "System Events is not running or could not be launched. Grant Automation/Accessibility permissions and try again."
                NotificationCenter.default.post(name: Notification.Name("CommandXStatusMessage"), object: msg)
            }
        }
    }
}

extension AppDelegate {
    private func setupFinderMonitoring() {
        workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        // Remove any existing observers first to ensure idempotency
        workspaceNotificationCenter?.removeObserver(self)

        // Listen for application launch notifications
        workspaceNotificationCenter?.addObserver(self,
                                               selector: #selector(applicationDidLaunch(_:)), 
                                               name: NSWorkspace.didLaunchApplicationNotification, 
                                               object: nil)
        
        // Listen for application termination notifications
        workspaceNotificationCenter?.addObserver(self, 
                                               selector: #selector(applicationDidTerminate(_:)), 
                                               name: NSWorkspace.didTerminateApplicationNotification, 
                                               object: nil)
        
        // Listen for frontmost application changes
        workspaceNotificationCenter?.addObserver(self, 
                                               selector: #selector(frontmostApplicationDidChange(_:)), 
                                               name: NSWorkspace.didActivateApplicationNotification, 
                                               object: nil)
    }
    
    @objc private func applicationDidLaunch(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == "com.apple.finder" {
            updateFinderStatus()
        }
    }
    
    @objc private func applicationDidTerminate(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == "com.apple.finder" {
            updateFinderStatus()
        }
    }
    
    @objc private func frontmostApplicationDidChange(_ notification: Notification) {
        updateFinderStatus()
    }
    
    private func updateFinderStatus() {
        let wasActive = finderRunning && finderIsFrontmost
        
        finderRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.finder" }
        finderIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        
        let isActive = finderRunning && finderIsFrontmost
        
        if isActive != wasActive {
            if isActive {
                showMenuBarIcon()
                registerHotKeys()
            } else {
                hideMenuBarIcon()
                unregisterHotKeys()
            }
        }
    }
    
    private func showMenuBarIcon() {
        // Menu bar icon is already created, just ensure it's visible
        if let button = statusItem?.button {
            button.isEnabled = true
            button.image?.isTemplate = false
        }
    }
    
    private func hideMenuBarIcon() {
        // Disable the menu bar button instead of removing it completely
        // This keeps the app running but makes it inactive
        if let button = statusItem?.button {
            button.isEnabled = false
            button.image?.isTemplate = true
        }
        // Close popover if open
        if popover?.isShown == true {
            popover?.performClose(nil)
        }
    }
    
    private func registerHotKeys() {
        HotKeyManager.shared.onCut = handleCut
        HotKeyManager.shared.onPaste = handlePaste
        HotKeyManager.shared.registerHotKeys()
    }
    
    private func unregisterHotKeys() {
        HotKeyManager.shared.unregisterHotKeys()
    }
    private func requestInitialPermissions() {
        // Open System Settings > Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        
        // Show notification guiding user
        let content = UNMutableNotificationContent()
        content.title = "Command X Setup"
        content.body = "Please grant accessibility permission to Command X in System Settings > Privacy & Security > Accessibility."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "CommandXFirstLaunch", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    private func checkAccessibilityPermission() {
        let hasPermission = AXIsProcessTrusted()
        UserDefaults.standard.set(hasPermission, forKey: "accessibilityPermissionGranted")
        // Notify UI to update permission status
        NotificationCenter.default.post(name: Notification.Name("CommandXPermissionStatusChanged"), object: hasPermission)
    }
}
