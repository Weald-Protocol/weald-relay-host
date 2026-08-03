import SwiftUI

/// Black surface, white mark, nothing else. One place so no view invents a colour.
enum Theme {
    static let surface = Color.black
    static let ink = Color.white
    static let dim = Color.white.opacity(0.45)
    static let faint = Color.white.opacity(0.18)
    static let hairline = Color.white.opacity(0.10)
    static let field = Color.white.opacity(0.06)

    static let live = Color(red: 0.42, green: 0.94, blue: 0.60)
    static let busy = Color(red: 0.98, green: 0.80, blue: 0.34)
    static let down = Color.white.opacity(0.28)
    static let bad = Color(red: 0.98, green: 0.42, blue: 0.42)

    static let wordmark = Font.system(size: 13, weight: .semibold, design: .default)
    static let label = Font.system(size: 10, weight: .semibold, design: .default)
    static let body = Font.system(size: 12, weight: .regular, design: .default)
    static let mono = Font.system(size: 11.5, weight: .medium, design: .monospaced)
}

/// The wordmark: WEALD, letterspaced, in white. No image asset to go stale.
struct Wordmark: View {
    var body: some View {
        Text("WEALD")
            .font(Theme.wordmark)
            .tracking(3.2)
            .foregroundStyle(Theme.ink)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.label)
            .tracking(1.4)
            .foregroundStyle(Theme.dim)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}
