import Foundation

enum Registrable {
    static func domain(of host: String, isSuffix: ((String) -> Bool)?) -> String {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = name.split(separator: ".").map(String.init)
        let address = name.contains(":") || labels.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        guard let isSuffix, !address, labels.count > 1, !isSuffix(name) else { return name }
        for count in stride(from: labels.count - 1, through: 1, by: -1)
        where isSuffix(labels.suffix(count).joined(separator: ".")) {
            return labels.suffix(count + 1).joined(separator: ".")
        }
        return name
    }

    /// The name in front of the public suffix. google.com, google.de and
    /// mail.google.co.uk are all "google"; foo.github.io stays "foo", apart
    /// from bar.github.io. An address, localhost, or a host whose suffix
    /// can't be told stays whole, so nothing is guessed off the front of it.
    static func label(of host: String, isSuffix: ((String) -> Bool)?) -> String {
        let site = domain(of: host, isSuffix: isSuffix)
        guard let isSuffix else { return site }
        let labels = site.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return site }
        // Longest suffix first: co.uk, not uk, and github.io, not io.
        for count in stride(from: labels.count - 1, through: 1, by: -1)
        where isSuffix(labels.suffix(count).joined(separator: ".")) {
            guard let name = labels.dropLast(count).last, !name.isEmpty else { return site }
            return name
        }
        return site
    }

    /// Whether two hosts are one site: the same host, or the same
    /// registrable domain (idmsa.apple.com and account.apple.com). Never for
    /// an address, nor when the domain couldn't be worked out.
    static func sameSite(_ one: String, _ other: String, isSuffix: ((String) -> Bool)?) -> Bool {
        let a = one.lowercased(), b = other.lowercased()
        if a == b { return true }
        let left = domain(of: a, isSuffix: isSuffix)
        return left.contains(".") && left == domain(of: b, isSuffix: isSuffix)
    }
}
