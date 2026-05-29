// PathParsing.swift
// Command X
//
// Free functions for converting AppleScript output into file URLs.
// Extracted here so the logic is independently testable.

import Foundation

/// Convert the raw AppleScript output string into an array of file URLs.
///
/// The AppleScript returns POSIX paths separated by NUL characters (`\0`).
/// Each component is trimmed and empty strings are discarded.
///
/// - Parameter output: The raw string returned by the AppleScript, e.g.
///   `"/Users/alice/file.txt\0/Users/alice/another file.txt\0"`.
/// - Returns: An array of `URL` values created with `URL(fileURLWithPath:)`.
func parseFinderPaths(_ output: String) -> [URL] {
    output
        .split(separator: "\0", omittingEmptySubsequences: true)
        .map { String($0) }
        .filter { !$0.isEmpty }
        .map { URL(fileURLWithPath: $0) }
}
