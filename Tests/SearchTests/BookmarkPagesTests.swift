import XCTest
@testable import Search

/// Which pages a folder holds, and in what order. No window: the walk is
/// the list itself, folders opened where they sit.
final class BookmarkPagesTests: XCTestCase {
    func testOrderFollowsTheFolder() {
        let tree = [
            Bookmark.site("One", URL(string: "https://example.com/1")!),
            Bookmark.site("Two", URL(string: "https://example.com/2")!),
            Bookmark.folder("Later", [
                Bookmark.site("Four", URL(string: "https://example.com/4")!),
            ]),
            Bookmark.site("Three", URL(string: "https://example.com/3")!),
        ]
        XCTAssertEqual(Bookmarks.pages(in: tree).map(\.url.absoluteString), [
            "https://example.com/1",
            "https://example.com/2",
            "https://example.com/4",
            "https://example.com/3",
        ])
        XCTAssertEqual(Bookmarks.pages(in: tree).map(\.title), ["One", "Two", "Four", "Three"])
    }

    func testSubfoldersOpenWhereTheySit() {
        let tree = [
            Bookmark.site("Before", URL(string: "https://example.com/before")!),
            Bookmark.folder("Outer", [
                Bookmark.site("First", URL(string: "https://example.com/first")!),
                Bookmark.folder("Inner", [
                    Bookmark.site("Deep", URL(string: "file:///tmp/deep.html")!),
                    Bookmark(title: "  ", url: "https://example.com/unnamed", children: nil),
                ]),
                Bookmark.site("After inner", URL(string: "https://example.com/after")!),
            ]),
            Bookmark.site("Last", URL(string: "https://example.com/last")!),
        ]
        let pages = Bookmarks.pages(in: tree)
        XCTAssertEqual(pages.map(\.url.absoluteString), [
            "https://example.com/before",
            "https://example.com/first",
            "file:///tmp/deep.html",
            "https://example.com/unnamed",
            "https://example.com/after",
            "https://example.com/last",
        ])
        XCTAssertEqual(pages.map(\.title), ["Before", "First", "Deep", "", "After inner", "Last"])
        // The folder itself is the same walk as its children.
        let outer = tree[1]
        XCTAssertEqual(
            Bookmarks.pages(in: [outer]).map(\.url.absoluteString),
            Bookmarks.pages(in: outer.children ?? []).map(\.url.absoluteString)
        )
    }

    func testEmptyFoldersAddNothing() {
        let tree = [
            Bookmark.folder("Empty", []),
            Bookmark(title: "No children", url: nil, children: nil),
            Bookmark.folder("Only empty", [
                Bookmark.folder("Deeper", []),
                Bookmark(title: "Also empty", url: nil, children: nil),
            ]),
            Bookmark(title: "Script", url: "javascript:void(0)", children: nil),
            Bookmark(title: "Words", url: "not a url", children: nil),
            Bookmark.site("Kept", URL(string: "https://example.com/kept")!),
            Bookmark.folder("Empty after", []),
        ]
        XCTAssertEqual(Bookmarks.pages(in: tree).map(\.url.absoluteString), ["https://example.com/kept"])
        XCTAssertTrue(Bookmarks.pages(in: [Bookmark.folder("Nothing", [])]).isEmpty)
        XCTAssertTrue(Bookmarks.pages(in: []).isEmpty)
    }

    func testAlreadyOpenIsSkippedAndTheFirstCopyStays() {
        let pages = Bookmarks.pages(in: [
            Bookmark.site("One", URL(string: "https://example.com/1")!),
            Bookmark.site("Two", URL(string: "https://example.com/2")!),
            Bookmark.site("Two again", URL(string: "https://example.com/2")!),
            Bookmark.site("Three", URL(string: "https://example.com/3")!),
        ])
        let left = Bookmarks.unopened(pages, among: ["https://example.com/1"])
        XCTAssertEqual(left.map(\.url.absoluteString), [
            "https://example.com/2",
            "https://example.com/3",
        ])
        XCTAssertEqual(left.map(\.title), ["Two", "Three"])
        XCTAssertEqual(
            Bookmarks.unopened(pages, among: []).map(\.url.absoluteString),
            ["https://example.com/1", "https://example.com/2", "https://example.com/3"]
        )
    }
}
