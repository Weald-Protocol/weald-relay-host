import SwiftUI
import AppKit

/// The whole interface. One screen, no tabs, no window.
struct PanelView: View {
    @Bindable var host: RelayHost
    var onQuit: () -> Void

    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Hairline()
            status
            Hairline()
            addresses
            if host.inviteLink != nil {
                Hairline()
                firstDevice
            }
            if showSettings {
                Hairline()
                settings
            }
            Hairline()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 8) {
            Wordmark()
            Text("RELAY HOST")
                .font(Theme.label)
                .tracking(1.6)
                .foregroundStyle(Theme.dim)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.14)) { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "chevron.up" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: status

    private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if host.phase == .running {
                    Text("PORT \(host.port)")
                        .font(Theme.label)
                        .tracking(1.2)
                        .foregroundStyle(Theme.dim)
                }
            }
            if case .failed(let why) = host.phase {
                Text(why)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action
        }
    }

    @ViewBuilder
    private var action: some View {
        switch host.phase {
        case .needsRuntime:
            PrimaryButton(title: "Install Docker") {
                NSWorkspace.shared.open(URL(string: "https://www.docker.com/products/docker-desktop/")!)
            }
        case .stopped:
            PrimaryButton(title: "Start relay") { host.start() }
        case .starting:
            PrimaryButton(title: "Starting", filled: false, enabled: false) {}
        case .stopping:
            PrimaryButton(title: "Stopping", filled: false, enabled: false) {}
        case .running:
            PrimaryButton(title: "Stop relay", filled: false) { host.stop() }
        case .failed:
            PrimaryButton(title: "Try again") { host.start() }
        }
    }

    private var statusText: String {
        switch host.phase {
        case .needsRuntime: return "Docker required"
        case .stopped: return "Not running"
        case .starting: return "Starting the relay"
        case .stopping: return "Stopping"
        case .running:
            if case .open = host.door { return "Serving over the tunnel" }
            if case .opening = host.door { return "Serving, opening the door" }
            return "Serving on this Mac"
        case .failed: return "Could not start"
        }
    }

    private var dotColor: Color {
        switch host.phase {
        case .running: return Theme.live
        case .starting, .stopping: return Theme.busy
        case .failed: return Theme.bad
        default: return Theme.down
        }
    }

    // MARK: the two addresses, which are the reason the app exists

    private var addresses: some View {
        VStack(alignment: .leading, spacing: 12) {
            CopyRow(
                title: "This Mac",
                value: host.phase == .running ? host.localURL : nil,
                caption: "Paste into a Weald project's relay field.",
                placeholder: "start the relay to get a URL"
            )
            PublicAddress(host: host)
        }
    }

    /// Shown only while the workspace has no members. The first device to open the
    /// link becomes the trust root, and the code cannot be reprinted.
    private var firstDevice: some View {
        VStack(alignment: .leading, spacing: 12) {
            CopyRow(
                title: "First device link",
                value: host.inviteLink,
                caption: "Open once, from the Mac app. It becomes the workspace owner."
            )
            if let code = host.inviteCode {
                CopyRow(
                    title: "One-time code",
                    value: code,
                    caption: "Save it now. It is never shown again."
                )
            }
        }
    }

    // MARK: settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionLabel(text: "Port")
                Spacer()
                TextField("54040", value: $host.port, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .font(Theme.mono)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
            }
            Field(label: "Image tag", placeholder: "auto", text: $host.tag)
            if host.tag == "auto" {
                Text("auto runs the newest release: \(host.resolvedTag)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }
            Hairline()
            PublicAccessSettings(host: host)
            Hairline()
            Toggle(isOn: $host.launchAtLogin) {
                Text("Start at login")
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(.switch)
            .tint(Theme.ink)
            HStack(spacing: 14) {
                QuietButton(title: "Apply and restart") { host.restart() }
                QuietButton(title: "Erase stored data") { host.erase() }
            }
            Text("Erasing removes the relay's database and blobs. Everything it holds is ciphertext it cannot read.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            QuietButton(title: "Getting started") {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/Weald-Protocol/weald-relay-host#readme")!
                )
            }
            Spacer()
            QuietButton(title: "Quit", action: onQuit)
        }
    }
}
