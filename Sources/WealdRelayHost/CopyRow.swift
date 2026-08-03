import SwiftUI
import AppKit

/// A URL and one gesture: click anywhere on the row to copy it.
///
/// The whole point of the app is the paste, so the paste is the biggest target
/// on the panel and there is no second step.
struct CopyRow: View {
    let title: String
    let value: String?
    var caption: String?
    var placeholder: String = "unavailable"

    @State private var copied = false
    @State private var hovering = false

    private var enabled: Bool { value != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: title)
                Spacer()
                Text(copied ? "COPIED" : (hovering && enabled ? "CLICK TO COPY" : ""))
                    .font(Theme.label)
                    .tracking(1.2)
                    .foregroundStyle(copied ? Theme.live : Theme.dim)
                    .animation(.easeOut(duration: 0.12), value: copied)
            }
            Text(value ?? placeholder)
                .font(Theme.mono)
                .foregroundStyle(enabled ? Theme.ink : Theme.dim)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering && enabled ? Theme.field.opacity(2) : Theme.field)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(copied ? Theme.live.opacity(0.7) : Theme.faint, lineWidth: 1)
                )
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { copy() }
    }

    private func copy() {
        guard let value else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }
}

/// The one wide button on the panel. White when it is the thing to do next.
struct PrimaryButton: View {
    let title: String
    var filled: Bool = true
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(filled ? Theme.surface : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(filled ? Theme.ink.opacity(hovering ? 0.88 : 1) : Theme.field)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(filled ? .clear : Theme.faint, lineWidth: 1)
                )
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

/// A quiet text action for the footer row.
struct QuietButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Theme.ink : Theme.dim)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
