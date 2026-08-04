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

    /// What the front door is doing, as distinct from what the relay is doing.
    /// A tunnel can be down while the relay is perfectly healthy, and saying so
    /// is more useful than folding both into one dot.
    enum Door: Equatable {
        case closed
        case opening
        case open(String)          // the hostname the outside world uses
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

    /// The front door, off by default: a relay that nobody asked to publish is
    /// not published.
    var tunnelMode: Tunnel.Mode {
        didSet { UserDefaults.standard.set(tunnelMode.rawValue, forKey: "tunnelMode") }
    }
    /// The hostname a named tunnel answers on. Cloudflare owns it, this app is
    /// only told about it, which is why it is typed rather than discovered.
    var tunnelHostname: String {
        didSet {
            UserDefaults.standard.set(
                tunnelHostname.trimmingCharacters(in: .whitespaces), forKey: "tunnelHostname"
            )
        }
    }
    /// Keychain-backed. The setter writes through so a token pasted into the
    /// panel survives a quit without ever landing in a plist.
    var tunnelToken: String {
        didSet { Tunnel.Token.save(tunnelToken.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    let retentionDays = 30
    let maxStorageGB = 50

    // MARK: observed state

    private(set) var phase: Phase = .stopped
    private(set) var door: Door = .closed
    private(set) var publicIP: String?
    private(set) var lastLog: String = ""

    /// The bootstrap invite the relay prints while its workspace has no members.
    /// The first device to open the link becomes the trust root, so this is the
    /// one thing a self-hoster needs beyond the socket URL. Only the token is
    /// kept: the link is rebuilt from wherever the relay is currently reachable,
    /// so opening a tunnel fixes an already-minted link instead of stranding it.
    private(set) var inviteToken: String?
    private(set) var inviteCode: String?

    var localURL: String { "ws://127.0.0.1:\(port)/relay" }

    /// The address to hand somebody else. A tunnel makes this a real `wss://`
    /// URL that works; without one it is the raw IP, which is shown because it
    /// is the truth about where this Mac lives and not because it will connect.
    var publicURL: String? {
        if case .open(let host) = door { return "wss://\(host)/relay" }
        return publicIP.map { "ws://\($0):\(port)/relay" }
    }

    /// Whether `publicURL` is something a Weald client will actually accept.
    var publicURLUsable: Bool {
        if case .open = door { return true }
        return false
    }

    var inviteLink: String? {
        guard let inviteToken else { return nil }
        if case .open(let host) = door { return "https://\(host)/join/\(inviteToken)" }
        return "http://127.0.0.1:\(port)/join/\(inviteToken)"
    }

    private var docker: String?
    private var poll: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        port = d.object(forKey: "port") as? Int ?? 54040
        tag = d.string(forKey: "tag") ?? "auto"
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        tunnelMode = Tunnel.Mode(rawValue: d.string(forKey: "tunnelMode") ?? "") ?? .off
        tunnelHostname = d.string(forKey: "tunnelHostname") ?? ""
        tunnelToken = Tunnel.Token.load()
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
            if inviteToken == nil { await loadInvite() }
            if tunnelMode != .off, !doorSettled { await loadDoor() }
            return
        }
        let up = await Task.detached { Docker.daemonUp(bin) }.value
        phase = up ? .stopped : .needsRuntime
    }

    private var doorSettled: Bool {
        switch door {
        case .open, .failed: return true
        case .closed, .opening: return false
        }
    }

    func start() {
        guard let bin = docker ?? Docker.locate() else { phase = .needsRuntime; return }
        docker = bin
        phase = .starting
        door = tunnelMode == .off ? .closed : .opening
        Task {
            if tag == "auto", let newest = await Registry.newestTag() {
                resolvedTag = newest
            }
            let plan = currentPlan()
            do {
                try Compose.write(plan)
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
                door = tunnelMode == .off ? .closed : .failed("The tunnel did not start.")
                return
            }
            // Migrations from zero run inside the binary, so first boot is slower
            // than a restart. Sixty seconds covers a cold image pull's tail too.
            for _ in 0..<60 {
                if await healthy() {
                    phase = .running
                    await loadInvite()
                    await openDoor()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            phase = .failed("The relay did not answer on port \(port).")
        }
    }

    private func currentPlan() -> Compose.Plan {
        let named = tunnelHostname.trimmingCharacters(in: .whitespaces)
        return Compose.Plan(
            port: port,
            tag: tag == "auto" ? resolvedTag : tag,
            retentionDays: retentionDays,
            maxStorageGB: maxStorageGB,
            tunnel: tunnelMode,
            // A quick tunnel is not told its hostname until after it connects, so
            // the relay keeps its loopback identity and the panel rewrites links.
            hostname: tunnelMode == .named && !named.isEmpty ? named : "localhost",
            tunnelToken: tunnelToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func stop() {
        guard let bin = docker else { return }
        phase = .stopping
        let file = Compose.file.path
        Task {
            let result = await Task.detached { Docker.run(bin, ["compose", "-f", file, "down"]) }.value
            lastLog = result.message
            door = .closed
            phase = result.ok ? .stopped : .failed(Self.explain(result.message))
            await refresh()
        }
    }

    func restart() {
        guard let bin = docker else { return }
        let file = Compose.file.path
        Task {
            phase = .stopping
            door = .closed
            _ = await Task.detached { Docker.run(bin, ["compose", "-f", file, "down"]) }.value
            start()
        }
    }

    /// Turn a public front door on or off in one gesture. The stack has to come
    /// down and back up because the tunnel is a container in it, so this is the
    /// button and the restart in one, rather than a setting the operator then
    /// has to remember to apply.
    func setTunnel(_ mode: Tunnel.Mode) {
        guard mode != tunnelMode else { return }
        tunnelMode = mode
        guard phase == .running || phase == .starting else {
            door = .closed
            return
        }
        restart()
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
            inviteToken = nil
            inviteCode = nil
            door = .closed
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

    /// Wait for the edge to accept the tunnel, then take the hostname from the
    /// daemon's own banner. Thirty seconds is generous: a quick tunnel is up in
    /// two or three, and the slow case is the first pull of the image.
    private func openDoor() async {
        guard tunnelMode != .off else { door = .closed; return }
        door = .opening
        for _ in 0..<30 {
            await loadDoor()
            if doorSettled { return }
            try? await Task.sleep(for: .seconds(1))
        }
        door = .failed("The tunnel did not come up. Check the log.")
    }

    /// Read the front door's state out of cloudflared's own output. It writes to
    /// stderr, so both streams are considered.
    func loadDoor() async {
        guard let bin = docker, tunnelMode != .off else { door = .closed; return }
        let file = Compose.file.path
        let text = await Task.detached {
            Docker.run(bin, ["compose", "-f", file, "logs", "--tail", "300", Tunnel.service])
                .combined
        }.value
        if let why = Tunnel.problem(in: text) {
            door = .failed(why)
            return
        }
        switch tunnelMode {
        case .off:
            door = .closed
        case .quick:
            if let host = Tunnel.quickHostname(in: text) { door = .open(host) }
        case .named:
            let named = tunnelHostname.trimmingCharacters(in: .whitespaces)
            if named.isEmpty {
                door = .failed("Add the hostname your Cloudflare tunnel answers on.")
            } else if Tunnel.registered(text) {
                door = .open(named)
            }
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
        // The link the relay prints is host-relative to its own hostname, so only
        // the token is kept and the address is supplied by whichever door is open.
        if let printed = Self.match(text, after: "invite link") {
            inviteToken = printed.split(separator: "/").last.map(String.init) ?? printed
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
