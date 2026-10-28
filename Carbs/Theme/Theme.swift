import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

enum Theme {
    static let primary = Color(hex: 0x3E98E3)
    static let protein = Color(hex: 0x3E98E3)
    static let carbs = Color(hex: 0xFF8E70)
    static let fat = Color(hex: 0x0EC0AB)
    static let error = Color(hex: 0xFF4E4E)
    static let good = Color(hex: 0x34C77B)

    static let background = Color(light: 0xEEF5FF, dark: 0x141B30)
    static let card = Color(light: 0xFFFFFF, dark: 0x1F2A44)
    static let cardBorder = Color(light: 0xD9E1E8, dark: 0x2A3554)
    static let text = Color(light: 0x242A48, dark: 0xF6F6F9)
    static let secondaryText = Color(light: 0x7E8294, dark: 0x9AA0B4)

    static let radius: CGFloat = 16
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.cardBorder, lineWidth: 0.5))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }

    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.primary.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4), in: Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Theme.card.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().stroke(Theme.cardBorder, lineWidth: 0.5))
    }
}

extension Font {
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

/// Four-column Cal / Protein / Carbs / Fat box with colored dots.
struct MacroStatBox: View {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var labels = true

    var body: some View {
        HStack(spacing: 0) {
            column(calories.rounded0, "Cal", nil)
            Divider().frame(height: 32)
            column(protein.rounded0, "Protein (g)", Theme.protein)
            Divider().frame(height: 32)
            column(carbs.rounded0, "Carbs (g)", Theme.carbs)
            Divider().frame(height: 32)
            column(fat.rounded0, "Fat (g)", Theme.fat)
        }
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 0.5))
    }

    private func column(_ value: String, _ label: String, _ color: Color?) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if let color { Capsule().fill(color).frame(width: 5, height: 11) }
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            }
            if labels { Text(label).font(.caption).foregroundStyle(Theme.secondaryText) }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A thin progress bar for remaining macros.
struct MacroBar: View {
    var value: Double
    var target: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let fraction = target > 0 ? min(1, value / target) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule().fill(value > target * 1.03 ? Theme.error : color).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 4)
    }
}

extension Double {
    var rounded0: String { String(Int(self.rounded())) }
    var rounded1: String { String(format: "%.1f", self) }
}
