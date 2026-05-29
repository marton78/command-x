// CommandXTests.swift
// CommandXTests
//
// Unit tests for path-parsing logic extracted from AppDelegate.

import XCTest
@testable import CommandX

final class CommandXTests: XCTestCase {

    // MARK: - parseFinderPaths

    func testNormalPaths() {
        let output = "/Users/alice/file.txt\0/Users/alice/document.pdf\0"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0], URL(fileURLWithPath: "/Users/alice/file.txt"))
        XCTAssertEqual(urls[1], URL(fileURLWithPath: "/Users/alice/document.pdf"))
    }

    func testPathsWithSpaces() {
        let output = "/Users/alice/my documents/report Q1.pdf\0/Users/alice/photo library/IMG 001.jpg\0"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].path, "/Users/alice/my documents/report Q1.pdf")
        XCTAssertEqual(urls[1].path, "/Users/alice/photo library/IMG 001.jpg")
    }

    func testPathsWithUnicode() {
        let output = "/Users/alice/日本語/ファイル.txt\0/Users/alice/Ünïcödé foldér/résumé.docx\0"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].path, "/Users/alice/日本語/ファイル.txt")
        XCTAssertEqual(urls[1].path, "/Users/alice/Ünïcödé foldér/résumé.docx")
    }

    func testNulDelimiterWithoutTrailingNul() {
        // Defensive: no trailing \0
        let output = "/Users/alice/a.txt\0/Users/alice/b.txt"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].path, "/Users/alice/a.txt")
        XCTAssertEqual(urls[1].path, "/Users/alice/b.txt")
    }

    func testEmptyString() {
        let urls = parseFinderPaths("")
        XCTAssertTrue(urls.isEmpty)
    }

    func testSinglePath() {
        let output = "/Users/alice/only.txt\0"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].path, "/Users/alice/only.txt")
    }

    func testOnlyNulCharacters() {
        let output = "\0\0\0"
        let urls = parseFinderPaths(output)
        XCTAssertTrue(urls.isEmpty)
    }
}
