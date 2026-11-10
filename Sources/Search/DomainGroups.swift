import Foundation

/// Gathering the open tabs of one space by site.
///
/// The row already has groups (see TabGroup). This only decides which
/// ordinary tabs join which group, and what a new group is called. Pins,
/// private tabs and the bench's tabs are handed in with no key, so they
/// stay where they are. A split pair is decided before this runs: both
/// halves carry the same key, or neither does, so the pair is never pulled
/// apart.
enum DomainGroups {
    struct Tab: Equatable {
        var id: UUID
        /// The site this tab groups under, or nil when it doesn't group.
        var key: String?
        /// The group it is already shown in, if that group is one this
        /// space still has.
        var groupID: UUID?
    }

    struct Group: Equatable {
        var id: UUID
        var name: String
        /// Set when this command made the group, or when it adopted a group
        /// already named for the site. Nil on a group made by hand under
        /// some other name, which is left alone.
        var domain: String?
    }

    enum Op: Equatable {
        /// A new group, its tabs in the order they already have in the row.
        case create(domain: String, title: String, ids: [UUID])
        /// Tabs joining a group that already stands for this site.
        case join(group: UUID, domain: String, ids: [UUID])
    }

    /// The site a page groups under. `registrable` is its eTLD+1 (see
    /// Registrable), so mail.google.com and docs.google.com are one site.
    /// An address, localhost and a file are their own: nothing is peeled
    /// off them. A new tab, a Search page, or anything that isn't a site
    /// doesn't group.
    static func key(of url: URL?, registrable: (String) -> String) -> String? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        if url.isFileURL || scheme == "file" { return "file" }
        guard scheme == "http" || scheme == "https" else { return nil }
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        // www.github.com and github.com are one site even when the suffix
        // list can't be asked, which would otherwise leave the www on.
        if host.hasPrefix("www."), host.count > 4 {
            host = String(host.dropFirst(4))
        }
        guard !host.isEmpty else { return nil }
        let site = registrable(host)
        return site.isEmpty ? nil : site
    }

    /// Both halves of a split, or neither. Two different sites stay loose,
    /// so one half is not carried into the other's group and the pair
    /// stays a pair in the row.
    static func pairKeys(_ left: String?, _ right: String?) -> (String?, String?) {
        guard let left, left == right else { return (nil, nil) }
        return (left, left)
    }

    /// What the group is called. GitHub rather than github.com; an address
    /// wears itself, since it has no name of its own.
    static func title(for key: String) -> String {
        if key == "file" { return "Files" }
        if key == "localhost" { return "Localhost" }
        let labels = key.split(separator: ".").map(String.init)
        guard labels.count >= 2, labels.last?.contains(where: \.isLetter) == true else { return key }
        let label = labels[0]
        if let brand = brands[label] { return brand }
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// Two sites whose names would read the same (apple.com and apple.org)
    /// keep the host, so the groups stay apart.
    static func titles(for keys: [String]) -> [String: String] {
        var friendly: [String: String] = [:]
        for key in keys where friendly[key] == nil { friendly[key] = title(for: key) }
        var counts: [String: Int] = [:]
        for name in friendly.values { counts[name, default: 0] += 1 }
        var titled: [String: String] = [:]
        for (key, name) in friendly {
            titled[key] = counts[name, default: 0] > 1 ? key : name
        }
        return titled
    }

    /// What to do, in the order the sites first appear in `tabs`. A site
    /// with one tab is left loose: a heading for a single tab is only
    /// noise. A tab already in a group made for something else stays
    /// there. Running it again, once everything that can move has moved,
    /// is nothing.
    static func plan(tabs: [Tab], groups: [Group]) -> [Op] {
        var seen: [String] = []
        var known = Set<String>()
        for tab in tabs {
            guard let key = tab.key, known.insert(key).inserted else { continue }
            seen.append(key)
        }
        let names = titles(for: seen)
        func want(_ key: String) -> String { names[key] ?? title(for: key) }
        func home(_ key: String) -> Group? {
            if let exact = groups.first(where: { $0.domain == key }) { return exact }
            let name = want(key)
            return groups.first { $0.domain == nil && ($0.name == name || $0.name == key) }
        }
        var homeKey: [UUID: String] = [:]
        for key in seen {
            if let group = home(key) { homeKey[group.id] = key }
        }

        var pools: [String: [UUID]] = [:]
        var order: [String] = []
        for tab in tabs {
            guard let key = tab.key else { continue }
            if let id = tab.groupID, homeKey[id] != key { continue }
            if pools[key] == nil { order.append(key) }
            pools[key, default: []].append(tab.id)
        }

        var ops: [Op] = []
        for key in order {
            let pool = pools[key] ?? []
            guard pool.count >= 2 else { continue }
            let existing = home(key)
            // No group yet: nothing is already in it. Comparing with nil
            // would treat every loose tab as a member and make nothing.
            let members = existing.map { group in
                tabs.compactMap { $0.groupID == group.id ? $0.id : nil }
            } ?? []
            let already = Set(members)
            let adding = pool.filter { !already.contains($0) }
            guard !adding.isEmpty else { continue }
            if let existing {
                ops.append(.join(group: existing.id, domain: key, ids: adding))
            } else if adding.count >= 2 {
                ops.append(.create(domain: key, title: want(key), ids: adding))
            }
        }
        return ops
    }

    /// Names people expect to see with their own capitals. Anything else
    /// takes a capital on its first letter, which is enough for most sites.
    private static let brands: [String: String] = [
        "youtube": "YouTube", "github": "GitHub", "icloud": "iCloud",
        "linkedin": "LinkedIn", "paypal": "PayPal", "tiktok": "TikTok",
        "openai": "OpenAI", "chatgpt": "ChatGPT", "ebay": "eBay",
        "imdb": "IMDb", "whatsapp": "WhatsApp", "bbc": "BBC", "cnn": "CNN",
        "nytimes": "NYTimes",
    ]
}
