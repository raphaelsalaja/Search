import XCTest
@testable import Search

/// Which copy of an address stays open. No window: the row is a list of ids.
final class DuplicateTabsTests: XCTestCase {
    private func id(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!
    }

    private func tab(_ n: Int, _ url: String?, active: Bool = false, pinned: Bool = false) -> DuplicateTabs.Tab {
        DuplicateTabs.Tab(id: id(n), url: url, active: active, pinned: pinned)
    }

    func testTheActiveCopyStaysAndTheEarlierOnesClose() {
        let tabs = [
            tab(1, "https://example.com/a"),
            tab(2, "https://example.com/a", active: true),
            tab(3, "https://example.com/b"),
            tab(4, "https://example.com/a"),
        ]
        XCTAssertEqual(DuplicateTabs.closing(tabs), [id(1), id(4)])
    }

    func testWithoutAnActiveCopyTheFirstStays() {
        let tabs = [
            tab(1, "https://example.com/a"),
            tab(2, "https://example.com/a"),
            tab(3, "https://example.com/a"),
        ]
        XCTAssertEqual(DuplicateTabs.closing(tabs), [id(2), id(3)])
    }

    func testADifferentAddressOrAnEmptyOneIsNotACopy() {
        let tabs = [
            tab(1, "https://example.com/a"),
            tab(2, "https://example.com/a/"),
            tab(3, "https://example.com/b"),
            tab(4, nil),
            tab(5, ""),
        ]
        XCTAssertTrue(DuplicateTabs.closing(tabs).isEmpty)
    }

    func testAPinIsNeverClosed() {
        let tabs = [
            tab(1, "https://example.com/a", pinned: true),
            tab(2, "https://example.com/a", active: true),
            tab(3, "https://example.com/a"),
            tab(4, "https://example.com/b", pinned: true),
            tab(5, "https://example.com/b"),
        ]
        // The page on screen stays, and so does the pin of that address.
        // Of the other address the pin stays and the loose copy closes.
        XCTAssertEqual(DuplicateTabs.closing(tabs), [id(3), id(5)])
    }
}