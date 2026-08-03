import Foundation

/// Where the container runtime is found, and how it is run.
///
/// The relay is a Linux process that wants a Postgres beside it, so the honest
/// way to run it on a Mac is the published image plus a database in the same
/// compose project. That means one prerequisite for the user (Docker Desktop or
/// OrbStack) and nothing else to install, ever.
enum Docker {
    /// GUI apps do not inherit a login shell, so `docker` is looked for by path.
    static let searchPaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        "/Applications/OrbStack.app/Contents/MacOS/bin/docker",
        "/usr/bin/docker"
    ]

    static func locate() -> String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    struct Result {
        let status: Int32
        let out: String
        let err: String
        var ok: Bool { status == 0 }
        /// What to show a human: stderr if there is any, else stdout.
        var message: String {
            let e = err.trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? out.trimmingCharacters(in: .whitespacesAndNewlines) : e
        }
    }

    /// Run the runtime and wait. Called off the main actor.
    static func run(_ binary: String, _ args: [String], cwd: URL? = nil) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        // A pruned PATH still lets compose find its own plugins.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch {
            return Result(status: 127, out: "", err: error.localizedDescription)
        }
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(
            status: p.terminationStatus,
            out: String(decoding: out),
            err: String(decoding: err)
        )
    }

    /// Is the daemon actually up, as opposed to the CLI merely being installed.
    static func daemonUp(_ binary: String) -> Bool {
        run(binary, ["info", "--format", "{{.ServerVersion}}"]).ok
    }
}

private extension String {
    init(decoding data: Data) { self = String(data: data, encoding: .utf8) ?? "" }
}
