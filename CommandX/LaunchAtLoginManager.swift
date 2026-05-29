// LaunchAtLoginManager.swift
// Command X
//
// Handles enabling/disabling launch at login using SMAppService (macOS 13+) or LSSharedFileList (older)

import Foundation
import CoreServices
import AppKit

#if canImport(ServiceManagement)
import ServiceManagement
#endif

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                let status = SMAppService.mainApp.status
                return status == .enabled || status == .requiresApproval
            } else {
                return (try? checkLoginItemsState()) ?? false
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch let smError as NSError where smError.code == kSMErrorAuthorizationFailure {
                    print("LaunchAtLoginManager: failed to \(newValue ? "register" : "unregister") (authorization required): \(smError)")
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems")!)
                } catch {
                    print("LaunchAtLoginManager: failed to \(newValue ? "register" : "unregister"): \(error)")
                }
            } else {
                do {
                    try modifyLoginItem(enabled: newValue)
                } catch {
                    print("LaunchAtLoginManager: failed to modify legacy login item: \(error)")
                }
            }
        }
    }

    // LSSharedFileList helpers — used on macOS < 13 only

    private func checkLoginItemsState() throws -> Bool {
        guard let loginItemsRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil) else {
            throw NSError(domain: "LaunchAtLoginManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create login items reference"])
        }
        let loginItems = loginItemsRef.takeRetainedValue()

        guard let snapshotRef = LSSharedFileListCopySnapshot(loginItems, nil) else {
            throw NSError(domain: "LaunchAtLoginManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to copy login items snapshot"])
        }
        let loginItemsArray = snapshotRef.takeRetainedValue() as? [LSSharedFileListItem] ?? []

        let appURL = Bundle.main.bundleURL

        for item in loginItemsArray {
            guard let itemURLRef = LSSharedFileListItemCopyResolvedURL(item, 0, nil) else { continue }
            let itemURL = itemURLRef.takeRetainedValue() as URL
            if itemURL == appURL {
                return true
            }
        }
        return false
    }

    private func modifyLoginItem(enabled: Bool) throws {
        guard let loginItemsRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil) else {
            throw NSError(domain: "LaunchAtLoginManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create login items reference"])
        }
        let loginItems = loginItemsRef.takeRetainedValue()

        let appURL = Bundle.main.bundleURL

        if enabled {
            LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemLast.takeUnretainedValue(), nil, nil, appURL as CFURL, nil, nil)
        } else {
            guard let snapshotRef = LSSharedFileListCopySnapshot(loginItems, nil) else {
                throw NSError(domain: "LaunchAtLoginManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to copy login items snapshot"])
            }
            let loginItemsArray = snapshotRef.takeRetainedValue() as? [LSSharedFileListItem] ?? []

            for item in loginItemsArray {
                guard let itemURLRef = LSSharedFileListItemCopyResolvedURL(item, 0, nil) else { continue }
                let itemURL = itemURLRef.takeRetainedValue() as URL
                if itemURL == appURL {
                    LSSharedFileListItemRemove(loginItems, item)
                    break
                }
            }
        }
    }
}
