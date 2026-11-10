import Foundation

// Tabs › Group Tabs by Domain. The open tabs of this space gather by site
// into the groups the row already has (TabGroup, TabGroups.swift), so
// folding, expanding, ungrouping and closing one are the ones every group
// already answers to. Nothing here runs unless Settings › Tabs asks for it.

extension Browser {
    /// Several tabs picked in the row: Group Tabs by Domain gathers only
    /// those, and leaves the rest of the space where it is.
    var groupingSelection: Bool { visibleSelectedTabCount > 1 }

    /// Whether Group Tabs by Domain would move anything. With several tabs
    /// picked, only those are asked.
    var canGroupTabsByDomain: Bool {
        guard prefs.groupsByDomain, prefs.usesTabGroups else { return false }
        return !DomainGroups.plan(tabs: domainTabRefs(only: domainSelection), groups: domainGroupRefs()).isEmpty
    }

    /// Whether Ungroup All Domains has a site's group to take apart.
    /// A group made by hand, under some other name, is not one of them.
    var canUngroupAllDomains: Bool {
        prefs.groupsByDomain && prefs.usesTabGroups && tabGroups.contains { $0.domain != nil }
    }

    /// The ordinary tabs of this space, gathered by site. A site needs two
    /// tabs before it becomes a group. A split pair joins only when both
    /// pages are that site, and then both halves go, so the pair stays a pair.
    /// `selectedOnly`: several tabs picked in the row, and only those move.
    func groupTabsByDomain(selectedOnly: Bool = true) {
        guard prefs.groupsByDomain, prefs.usesTabGroups else { return }
        let only = selectedOnly ? domainSelection : nil
        let ops = DomainGroups.plan(tabs: domainTabRefs(only: only), groups: domainGroupRefs())
        guard !ops.isEmpty else { return }
        let byID = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for op in ops {
            switch op {
            case .create(let domain, let title, let ids):
                let id = UUID()
                tabGroups.append(TabGroup(id: id, name: title, collapsed: false, domain: domain))
                give(ids, to: id, known: byID)
            case .join(let group, let domain, let ids):
                // A group already called GitHub, made before this knew about
                // sites, becomes that site's group. One saved when the key
                // was still google.com is rewritten to the label, so the
                // next pass joins it instead of making a second one.
                if let index = tabGroups.firstIndex(where: { $0.id == group }), tabGroups[index].domain != domain {
                    tabGroups[index].domain = domain
                }
                give(ids, to: group, known: byID)
            }
        }
        arrangeGroupedTabs()
        writeSession(now: true)
    }

    /// The same gathering, in every open window of this profile. A selection
    /// in this window doesn't narrow the others, or this one: the command is
    /// the whole space, in each window.
    func groupTabsByDomainInAllWindows() {
        guard prefs.groupsByDomain, prefs.usesTabGroups else { return }
        for window in Browsers.all where window.isOpen && !window.isPopup && window.profileID == profileID {
            window.groupTabsByDomain(selectedOnly: false)
        }
    }

    /// The picked tabs, when there are several. Nil asks for the whole space.
    private var domainSelection: Set<Tab.ID>? {
        guard groupingSelection else { return nil }
        return selectedTabIDs
    }

    /// The site's groups come apart. Their tabs stay open, back among the
    /// ones in no group. A group made by hand stays a group.
    func ungroupAllDomains() {
        guard canUngroupAllDomains else { return }
        let ids = Set(tabGroups.compactMap { $0.domain == nil ? nil : $0.id })
        for tab in tabs where tab.groupID.map(ids.contains) == true { tab.groupID = nil }
        tabGroups.removeAll { ids.contains($0.id) }
        if let editing = editingGroupID, ids.contains(editing) { editingGroupID = nil }
        arrangeGroupedTabs()
        writeSession(now: true)
    }

    private func domainGroupRefs() -> [DomainGroups.Group] {
        tabGroups.map { DomainGroups.Group(id: $0.id, name: $0.name, domain: $0.domain) }
    }

    /// The label in front of the public suffix, from the list macOS keeps
    /// (the same one passkeys use). Without that list the host itself is
    /// the site, and www. is still taken off.
    private static let registrable: (String) -> String = {
        let suffix = Passkeys.publicSuffix.map { test in { (name: String) in test(name as CFString) } }
        return { Registrable.label(of: $0, isSuffix: suffix) }
    }()

    /// `only`: several tabs picked. The others are left out of the plan, so
    /// they neither join a group nor pull a pair apart on their own.
    private func domainTabRefs(only selected: Set<Tab.ID>? = nil) -> [DomainGroups.Tab] {
        // A pair that isn't one site, or whose halves aren't already in the
        // same group, is frozen: neither half may join a group on its own.
        var shared: [UUID: String] = [:]
        var frozen = Set<UUID>()
        if prefs.splitView {
            for pair in splits {
                // One half picked and the other not: neither half moves, so
                // the pair is not pulled into a group the other page isn't in.
                if let selected, selected.contains(pair.left) != selected.contains(pair.right) {
                    frozen.insert(pair.left)
                    frozen.insert(pair.right)
                }
                let left = tabs.first { $0.id == pair.left }
                let right = tabs.first { $0.id == pair.right }
                let keys = DomainGroups.pairKeys(
                    DomainGroups.key(of: left?.address, registrable: Self.registrable),
                    DomainGroups.key(of: right?.address, registrable: Self.registrable))
                let leftGroup = left.flatMap { group(of: $0) }
                let rightGroup = right.flatMap { group(of: $0) }
                // Same site and already in the same group (or in none): they
                // move together. Anything else, and neither half moves, so
                // one page of the pair can't land in a group the other isn't in.
                if let key = keys.0, leftGroup == rightGroup {
                    if let left { shared[left.id] = key }
                    if let right { shared[right.id] = key }
                } else {
                    if let left { frozen.insert(left.id) }
                    if let right { frozen.insert(right.id) }
                }
            }
        }
        return tabs.compactMap { tab in
            if let selected, !selected.contains(tab.id) { return nil }
            let eligible = tab.pin == nil && !tab.shy && !tab.bench && !frozen.contains(tab.id)
            let key = eligible ? (shared[tab.id] ?? DomainGroups.key(of: tab.address, registrable: Self.registrable)) : nil
            return DomainGroups.Tab(id: tab.id, key: key, groupID: group(of: tab))
        }
    }

    private func give(_ ids: [UUID], to group: UUID, known: [UUID: Tab]) {
        for id in ids {
            guard let tab = known[id], tab.pin == nil, !tab.shy, !tab.bench, tab.groupID != group else { continue }
            tab.groupID = group
        }
    }
}
