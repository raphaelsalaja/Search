import Foundation

/// Which copies of an open address to close.
///
/// One of each address stays. The one on screen wins, then a pin, then
/// whichever comes first in the row. A pin is never closed: it is a place
/// kept, not a spare copy of the page you are reading.
enum DuplicateTabs {
    struct Tab: Equatable {
        var id: UUID
        /// The address as written. Nil is not a page, and not a copy of one.
        var url: String?
        var active: Bool
        var pinned: Bool
    }

    /// Ids to close, in the order the row has them.
    static func closing(_ tabs: [Tab]) -> [UUID] {
        var keeper: [String: UUID] = [:]
        for tab in tabs {
            guard let url = tab.url, !url.isEmpty, tab.active, keeper[url] == nil else { continue }
            keeper[url] = tab.id
        }
        for tab in tabs {
            guard let url = tab.url, !url.isEmpty, keeper[url] == nil, tab.pinned else { continue }
            keeper[url] = tab.id
        }
        for tab in tabs {
            guard let url = tab.url, !url.isEmpty, keeper[url] == nil else { continue }
            keeper[url] = tab.id
        }
        return tabs.compactMap { tab in
            guard let url = tab.url, let keep = keeper[url], keep != tab.id, !tab.pinned else { return nil }
            return tab.id
        }
    }
}
