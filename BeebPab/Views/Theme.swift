import AppKit
import SwiftUI

enum Theme {
    static let blue = Color(red: 0.149, green: 0.494, blue: 0.965)
    static let cyan = Color(red: 0.208, green: 0.737, blue: 0.957)
    static let green = Color(red: 0.204, green: 0.737, blue: 0.392)
    static let orange = Color(red: 0.976, green: 0.588, blue: 0.149)

    static let brandGradient = LinearGradient(colors: [blue, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func platformColor(_ id: String) -> Color {
        switch id {
        case "facebook": return Color(red: 0.094, green: 0.467, blue: 0.949)
        case "line": return Color(red: 0.024, green: 0.729, blue: 0.333)
        default: return blue
        }
    }

    static func platformSymbol(_ id: String) -> String {
        switch id {
        case "facebook": return "hand.thumbsup.fill"
        case "line": return "bubble.left.fill"
        default: return "globe"
        }
    }

    /// The preset's symbol if macOS knows it, otherwise a safe default.
    static func symbol(for target: OutputTarget) -> String {
        if let name = target.symbol, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return name }
        return "photo"
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

/// Rounded card with a soft shadow, used for every panel.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
            )
    }
}

extension View {
    func card(cornerRadius: CGFloat = 12) -> some View { modifier(CardBackground(cornerRadius: cornerRadius)) }
}

/// Colored tile holding an SF Symbol.
struct IconTile: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 28
    var filled = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(filled ? .white : color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(filled ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14)))
            )
    }
}

struct StepHeader: View {
    var number: Int
    var title: String
    var symbol: String
    var isComplete = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(isComplete ? AnyShapeStyle(Theme.green.gradient) : AnyShapeStyle(Theme.brandGradient))
                if isComplete {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            Image(systemName: symbol).foregroundStyle(Theme.blue)
            Text(title).font(.headline)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
            )
            .shadow(color: isEnabled ? Theme.blue.opacity(0.35) : .clear, radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Chip: View {
    var text: String
    var color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}
