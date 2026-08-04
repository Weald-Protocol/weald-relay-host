import Foundation
import Security

/// The public front door.
///
/// A relay on a laptop has two problems the panel cannot solve by asking nicely.
/// A Weald client refuses a plaintext socket to anything that is not literally
/// loopback, so `ws://` works on this Mac and nowhere else, and a home router
/// does not forward a port because you would like it to.
///
/// An outbound tunnel answers both at once. The daemon dials Cloudflare, so
/// nothing is forwarded, no port is opened and the Mac's address is never
/// published, and TLS terminates at the edge, so the URL is `wss://` without a
/// certificate, an ACME challenge or a DNS record ever touching this machine.
/// That is the whole reason this is a button rather than an afternoon.
enum Tunnel {
    /// How the front door is opened, ordered by how much the operator has to do.
    enum Mode: String, CaseIterable, Identifiable {
        /// No front door. This Mac only, which is the right answer for a relay
        /// that only ever serves the machine it runs on.
        case off
        /// A throwaway `*.trycloudflare.com` hostname. No account, no token, no
        /// configuration. A different hostname is minted at every start, which
        /// is the price of asking nobody for permission.
        case quick
        /// A tunnel the operator created in their own Cloudflare account, which
        /// keeps one hostname forever. Costs one token paste, once.
        case named

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "Off"
            case .quick: return "Quick"
            case .named: return "My tunnel"
            }
        }
    }

    /// The one image here that is deliberately not pinned. cloudflared is a
    /// client that dials out and holds nothing, the edge rejects builds that
    /// have fallen far enough behind, and a quick tunnel from a stale binary
    /// fails in a way that reads like a network fault.
    static let image = "cloudflare/cloudflared:latest"

    /// The compose service name, so the panel can read its log back.
    static let service = "tunnel"

    /// The hostname cloudflared prints in its banner once the edge has accepted
    /// the tunnel. The last one wins: a restart prints a new banner and the
    /// newest line is the tunnel that is actually up.
    static func quickHostname(in log: String) -> String? {
        var found: String?
        var rest = Substring(log)
        while let marker = rest.range(of: "https://") {
            let tail = rest[marker.upperBound...]
            let host = tail.prefix { character in
                !character.isWhitespace && character != "/" && character != "\""
                    && character != "|" && character != ","
            }
            if host.hasSuffix(".trycloudflare.com"), host.count > ".trycloudflare.com".count {
                found = String(host)
            }
            rest = tail
        }
        return found
    }

    /// A named tunnel prints no hostname, because the hostname lives in the
    /// operator's Cloudflare account rather than in this process. The edge
    /// accepting a connection is the only thing this side can observe.
    static func registered(_ log: String) -> Bool {
        log.contains("Registered tunnel connection")
    }

    /// The two token failures worth a sentence. Everything else is left to the
    /// raw log, because guessing at a third one would be worse than silence.
    static func problem(in log: String) -> String? {
        let text = log.lowercased()
        if text.contains("provided tunnel token is not valid")
            || text.contains("failed to parse token") {
            return "That tunnel token was not accepted. Copy it again from Cloudflare."
        }
        if text.contains("no such host") || text.contains("dial tcp") {
            return "cloudflared could not reach Cloudflare. Check the network."
        }
        return nil
    }

    /// The tunnel token, in the login keychain rather than in defaults or in the
    /// compose file, because it authenticates as the operator's Cloudflare
    /// account and the compose file is a world-readable regenerated artefact.
    enum Token {
        private static let service = "WealdRelayHost"
        private static let account = "cloudflare-tunnel-token"

        static func load() -> String {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data
            else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }

        static func save(_ value: String) {
            let identity: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(identity as CFDictionary)
            guard !value.isEmpty else { return }
            var item = identity
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
