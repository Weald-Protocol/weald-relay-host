import Foundation

/// Which relay version to run.
///
/// The published image carries release tags (`wealdrelay-v0.1.5`) and no moving
/// `latest`, on purpose: a relay's digest is what verification compares against
/// release provenance, so a tag that silently changes underneath an operator
/// would defeat the point. That leaves this app to resolve the newest release
/// itself, which it does anonymously, and to fall back to a pin when it cannot.
enum Registry {
    static let repository = "weald-protocol/wealdrelay"

    /// Used when the registry is unreachable. Bump with releases.
    static let fallbackTag = "wealdrelay-v0.1.5"

    /// The newest `wealdrelay-vX.Y.Z` tag, by version order rather than by the
    /// registry's listing order, which is not specified to be sorted.
    static func newestTag() async -> String? {
        guard let token = await pullToken() else { return nil }
        var request = URLRequest(
            url: URL(string: "https://ghcr.io/v2/\(repository)/tags/list")!
        )
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = body["tags"] as? [String]
        else { return nil }

        return tags
            .compactMap { tag -> (String, [Int])? in
                guard tag.hasPrefix("wealdrelay-v"), !tag.hasSuffix(".sig") else { return nil }
                let parts = tag.dropFirst("wealdrelay-v".count)
                    .split(separator: ".")
                    .compactMap { Int($0) }
                return parts.count == 3 ? (tag, parts) : nil
            }
            .max { a, b in
                for (x, y) in zip(a.1, b.1) where x != y { return x < y }
                return false
            }?
            .0
    }

    private static func pullToken() async -> String? {
        var request = URLRequest(url: URL(
            string: "https://ghcr.io/token?scope=repository:\(repository):pull&service=ghcr.io"
        )!)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return body["token"] as? String
    }
}
