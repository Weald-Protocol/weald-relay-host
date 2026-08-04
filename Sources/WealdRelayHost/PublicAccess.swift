import SwiftUI
import AppKit

/// The public address row, and the one button that makes it real.
///
/// Two rows would be a lie here. Before a tunnel there is an IP that will not
/// connect, and after one there is a `wss://` URL that will, and the row's job
/// is to say which of those the operator is looking at without a paragraph.
struct PublicAddress: View {
    @Bindable var host: RelayHost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CopyRow(
                title: "Public address",
                value: host.publicURL,
                caption: caption,
                placeholder: placeholder
            )
            if case .failed(let why) = host.door {
                Text(why)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if host.tunnelMode == .off, host.phase == .running {
                PrimaryButton(title: "Open a public door", filled: false) {
                    host.setTunnel(.quick)
                }
                Text("Starts a Cloudflare tunnel in the stack. No router change, no certificate, no account.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var caption: String {
        switch host.door {
        case .open where host.tunnelMode == .quick:
            return "TLS by Cloudflare. This hostname changes at the next start."
        case .open:
            return "TLS by Cloudflare. Anyone with this URL can reach your relay."
        case .opening:
            return "Waiting for the tunnel to be accepted."
        default:
            return "Your IP, for people off this Mac. Plaintext, so a client refuses it."
        }
    }

    private var placeholder: String {
        switch host.door {
        case .opening: return "opening the tunnel"
        default: return "looking up your IP"
        }
    }
}

/// The front door's settings: which kind, and the two fields the second kind
/// needs. Hidden behind the same disclosure as the rest of Settings, because a
/// relay serving one Mac never needs to see any of it.
struct PublicAccessSettings: View {
    @Bindable var host: RelayHost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionLabel(text: "Public access")
                Spacer()
                Picker("", selection: binding) {
                    ForEach(Tunnel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            switch host.tunnelMode {
            case .off:
                note("This Mac only. The relay is not reachable from anywhere else.")
            case .quick:
                note("A throwaway hostname from Cloudflare, minted at every start. Nothing to configure, and nothing that survives a restart.")
            case .named:
                Field(
                    label: "Hostname", placeholder: "relay.example.com", width: 150,
                    text: $host.tunnelHostname
                )
                SecureField("Cloudflare tunnel token", text: $host.tunnelToken)
                    .textFieldStyle(.plain)
                    .font(Theme.mono)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
                note("Create a tunnel in Cloudflare Zero Trust, point its public hostname at http://relay:\(host.port), and paste the token. Held in your login keychain, and the hostname then survives every restart.")
                QuietButton(title: "Open Cloudflare Zero Trust") {
                    NSWorkspace.shared.open(URL(string: "https://one.dash.cloudflare.com")!)
                }
            }
        }
    }

    /// Changing the mode restarts the stack, because the tunnel is a container
    /// in it. Doing that here rather than waiting for Apply is the difference
    /// between a button and a setting.
    private var binding: Binding<Tunnel.Mode> {
        Binding(get: { host.tunnelMode }, set: { host.setTunnel($0) })
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A labelled single-line field, so the three settings that have one look alike.
struct Field: View {
    let label: String
    let placeholder: String
    var width: CGFloat = 130
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            SectionLabel(text: label)
            Spacer()
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.mono)
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
        }
    }
}
