import Foundation
import Observation

/// Everything the panel shows and every action it can take.
@MainActor
@Observable
final class RelayHost {
    enum Phase: Equatable {
        case needsRuntime          // no docker binary, or the daemon is asleep
        case stopped
        case starting
        case running
        case stopping
        case failed(String)
    }

    // MARK: settings, persisted so a restart comes back the same

    var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "port") }
    }
    /// `auto` means the newest published release, resolved at start. Anything
    /// else is a pin the operator typed and this app never overwrites.
    var tag: String {
        didSet { UserDefaults.standard.set(tag, forKey: "tag") }
    }
    private(set) var resolvedTag = Registry.fallbackTag
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            LoginItem.set(launchAtLogin)
        }
    }

    let retentionDays = 30
    let maxStorageGB = 50

    // MARK: observed state

    private(set) var phase: Phase = .stopped
    private(set) var publicIP: String?
    private(set) var lastLog: String = ""

    /// The bootstrap invite the relay prints while its workspace has no members.
    /// The first device to open the link becomes the trust root, so this is the
    /// one thing a self-hoster needs beyond the socket URL.
    private(set) var inviteLink: String?
    private(set) var inviteCode: String?

    var localURL: String { "ws://127.0.0.1:\(port)/relay" }
    var publicURL: String? { publicIP.map { "ws://\($0):\(port)/relay" } }

    private var docker: String?
    private var poll: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        port = d.object(forKey: "port") as? Int ?? 54040
        tag = d.string(forKey: "tag") ?? "auto"
        launchAtLogin = d.bool(forKey: "launchAtLogin")
    }

    // MARK: lifecycle

    func begin() {
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        Task { await loadPublicIP() }
    }

    func end() { poll?.cancel() }

    /// One truth: the socket answers or it does not. Container bookkeeping is not
    /// consulted, because a container that is up and a relay that is serving are
    /// different claims and only the second one is useful.
    func refresh() async {
        if docker == nil { docker = Docker.locate() }
        guard let bin = docker else {
            phase = .needsRuntime
            return
        }
        switch phase {
        case .starting, .stopping:
            return                      // a command owns the state until it returns
        default:
            break
        }
        if await healthy() {
            phase = .running
            if inviteLink == nil { await loadInvite() }
            return
        }
        let up = await Task.detached { Docker.daemonUp(bin) }.value
        phase = up ? .stopped : .needsRuntime
    }

    func start() {
        guard let bin = docker ?? Docker.locate() else { phase = .needsRuntime; return }
        docker = bin
        phase = .starting
        Task {
            if tag == "auto", let newest = await Registry.newestTag() {
                resolvedTag = newest
            }
            let port = port, tag = tag == "auto" ? resolvedTag : tag
            let retention = retentionDays, storage = maxStorageGB
            do {
                try Compose.write(
                    port: port, tag: tag,
                    retentionDays: retention, maxStorageGB: storage
                )
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            let file = Compose.file.path
            let result = await Task.detached {
                Docker.run(bin, ["compose", "-f", file, "up", "-d", "--pull", "missing"])
            }.value
            lastLog = result.message
            guard result.ok else {
                phase = .failed(Self.explain(result.message))
                return
            }
            // Migrations from zero run inside the binary, so first boot is slower
            // than a restart. Sixty seconds covers a cold image pull's tail too.
            for _ in 0..<60 {
                if await healthy() {
                    phase = .running
                    await loadInvite()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            phase = .failed("The relay did not answer on port \(port).")
        }
    }

    func stop() {
        guard let bin = docker else { return }
        phase = .stopping
        let file = Compose.file.path
        Task {
            let result = await Task.detached { Docker.run(bin, ["compose", "-f", file, "down"]) }.value
            lastLog = result.message
            phase = result.ok ? .stopped : .failed(Self.explain(result.message))
            await refresh()
        }
    }

    func restart() {
        guard let bin = docker else { return }
        let file = Compose.file.path
        Task {
            phase = .stopping
            _ = await Task.detached { Docker.run(bin, ["compose", "-f", file, "down"]) }.value
            start()
        }
    }

    /// Stop and delete both volumes. Everything the relay holds is ciphertext it
    /// cannot read, so this destroys undelivered envelopes and nothing else.
    func erase() {
        guard let bin = docker else { return }
        phase = .stopping
        let file = Compose.file.path
        Task {
            let result = await Task.detached {
                Docker.run(bin, ["compose", "-f", file, "down", "--volumes"])
            }.value
            lastLog = result.message
            inviteLink = nil
            inviteCode = nil
            phase = .stopped
            await refresh()
        }
    }

    // MARK: probes

    private func healthy() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/healthz")!)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Read the bootstrap invite back out of the relay's own stdout.
    ///
    /// The relay reprints the link on every start while the workspace is still
    /// empty and stops once it is redeemed, so an absent link here means the
    /// workspace already has a trust root. The code is printed only at mint and
    /// is not recoverable, which is why it is read from the log rather than asked
    /// for: there is nowhere else it exists.
    func loadInvite() async {
        guard let bin = docker else { return }
        let file = Compose.file.path
        let text = await Task.detached {
            Docker.run(bin, ["compose", "-f", file, "logs", "--tail", "500", "relay"]).out
        }.value
        guard text.contains("this workspace") else { return }
        // The link is host-relative to the relay's own hostname, which is
        // `localhost` in this stack, so it is rewritten to the port in use.
        if let token = Self.match(text, after: "invite link") {
            let last = token.split(separator: "/").last.map(String.init) ?? token
            inviteLink = "http://127.0.0.1:\(port)/join/\(last)"
        }
        if let code = Self.match(text, after: "invite code") {
            inviteCode = code
        }
    }

    /// Last occurrence wins: a restart reprints the link, and the newest line is
    /// the one describing the database that is currently attached.
    private static func match(_ text: String, after label: String) -> String? {
        text.split(separator: "\n")
            .last { $0.contains(label) }
            .flatMap { line in
                line.range(of: label).map {
                    String(line[$0.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    func loadPublicIP() async {
        for source in ["https://api.ipify.org", "https://ifconfig.me/ip"] {
            var request = URLRequest(url: URL(string: source)!)
            request.timeoutInterval = 5
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty, text.count < 64 {
                publicIP = text
                return
            }
        }
    }

    /// Turn the two failures people actually hit into one sentence each.
    private static func explain(_ raw: String) -> String {
        let text = raw.lowercased()
        if text.contains("port is already allocated") || text.contains("address already in use") {
            return "That port is taken. Pick another in Settings."
        }
        if text.contains("cannot connect to the docker daemon") {
            return "Docker is not running. Open it and try again."
        }
        if text.contains("denied") || text.contains("unauthorized") {
            return "Could not pull the relay image. Check the network."
        }
        let line = raw.split(separator: "\n").last.map(String.init) ?? raw
        return line.isEmpty ? "The relay failed to start." : line
    }
}
