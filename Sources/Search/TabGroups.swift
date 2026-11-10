import SwiftUI
import AppKit

/// Unshifted heading and member frames in the layout's named coordinate space.
struct GroupDropFrame: Equatable {
    let group: UUID
    var tab: UUID? = nil
    let rect: CGRect
}

struct GroupDropTarget: Equatable {
    let group: UUID
    var member: UUID? = nil
    var after = false
}

struct GroupDropFrames: PreferenceKey {
    static var defaultValue: [UUID: GroupDropFrame] = [:]

    static func reduce(value: inout [UUID: GroupDropFrame], nextValue: () -> [UUID: GroupDropFrame]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }

    static func resolve(_ point: CGPoint, frames: [UUID: GroupDropFrame],
                        groups: [TabGroup], excluding source: UUID, vertical: Bool) -> GroupDropTarget? {
        // Model group order gives overlapping regions a deterministic priority.
        for group in groups {
            let heading = frames[group.id]?.rect
            let members = frames.values.filter { $0.group == group.id && $0.tab != nil && $0.tab != source }
                .sorted { vertical ? $0.rect.minY < $1.rect.minY : $0.rect.minX < $1.rect.minX }
            let extent = members.reduce(heading ?? .null) { $0.union($1.rect) }
            guard extent.contains(point) else { continue }
            if heading?.contains(point) == true || group.collapsed || members.isEmpty {
                return GroupDropTarget(group: group.id)
            }
            let position = vertical ? point.y : point.x
            if let next = members.first(where: { position < (vertical ? $0.rect.midY : $0.rect.midX) }) {
                return GroupDropTarget(group: group.id, member: next.tab)
            }
            return GroupDropTarget(group: group.id, member: members.last?.tab, after: true)
        }
        return nil
    }
}

/// A quiet name above the tabs it contains, in either layout.
struct GroupHeading: View {
    @Environment(\.greys) private var greys
    @Environment(\.tabShortcutNumbers) private var shortcutNumbers
    @ObservedObject var browser: Browser
    let group: TabGroup
    var horizontal = false
    var dragSpace: String? = nil
    /// In the column of icons (SideIcons.swift): the name's first letter in
    /// a short heading, the name itself in its tooltip.
    var compact = false

    @State private var draft = ""
    @State private var hovering = false
    @State private var dropping = false
    @FocusState private var focused: Bool

    private var editing: Bool { browser.editingGroupID == group.id }

    /// Its height in the column, a little under a tab's.
    static let height: CGFloat = 24
    /// And in the column of icons.
    static let compactHeight: CGFloat = 18

    /// Measured once a name: the row asks for every heading's on every redraw.
    private static var measured: [String: CGFloat] = [:]
    private static let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    static func width(for name: String, numbered: Bool = false, marked: Bool = false) -> CGFloat {
        let text: CGFloat
        if let known = measured[name] {
            text = known
        } else {
            text = ceil((name as NSString).size(withAttributes: [.font: font]).width)
            if measured.count > 500 { measured.removeAll() }
            measured[name] = text
        }
        // A site's icon, when the group was gathered by domain and one of
        // its tabs already has one. Room for it either way: the icon arrives
        // a moment after the group does.
        return text + 20 + (numbered ? 23 : 0) + (marked ? 22 : 0)
    }

    var body: some View {
        if compact { short } else { long }
    }

    /// A tab of a site's group, so its icon can stand in the heading once
    /// the page has one. Nothing fetched, and nothing for a group made by hand.
    private var siteTab: Tab? {
        guard group.domain != nil else { return nil }
        let members = browser.tabs.filter { $0.groupID == group.id && $0.pin == nil }
        return members.first { $0.icon != nil } ?? members.first
    }

    /// The column of icons' heading: the letter, a fold mark beside it.
    private var short: some View {
        HStack(spacing: 2) {
            if let tab = siteTab {
                GroupLetter(tab: tab, letter: group.name.first.map { String($0).uppercased() } ?? "•")
            } else {
                Text(group.name.first.map { String($0).uppercased() } ?? "•")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 6.5, weight: .bold))
                .rotationEffect(.degrees(group.collapsed ? -90 : 0))
        }
        .foregroundStyle(hovering ? Palette.ink.opacity(0.7) : Palette.muted)
        .frame(maxWidth: .infinity)
        .frame(height: Self.compactHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(dropping ? greys.wash : (hovering ? greys.hover : greys.tile)))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture { browser.toggleTabGroup(group.id) }
        .modifier(GroupHeadingShared(browser: browser, group: group, dragSpace: dragSpace, dropping: $dropping))
        .onHover { hovering = $0 }
        .help(group.collapsed ? "\(group.name) — folded" : group.name)
        .accessibilityLabel(group.name)
        // Rename Group: no room for the name here, so it is typed beside.
        .popover(isPresented: Binding(get: { editing }, set: { if !$0 { browser.editingGroupID = nil } }),
                 arrowEdge: browser.prefs.sidePosition == .right ? .leading : .trailing) {
            TextField("Group name", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 160)
                .padding(10)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { browser.editingGroupID = nil }
                .onAppear {
                    draft = group.name
                    DispatchQueue.main.async { focused = true }
                }
        }
    }

    private var long: some View {
        HStack(spacing: 8) {
            if editing {
                TextField("Group name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: horizontal ? max(60, Self.width(for: group.name) - 20) : nil)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { browser.editingGroupID = nil }
            } else if let tab = siteTab {
                GroupTitle(tab: tab, name: group.name)
            } else {
                Text(group.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !horizontal { Spacer(minLength: 0) }
            if !editing, group.collapsed {
                if let number = shortcutNumbers[group.id] {
                    TabShortcutNumber(number: number)
                } else if horizontal, browser.prefs.showsTabShortcuts {
                    Color.clear.frame(width: 15, height: 15)
                }
            }
            if !editing && !horizontal {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .rotationEffect(.degrees(group.collapsed ? -90 : 0))
                    .opacity(hovering ? 1 : 0)
            }
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 10)
        .frame(height: horizontal ? 28 : Self.height)
        .frame(maxWidth: horizontal ? nil : .infinity, alignment: .leading)
        .fixedSize(horizontal: horizontal, vertical: false)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(dropping ? greys.wash : (hovering ? greys.hover : .clear)))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { if !editing { browser.toggleTabGroup(group.id) } }
        .modifier(GroupHeadingShared(browser: browser, group: group, dragSpace: dragSpace, dropping: $dropping))
        .onHover { hovering = $0 }
        .onChange(of: editing) { _, now in
            if now {
                draft = group.name
                DispatchQueue.main.async { focused = true }
            }
        }
        .onAppear {
            if editing {
                draft = group.name
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private func commit() {
        browser.renameTabGroup(group.id, to: draft)
        browser.editingGroupID = nil
    }
}

/// The group's name, with its site's icon beside it once a tab already
/// has one. Nothing is fetched. No icon, and the heading is the name alone,
/// as a group made by hand.
private struct GroupTitle: View {
    @ObservedObject var tab: Tab
    let name: String

    var body: some View {
        HStack(spacing: tab.icon == nil ? 0 : 8) {
            if tab.icon != nil {
                Mark(icon: tab.icon, letter: "", size: 14)
            }
            Text(name)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, alignment: .leading)
        }
    }
}

/// The column of icons: the site's icon, or the group's letter until then.
private struct GroupLetter: View {
    @ObservedObject var tab: Tab
    let letter: String

    var body: some View {
        Mark(icon: tab.icon, letter: letter, size: 12)
    }
}

/// Expand All Groups and Collapse All Groups, for a right-click on the
/// empty part of the tab row. Both are always there; the one with nothing
/// to do is greyed, as in the Tabs menu.
@MainActor
enum GroupFoldMenu {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private static var actions: [Action] = []

    static func menu(for browser: Browser) -> NSMenu {
        actions = []
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Expand All Groups", key: "]", enabled: browser.canUnfoldAllGroups) {
            browser.foldAllGroups(false)
        })
        menu.addItem(item("Collapse All Groups", key: "[", enabled: browser.canFoldAllGroups) {
            browser.foldAllGroups(true)
        })
        menu.addItem(.separator())
        menu.addItem(item("Ungroup All", key: "u", enabled: browser.canUngroupAll) {
            browser.ungroupAll()
        })
        menu.addItem(item("Close Duplicate Tabs", key: "d", enabled: browser.canCloseDuplicateTabs) {
            browser.closeDuplicateTabs()
        })
        menu.addItem(item("Sleep Other Tabs", key: "s", enabled: browser.canSleepOtherTabs) {
            browser.sleepOtherTabs()
        })
        menu.addItem(item("Reopen Closed Group", key: "t", enabled: browser.canReopenClosedGroup) {
            browser.reopenClosedGroup()
        })
        return menu
    }

    private static func item(_ title: String, key: String, enabled: Bool, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = Action(run)
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: key)
        item.target = action
        item.keyEquivalentModifierMask = [.control, .shift]
        item.isEnabled = enabled
        return item
    }
}

/// What both headings answer to: their place for a drop, a tab or a
/// group let go on them, being picked up, and their menu.
private struct GroupHeadingShared: ViewModifier {
    @ObservedObject var browser: Browser
    let group: TabGroup
    let dragSpace: String?
    @Binding var dropping: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if let dragSpace {
                    GeometryReader { geometry in
                        Color.clear.preference(key: GroupDropFrames.self,
                                               value: [group.id: GroupDropFrame(group: group.id, rect: geometry.frame(in: .named(dragSpace)))])
                    }
                }
            }
            .onDrop(of: [.text], isTargeted: $dropping) { providers in
                guard let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) else { return false }
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    guard let value else { return }
                    DispatchQueue.main.async {
                        if value.hasPrefix("search-group:"),
                           let id = UUID(uuidString: String(value.dropFirst("search-group:".count))),
                           let index = browser.tabGroups.firstIndex(where: { $0.id == group.id }) {
                            browser.moveTabGroup(id, to: index)
                        }
                    }
                }
                return true
            }
            .onDrag { NSItemProvider(object: "search-group:\(group.id.uuidString)" as NSString) }
            .contextMenu {
                Button("Rename Group") { browser.editingGroupID = group.id }
                Button(group.collapsed ? "Expand Group" : "Collapse Group") { browser.toggleTabGroup(group.id) }
                // Every group of this space, not only this one. Both stay
                // in the menu: the one with nothing to do is greyed.
                Button("Expand All Groups") { browser.foldAllGroups(false) }
                    .shortcut("tabs.expandGroups")
                    .disabled(!browser.canUnfoldAllGroups)
                Button("Collapse All Groups") { browser.foldAllGroups(true) }
                    .shortcut("tabs.collapseGroups")
                    .disabled(!browser.canFoldAllGroups)
                // The whole group into another space, still a group there: Arc's
                // folders came in wherever Arc had them.
                if browser.prefs.usesSpaces, browser.spaces.count > 1 {
                    Menu("Move Group to Space") {
                        ForEach(browser.spaces.filter { $0.id != browser.spaceID }) { space in
                            Button {
                                browser.move(group: group.id, toSpace: space.id)
                            } label: {
                                Label(space.name, systemImage: space.symbol)
                            }
                        }
                    }
                }
                Divider()
                Button("Copy Addresses") { browser.copyGroupAddresses(group.id) }
                    .shortcut("tabs.copyGroup")
                    .disabled(browser.groupAddresses(group.id).isEmpty)
                Button("Ungroup Tabs") { browser.removeTabGroup(group.id) }
                Button("Ungroup All") { browser.ungroupAll() }
                    .shortcut("tabs.ungroupAll")
                    .disabled(!browser.canUngroupAll)
                Button("Close Group") { browser.closeTabGroup(group.id) }
                    .shortcut("tabs.closeGroup")
            }
    }
}
