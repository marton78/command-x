// FileOperationManager.swift
// Command X
//
// Handles storing cut files and performing move/symlink operations.

import Foundation

class FileOperationManager {
    static let shared = FileOperationManager()
    private(set) var cutURLs: [URL] = []
    
    func cut(urls: [URL]) {
        cutURLs = urls
    }
    
    func paste(to destination: URL, useSymlink: Bool = false) throws {
        for url in cutURLs {
            let destURL = destination.appendingPathComponent(url.lastPathComponent)
            if useSymlink {
                try FileManager.default.createSymbolicLink(at: destURL, withDestinationURL: url)
            } else {
                try FileManager.default.moveItem(at: url, to: destURL)
            }
        }
        cutURLs = []
    }
    
    func clear() {
        cutURLs = []
    }
}
