// HotKeyManager.swift
// Command X
//
// Handles global hotkey registration for Command+X and Command+V

import Cocoa
import Carbon

class HotKeyManager {
    static let shared = HotKeyManager()
    private var cutHotKey: EventHotKeyRef?
    private var pasteHotKey: EventHotKeyRef?
    var onCut: (() -> Void)?
    var onPaste: (() -> Void)?

    func registerHotKeys() {
        // Command+X
        registerHotKey(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(cmdKey), id: 1)
        // Command+V - register so we can conditionally intercept paste when we have a cut
        registerHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey), id: 2)
        installEventHandler()
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let eventHotKeyID = EventHotKeyID(signature: OSType(id), id: id)
        RegisterEventHotKey(keyCode, modifiers, eventHotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if id == 1 { cutHotKey = hotKeyRef } else if id == 2 { pasteHotKey = hotKeyRef }
    }

    private func installEventHandler() {
        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            switch hotKeyID.id {
            case 1:
                HotKeyManager.shared.onCut?()
            case 2:
                HotKeyManager.shared.onPaste?()
            default:
                break
            }
            return noErr
        }, 1, [eventSpec], nil, nil)
    }

    func unregisterHotKeys() {
        if let cutHotKey = cutHotKey {
            UnregisterEventHotKey(cutHotKey)
            self.cutHotKey = nil
        }
        if let pasteHotKey = pasteHotKey {
            UnregisterEventHotKey(pasteHotKey)
            self.pasteHotKey = nil
        }
    }
}
