import AppKit
import XCTest
@testable import Search

/// Opening a folder's bookmarks. The tabs are the kind a session brings
/// back: an address and a title, and a web view only for the one in front.
@MainActor
final class OpenAllBookmarksTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "open-all-bookmarks-\(getpid())", 1)
        super.setUp()
    }

    override func tearDown() {
        Ask.testing = nil
        super.tearDown()
    }

    func testOnlyTheFirstTabWakes() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let before = Set(browser.tabs.map(\.id))
        browser.openAllInTabs([
            Bookmark.site("A", URL(string: "https://example.com/a")!),
            Bookmark.folder("Sub", [
                Bookmark.site("B", URL(string: "https://example.com/b")!),
            ]),
            Bookmark.site("C", URL(string: "https://example.com/c")!),
        ])
        let opened = browser.tabs.filter { !before.contains($0.id) }
        XCTAssertEqual(opened.map { $0.address?.absoluteString }, [
            "https://example.com/a",
            "https://example.com/b",
            "https://example.com/c",
        ])
        XCTAssertEqual(browser.active?.address?.absoluteString, "https://example.com/a")
        XCTAssertFalse(opened[0].asleep, "The one in front loads")
        XCTAssertNotNil(opened[0].built)
        XCTAssertTrue(opened[1].asleep)
        XCTAssertNil(opened[1].built, "A tab not gone to has no web view")
        XCTAssertTrue(opened[2].asleep)
        XCTAssertNil(opened[2].built)
        XCTAssertTrue(opened.allSatisfy { $0.groupID == nil })
    }

    func testAnOpenPageIsLeftAsItIs() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        browser.open(URL(string: "https://example.com/b")!, foreground: false)
        let before = Set(browser.tabs.map(\.id))
        browser.openAllInTabs([
            Bookmark.site("A", URL(string: "https://example.com/a")!),
            Bookmark.site("B", URL(string: "https://example.com/b")!),
            Bookmark.site("C", URL(string: "https://example.com/c")!),
        ])
        let opened = browser.tabs.filter { !before.contains($0.id) }
        XCTAssertEqual(opened.map { $0.address?.absoluteString }, [
            "https://example.com/a",
            "https://example.com/c",
        ])
    }

    func testMoreThanTheThresholdAsks() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let count = browser.tabs.count
        let twenty = (1...Bookmarks.openAllConfirmCount).map {
            Bookmark.site("\($0)", URL(string: "https://example.com/n\($0)")!)
        }
        Ask.testing = false
        browser.openAllInTabs(twenty)
        XCTAssertEqual(browser.tabs.count, count + Bookmarks.openAllConfirmCount, "Twenty opens without asking")

        let over = (1...Bookmarks.openAllConfirmCount + 1).map {
            Bookmark.site("Over \($0)", URL(string: "https://example.com/over\($0)")!)
        }
        let asked = browser.tabs.count
        Ask.testing = false
        browser.openAllInTabs(over)
        XCTAssertEqual(browser.tabs.count, asked, "Cancel opens nothing")
        Ask.testing = true
        browser.openAllInTabs(over)
        XCTAssertEqual(browser.tabs.count, asked + Bookmarks.openAllConfirmCount + 1)
        let added = browser.tabs.suffix(Bookmarks.openAllConfirmCount + 1)
        XCTAssertEqual(added.filter { $0.asleep }.count, Bookmarks.openAllConfirmCount)
        XCTAssertFalse(added.first?.asleep ?? true)
    }
}
