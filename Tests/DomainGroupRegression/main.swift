import Foundation

// DomainGroups and Registrable, with no AppKit. The same cases as
// DomainGroupTests, so a Linux checkout can compile just these files.

let suffix: (String) -> Bool = { name in
    ["com", "org", "net", "io", "co.uk", "com.au", "github.io", "eu", "ru", "de"].contains(name)
}
func registrable(_ host: String) -> String { Registrable.domain(of: host, isSuffix: suffix) }
func key(_ text: String) -> String? {
    DomainGroups.key(of: URL(string: text)) { Registrable.label(of: $0, isSuffix: suffix) }
}
func id(_ n: Int) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")! }
func tab(_ n: Int, _ text: String?, group: Int? = nil) -> DomainGroups.Tab {
    DomainGroups.Tab(id: id(n), key: text.flatMap(key), groupID: group.map(id))
}
func loose(_ n: Int, _ site: String) -> DomainGroups.Tab { DomainGroups.Tab(id: id(n), key: site, groupID: nil) }

var failures = 0
func expect(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("FAIL: \(what)") } else { print("ok    \(what)") }
}
func same<T: Equatable>(_ value: T, _ want: T, _ what: String) { expect(value == want, what) }

same(registrable("docs.google.com"), "google.com", "docs.google.com is google.com")
same(registrable("mail.google.com"), "google.com", "mail.google.com is google.com")
same(registrable("gist.github.com"), "github.com", "gist.github.com is github.com")
same(registrable("www.bbc.co.uk"), "bbc.co.uk", "www.bbc.co.uk keeps co.uk")
same(registrable("foo.github.io"), "foo.github.io", "a github.io site stays itself")
expect(registrable("foo.github.io") != registrable("bar.github.io"), "two github.io sites are not one")
same(registrable("192.168.1.20"), "192.168.1.20", "an address stays an address")
same(registrable("localhost"), "localhost", "localhost stays localhost")
same(registrable("::1"), "::1", "an ipv6 address stays itself")
same(Registrable.domain(of: "a.example.com", isSuffix: nil), "a.example.com", "without the suffix list the host stays whole")

same(key("https://docs.google.com/document/d/1"), "google", "a docs url keys as google")
same(key("https://mail.google.com/mail"), "google", "gmail keys as google")
same(key("https://www.GitHub.com/search"), "github", "www and capitals come off")
same(key("https://github.com."), "github", "a trailing dot comes off")
same(key("https://gist.github.com/a"), "github", "gist joins github")
same(key("https://www.bbc.co.uk/news"), "bbc", "bbc.co.uk is bbc")
same(key("https://mail.google.co.uk/"), "google", "mail.google.co.uk is google")
same(key("https://google.de/"), "google", "google.de is google")
same(key("https://foo.github.io/page"), "foo", "foo.github.io is foo")
expect(key("https://foo.github.io/") != key("https://bar.github.io/"), "github.io keys differ")
same(key("http://192.168.1.20:8080/admin"), "192.168.1.20", "a port doesn't split an address")
same(key("http://10.0.0.1/"), "10.0.0.1", "10.0.0.1")
expect(key("http://10.0.0.1/") != key("http://10.0.0.2/"), "two addresses are two sites")
same(key("http://localhost:3000/"), "localhost", "localhost:3000")
same(key("http://localhost:8080/app"), "localhost", "localhost:8080 is the same machine")
same(key("http://[::1]/"), "::1", "::1")
same(key("file:///Users/me/notes.html"), "file", "a file")
same(key("file:///tmp/a.pdf"), "file", "another file, same group")
expect(key("search://settings") == nil, "a Search page doesn't group")
expect(key("about:blank") == nil, "a blank tab doesn't group")
expect(key("https://") == nil, "a url with no host doesn't group")

same(DomainGroups.title(for: "github.com"), "GitHub", "GitHub, not github.com")
same(DomainGroups.title(for: "google.com"), "Google", "Google")
same(DomainGroups.title(for: "youtube.com"), "YouTube", "YouTube")
same(DomainGroups.title(for: "bbc.co.uk"), "BBC", "BBC")
same(DomainGroups.title(for: "localhost"), "Localhost", "Localhost")
same(DomainGroups.title(for: "file"), "Files", "Files")
same(DomainGroups.title(for: "192.168.1.20"), "192.168.1.20", "an address is its own title")
same(DomainGroups.title(for: "::1"), "::1", "ipv6 is its own title")
let collided = DomainGroups.titles(for: ["apple.com", "apple.org"])
same(collided["apple.com"], "apple.com", "apple.com keeps its host when Apple would collide")
same(collided["apple.org"], "apple.org", "apple.org keeps its host too")
same(DomainGroups.titles(for: ["github.com"])["github.com"], "GitHub", "one Apple-shaped name is still friendly")

same(DomainGroups.pairKeys("google.com", "google.com").0, "google.com", "a pair of one site shares it")
same(DomainGroups.pairKeys("google.com", "google.com").1, "google.com", "both halves")
expect(DomainGroups.pairKeys("google.com", "github.com").0 == nil, "a pair of two sites stays loose")
expect(DomainGroups.pairKeys("google.com", "github.com").1 == nil, "neither half is pulled across")
expect(DomainGroups.pairKeys("google.com", nil).0 == nil, "a pair with a blank stays loose")
expect(DomainGroups.pairKeys(nil, nil).0 == nil, "two blanks stay loose")

let gathered = DomainGroups.plan(tabs: [
    tab(1, "https://docs.google.com/a"),
    tab(2, "https://github.com/a"),
    tab(3, "https://mail.google.com/b"),
    tab(4, "https://example.com/"),
    tab(5, "https://gist.github.com/b"),
], groups: [])
same(gathered, [
    .create(domain: "google", title: "Google", ids: [id(1), id(3)]),
    .create(domain: "github", title: "GitHub", ids: [id(2), id(5)]),
], "sites gather in the order they appear, and a single tab stays loose")

same(DomainGroups.plan(tabs: [
    tab(1, "file:///tmp/a.pdf"),
    tab(2, "http://localhost:3000/"),
    tab(3, "file:///tmp/b.pdf"),
    tab(4, "http://localhost:8080/"),
    tab(5, "http://192.168.1.20/"),
    tab(6, "http://192.168.1.20:9/"),
    tab(7, "http://10.0.0.1/"),
    tab(8, "about:blank"),
], groups: []), [
    .create(domain: "file", title: "Files", ids: [id(1), id(3)]),
    .create(domain: "localhost", title: "Localhost", ids: [id(2), id(4)]),
    .create(domain: "192.168.1.20", title: "192.168.1.20", ids: [id(5), id(6)]),
], "files, localhost and an address each group; one address and a blank don't")

let work = DomainGroups.Group(id: id(9), name: "Work", domain: nil)
same(DomainGroups.plan(tabs: [
    DomainGroups.Tab(id: id(1), key: nil, groupID: nil),
    DomainGroups.Tab(id: id(2), key: nil, groupID: nil),
    DomainGroups.Tab(id: id(3), key: "github.com", groupID: id(9)),
    loose(4, "github.com"),
], groups: [work]), [], "a pin, a private tab and a hand-made group are left alone")

let github = DomainGroups.Group(id: id(9), name: "GitHub", domain: nil)
same(DomainGroups.plan(tabs: [
    DomainGroups.Tab(id: id(1), key: "github.com", groupID: id(9)),
    loose(2, "github.com"),
    loose(3, "github.com"),
], groups: [github]), [
    .join(group: id(9), domain: "github.com", ids: [id(2), id(3)]),
], "a group already called GitHub takes the new tabs")

let adopted = DomainGroups.Group(id: id(9), name: "Code", domain: "github.com")
expect(DomainGroups.plan(tabs: [
    DomainGroups.Tab(id: id(1), key: "github.com", groupID: id(9)),
    DomainGroups.Tab(id: id(2), key: "github.com", groupID: id(9)),
], groups: [adopted]).isEmpty, "running it again moves nothing")
same(DomainGroups.plan(tabs: [
    DomainGroups.Tab(id: id(1), key: "github.com", groupID: id(9)),
    loose(3, "github.com"),
], groups: [adopted]), [
    .join(group: id(9), domain: "github.com", ids: [id(3)]),
], "a renamed site group still takes its site")

same(DomainGroups.plan(tabs: [
    loose(1, "apple.com"), loose(2, "apple.com"),
    loose(3, "apple.org"), loose(4, "apple.org"),
], groups: []), [
    .create(domain: "apple.com", title: "apple.com", ids: [id(1), id(2)]),
    .create(domain: "apple.org", title: "apple.org", ids: [id(3), id(4)]),
], "apple.com and apple.org stay two groups")

let saved = TabGroup(id: id(1), name: "GitHub", collapsed: true, domain: "github.com")
let data = try JSONEncoder().encode(saved)
let back = try JSONDecoder().decode(TabGroup.self, from: data)
expect(back == saved, "a site's group round-trips")
expect(String(data: data, encoding: .utf8)?.contains("github.com") == true, "the site is written down")
let older = """
{"id":"\(id(1).uuidString)","name":"Work","collapsed":false}
""".data(using: .utf8)!
let plain = try JSONDecoder().decode(TabGroup.self, from: older)
expect(plain.name == "Work" && !plain.collapsed && plain.domain == nil, "a group saved before sites still loads")
let folded = """
{"id":"\(id(1).uuidString)","name":"Work"}
""".data(using: .utf8)!
expect(try !JSONDecoder().decode(TabGroup.self, from: folded).collapsed, "a group saved without its fold is open")

same(DomainGroups.plan(tabs: [
    tab(1, "https://name.eu/"),
    tab(2, "https://name.ru/a"),
    tab(3, "https://name.co.uk/"),
    tab(4, "https://www.name.com/"),
    tab(5, "https://name.de/"),
], groups: []), [
    .create(domain: "name", title: "Name", ids: [id(1), id(2), id(3), id(4), id(5)]),
], "name.eu, name.ru, name.co.uk, name.com and name.de are one group")
same(DomainGroups.plan(tabs: [
    tab(1, "https://name.eu/"),
    tab(2, "https://other.eu/"),
    tab(3, "https://name.ru/"),
    tab(4, "https://foo.github.io/"),
    tab(5, "https://bar.github.io/"),
    tab(6, "https://other.com/"),
], groups: []), [
    .create(domain: "name", title: "Name", ids: [id(1), id(3)]),
    .create(domain: "other", title: "Other", ids: [id(2), id(6)]),
], "a different name stays apart, and so do two github.io sites")

// The catalogue of menu shortcuts, read as text: Expand All and Collapse
// All have keys, and no two commands in that list share one. The reserved
// list and the space keys sit outside this array.
let shortcutsURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/Search/Shortcuts.swift")
let shortcuts = try String(contentsOf: shortcutsURL, encoding: .utf8)
guard let catalogueStart = shortcuts.range(of: "static let all: [Command] = ["),
      let catalogueEnd = shortcuts.range(of: "] + (1...9).map") else {
    expect(false, "the command list is where the shortcut check looks")
    exit(1)
}
let catalogue = shortcuts[catalogueStart.lowerBound..<catalogueEnd.lowerBound]
var combos: [String: Int] = [:]
var scan = catalogue[...]
while let open = scan.range(of: "KeyCombo(") {
    var depth = 1
    var index = open.upperBound
    while index < scan.endIndex, depth > 0 {
        let character = scan[index]
        if character == "(" { depth += 1 }
        if character == ")" { depth -= 1 }
        if depth == 0 { break }
        index = scan.index(after: index)
    }
    let args = scan[open.upperBound..<index]
    if !args.hasPrefix("String(") {
        let key = args.first.map { _ in
            let quoted = args.drop(while: { $0 != "\"" }).dropFirst()
            return String(quoted.prefix(while: { $0 != "\"" }))
        } ?? ""
        let command = !args.contains("command: false")
        let shift = args.contains("shift: true")
        let option = args.contains("option: true")
        let control = args.contains("control: true")
        let name = "\(key) cmd=\(command) shift=\(shift) opt=\(option) ctrl=\(control)"
        combos[name, default: 0] += 1
    }
    scan = scan[scan.index(after: index)...]
}
let shared = combos.filter { $0.value > 1 }.map(\.key).sorted()
expect(shared.isEmpty, "no two commands share a shortcut\(shared.isEmpty ? "" : ": \(shared.joined(separator: ", "))")")
expect(combos["[ cmd=false shift=true opt=false ctrl=true"] == 1, "Collapse All Groups is ⌃⇧[")
expect(combos["] cmd=false shift=true opt=false ctrl=true"] == 1, "Expand All Groups is ⌃⇧]")
expect(combos["[ cmd=true shift=false opt=true ctrl=false"] == 1, "Fold All Groups keeps ⌥⌘[")
expect(combos["] cmd=true shift=false opt=true ctrl=false"] == 1, "Unfold All Groups keeps ⌥⌘]")

if failures > 0 { exit(1) }
print("Domain group regressions passed.")
