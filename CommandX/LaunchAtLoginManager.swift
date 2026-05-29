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
            // For development builds, try to check actual login items but fall back to UserDefaults
            #if DEBUG
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                if let actualState = try? checkLoginItemsState() {
                    // Sync UserDefaults with actual state
                    UserDefaults.standard.set(actualState, forKey: "launchAtLogin")
                    return actualState
                } else {
                    // Fall back to UserDefaults if APIs fail
                    return UserDefaults.standard.bool(forKey: "launchAtLogin")
                }
            }
            #else
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return isInLoginItems()
            }
            #endif
        }
        set {
            // For development builds, try to modify login items off the main thread and fall back to UserDefaults
            #if DEBUG
            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
            // Perform system login-item modification asynchronously to avoid ObjC/CF lifetime crashes on the main thread
            DispatchQueue.global(qos: .utility).async {
                autoreleasepool {
                    if #available(macOS 13.0, *) {
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch let smError as NSError where smError.code == kSMErrorAuthorizationFailure {
                            print("Failed to \(newValue ? "register" : "unregister") launch at login (authorization required): \(smError)")
                            DispatchQueue.main.async {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems")!)
                            }
                        } catch {
                            print("Failed to \(newValue ? "register" : "unregister") launch at login: \(error)")
                            // Fall back to LSSharedFileList
                            try? self.modifyLoginItem(enabled: newValue)
                        }
                    } else {
                        try? self.modifyLoginItem(enabled: newValue)
                    }
                }
            }
            #else
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch let smError as NSError where smError.code == kSMErrorAuthorizationFailure {
                    print("Failed to \(newValue ? "register" : "unregister") launch at login (authorization required): \(smError)")
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems")!)
                } catch {
                    print("Failed to \(newValue ? "register" : "unregister") launch at login: \(error)")
                    // Fall back to LSSharedFileList
                    setLoginItem(enabled: newValue)
                }
            } else {
                setLoginItem(enabled: newValue)
            }
            #endif
        }
    }
    
    // LSSharedFileList methods - used in both DEBUG and RELEASE builds with error handling
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
    
    #if !DEBUG
    // Legacy methods for RELEASE builds
    private func isInLoginItems() -> Bool {
        return (try? checkLoginItemsState()) ?? false
    }
    
    private func setLoginItem(enabled: Bool) {
        try? modifyLoginItem(enabled: enabled)
    }
    #endif
}
