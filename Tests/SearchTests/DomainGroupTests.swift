import XCTest
@testable import Search

/// Which site a tab belongs to, and how those tabs gather into the groups
/// the row already has. No window: the rules are pure.
final class DomainGroupTests: XCTestCase {
    private let suffix: (String) -> Bool = { name in
        ["com", "org", "net", "io", "co.uk", "com.au", "github.io"].contains(name)
    }

    private func registrable(_ host: String) -> String {
        Registrable.domain(of: host, isSuffix: suffix)
    }

    private func key(_ text: String) -> String? {
        DomainGroups.key(of: URL(string: text), registrable: registrable)
    }

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!
    }

    private func tab(_ n: Int, _ text: String?, group: Int? = nil) -> DomainGroups.Tab {
        DomainGroups.Tab(id: id(n), key: text.flatMap(key), groupID: group.map(id))
    }

    private func loose(_ n: Int, _ site: String?) -> DomainGroups.Tab {
        DomainGroups.Tab(id: id(n), key: site, groupID: nil)
    }

    func testRegistrableDomain() {
        XCTAssertEqual(registrable("docs.google.com"), "google.com")
        XCTAssertEqual(registrable("mail.google.com"), "google.com")
        XCTAssertEqual(registrable("gist.github.com"), "github.com")
        XCTAssertEqual(registrable("www.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(registrable("foo.github.io"), "foo.github.io")
        XCTAssertEqual(registrable("bar.github.io"), "bar.github.io")
        XCTAssertNotEqual(registrable("foo.github.io"), registrable("bar.github.io"))
        XCTAssertEqual(registrable("192.168.1.20"), "192.168.1.20")
        XCTAssertEqual(registrable("localhost"), "localhost")
        XCTAssertEqual(registrable("::1"), "::1")
        XCTAssertEqual(registrable("a.example.com"), "example.com")
        XCTAssertEqual(Registrable.domain(of: "a.example.com", isSuffix: nil), "a.example.com")
    }

    func testKeys() {
        XCTAssertEqual(key("https://docs.google.com/document/d/1"), "google.com")
        XCTAssertEqual(key("https://mail.google.com/mail"), "google.com")
        XCTAssertEqual(key("https://www.GitHub.com/search"), "github.com")
        XCTAssertEqual(key("https://github.com."), "github.com")
        XCTAssertEqual(key("https://gist.github.com/a"), "github.com")
        XCTAssertEqual(key("https://www.bbc.co.uk/news"), "bbc.co.uk")
        XCTAssertEqual(key("https://foo.github.io/page"), "foo.github.io")
        XCTAssertNotEqual(key("https://foo.github.io/"), key("https://bar.github.io/"))
        XCTAssertEqual(key("http://192.168.1.20:8080/admin"), "192.168.1.20")
        XCTAssertEqual(key("http://10.0.0.1/"), "10.0.0.1")
        XCTAssertNotEqual(key("http://10.0.0.1/"), key("http://10.0.0.2/"))
        XCTAssertEqual(key("http://localhost:3000/"), "localhost")
        XCTAssertEqual(key("http://localhost:8080/app"), "localhost")
        XCTAssertEqual(key("http://[::1]/"), "::1")
        XCTAssertEqual(key("file:///Users/me/notes.html"), "file")
        XCTAssertEqual(key("file:///tmp/a.pdf"), "file")
        XCTAssertNil(key("search://settings"))
        XCTAssertNil(key("about:blank"))
        XCTAssertNil(key("https://"))
    }

    func testTitles() {
        XCTAssertEqual(DomainGroups.title(for: "github.com"), "GitHub")
        XCTAssertEqual(DomainGroups.title(for: "google.com"), "Google")
        XCTAssertEqual(DomainGroups.title(for: "youtube.com"), "YouTube")
        XCTAssertEqual(DomainGroups.title(for: "bbc.co.uk"), "BBC")
        XCTAssertEqual(DomainGroups.title(for: "localhost"), "Localhost")
        XCTAssertEqual(DomainGroups.title(for: "file"), "Files")
        XCTAssertEqual(DomainGroups.title(for: "192.168.1.20"), "192.168.1.20")
        XCTAssertEqual(DomainGroups.title(for: "::1"), "::1")
        let collided = DomainGroups.titles(for: ["apple.com", "apple.org"])
        XCTAssertEqual(collided["apple.com"], "apple.com")
        XCTAssertEqual(collided["apple.org"], "apple.org")
        XCTAssertEqual(DomainGroups.titles(for: ["github.com"])["github.com"], "GitHub")
    }

    func testPairStaysTogetherOnlyOnOneSite() {
        XCTAssertEqual(DomainGroups.pairKeys("google.com", "google.com").0, "google.com")
        XCTAssertEqual(DomainGroups.pairKeys("google.com", "google.com").1, "google.com")
        XCTAssertNil(DomainGroups.pairKeys("google.com", "github.com").0)
        XCTAssertNil(DomainGroups.pairKeys("google.com", "github.com").1)
        XCTAssertNil(DomainGroups.pairKeys("google.com", nil).0)
        XCTAssertNil(DomainGroups.pairKeys(nil, nil).0)
    }

    func testGroupsByFirstSightAndLeavesSingletons() {
        let tabs = [
            tab(1, "https://docs.google.com/a"),
            tab(2, "https://github.com/a"),
            tab(3, "https://mail.google.com/b"),
            tab(4, "https://example.com/"),
            tab(5, "https://gist.github.com/b"),
        ]
        let ops = DomainGroups.plan(tabs: tabs, groups: [])
        XCTAssertEqual(ops, [
            .create(domain: "google.com", title: "Google", ids: [id(1), id(3)]),
            .create(domain: "github.com", title: "GitHub", ids: [id(2), id(5)]),
        ])
    }

    func testFilesLocalhostAndAddresses() {
        let tabs = [
            tab(1, "file:///tmp/a.pdf"),
            tab(2, "http://localhost:3000/"),
            tab(3, "file:///tmp/b.pdf"),
            tab(4, "http://localhost:8080/"),
            tab(5, "http://192.168.1.20/"),
            tab(6, "http://192.168.1.20:9/"),
            tab(7, "http://10.0.0.1/"),
            tab(8, "about:blank"),
        ]
        XCTAssertEqual(DomainGroups.plan(tabs: tabs, groups: []), [
            .create(domain: "file", title: "Files", ids: [id(1), id(3)]),
            .create(domain: "localhost", title: "Localhost", ids: [id(2), id(4)]),
            .create(domain: "192.168.1.20", title: "192.168.1.20", ids: [id(5), id(6)]),
        ])
    }

    func testPinsPrivateAndHandMadeGroupsStay() {
        let pinned = DomainGroups.Tab(id: id(1), key: nil, groupID: nil)
        let shy = DomainGroups.Tab(id: id(2), key: nil, groupID: nil)
        let held = DomainGroups.Tab(id: id(3), key: "github.com", groupID: id(9))
        let loose = loose(4, "github.com")
        let work = DomainGroups.Group(id: id(9), name: "Work", domain: nil)
        XCTAssertEqual(DomainGroups.plan(tabs: [pinned, shy, held, loose], groups: [work]), [])
    }

    func testJoinsAGroupAlreadyNamedForTheSite() {
        let github = DomainGroups.Group(id: id(9), name: "GitHub", domain: nil)
        let tabs = [
            DomainGroups.Tab(id: id(1), key: "github.com", groupID: id(9)),
            loose(2, "github.com"),
            loose(3, "github.com"),
        ]
        XCTAssertEqual(DomainGroups.plan(tabs: tabs, groups: [github]), [
            .join(group: id(9), domain: "github.com", ids: [id(2), id(3)]),
        ])
        let again = [
            DomainGroups.Tab(id: id(1), key: "github.com", groupID: id(9)),
            DomainGroups.Tab(id: id(2), key: "github.com", groupID: id(9)),
        ]
        let adopted = DomainGroups.Group(id: id(9), name: "Code", domain: "github.com")
        XCTAssertTrue(DomainGroups.plan(tabs: again, groups: [adopted]).isEmpty)
        XCTAssertEqual(DomainGroups.plan(tabs: again + [loose(3, "github.com")], groups: [adopted]), [
            .join(group: id(9), domain: "github.com", ids: [id(3)]),
        ])
    }

    func testOneTabAlreadyGroupedDoesNotMakeASecondGroup() {
        let named = DomainGroups.Group(id: id(9), name: "github.com", domain: nil)
        let tabs = [
            DomainGroups.Tab(id: id(1), key: "github.com", groupID: id(9)),
            loose(2, "github.com"),
        ]
        XCTAssertEqual(DomainGroups.plan(tabs: tabs, groups: [named]), [
            .join(group: id(9), domain: "github.com", ids: [id(2)]),
        ])
    }

    func testSeparateSitesWhoseNamesWouldCollide() {
        let tabs = [
            loose(1, "apple.com"), loose(2, "apple.com"),
            loose(3, "apple.org"), loose(4, "apple.org"),
        ]
        XCTAssertEqual(DomainGroups.plan(tabs: tabs, groups: []), [
            .create(domain: "apple.com", title: "apple.com", ids: [id(1), id(2)]),
            .create(domain: "apple.org", title: "apple.org", ids: [id(3), id(4)]),
        ])
    }

    func testASavedGroupKeepsItsSiteAndSurvivesWithoutOne() throws {
        let id = id(1)
        let group = TabGroup(id: id, name: "GitHub", collapsed: true, domain: "github.com")
        let data = try JSONEncoder().encode(group)
        let back = try JSONDecoder().decode(TabGroup.self, from: data)
        XCTAssertEqual(back, group)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("github.com"))

        let older = """
        {"id":"\(id.uuidString)","name":"Work","collapsed":false}
        """.data(using: .utf8)!
        let plain = try JSONDecoder().decode(TabGroup.self, from: older)
        XCTAssertEqual(plain.name, "Work")
        XCTAssertFalse(plain.collapsed)
        XCTAssertNil(plain.domain)

        let folded = """
        {"id":"\(id.uuidString)","name":"Work"}
        """.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(TabGroup.self, from: folded).collapsed)
    }
}
