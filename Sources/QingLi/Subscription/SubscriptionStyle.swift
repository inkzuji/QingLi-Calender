import SwiftUI
import QingLiCore

struct SubscriptionFeedback: View {
    let feedback: HolidayDataController.Feedback
    let palette: SubscriptionPalette

    var body: some View {
        Text(feedback.text)
            .font(.system(size: 12))
            .foregroundStyle(colors.ink)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: 8))
    }

    private var colors: (ink: Color, fill: Color) {
        switch feedback.kind {
        case .information: (palette.infoInk, palette.infoBackground)
        case .success: (palette.successInk, palette.successBackground)
        case .failure: (palette.errorInk, palette.errorBackground)
        }
    }
}

struct SubscriptionButtonStyle: ButtonStyle {
    let palette: SubscriptionPalette
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? .white : palette.base.ink)
            .padding(.horizontal, 15)
            .frame(height: 39)
            .contentShape(Rectangle())
            .subscriptionPanel(
                fill: fill(isPressed: configuration.isPressed),
                line: isPrimary ? .clear : palette.line,
                radius: 8
            )
            .shadow(color: isPrimary ? palette.base.blue.opacity(0.13) : .clear, radius: 2, y: 2)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }

    private func fill(isPressed: Bool) -> Color {
        let active = isEnabled && (isHovered || isPressed)
        if isPrimary { return active ? Color(subscriptionRGB: 0x0054dc) : Color(subscriptionRGB: 0x0865f7) }
        return active ? palette.infoBackground : palette.surface
    }
}

struct SubscriptionPalette {
    let base: QingLiPalette
    private let isDark: Bool

    init(colorScheme: ColorScheme) {
        base = QingLiPalette(colorScheme: colorScheme)
        isDark = colorScheme == .dark
    }

    var surface: Color { color(0xffffff, dark: 0x222c38) }
    var line: Color { isDark ? base.line : Color(subscriptionRGB: 0xdce5ee) }
    var segment: Color { color(0xe9eef4, dark: 0x171e27) }
    var footer: Color { color(0xf3f7fb, dark: 0x242e3b) }
    var previewBackground: Color { color(0xf0f5fb, dark: 0x1d2d41) }
    var selectedYear: Color { color(0xf0f6ff, dark: 0x243a58) }
    var infoBackground: Color { color(0xedf4ff, dark: 0x293d57) }
    var infoInk: Color { color(0x295487, dark: 0xb0d0f8) }
    var successBackground: Color { color(0xe6f3ee, dark: 0x253f38) }
    var successInk: Color { color(0x28755c, dark: 0x9dd9c4) }
    var errorBackground: Color { color(0xfff0ed, dark: 0x54322f) }
    var errorInk: Color { color(0xa44936, dark: 0xf1b6ad) }
    var warningBackground: Color { color(0xfff3dc, dark: 0x473c28) }
    var warningInk: Color { color(0x996e22, dark: 0xeac689) }

    private func color(_ light: UInt32, dark: UInt32) -> Color {
        Color(subscriptionRGB: isDark ? dark : light)
    }
}

extension Color {
    init(subscriptionRGB rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255
        )
    }
}

extension View {
    func subscriptionPanel(fill: Color, line: Color, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return background(fill, in: shape)
            .overlay { shape.strokeBorder(line, lineWidth: 1).allowsHitTesting(false) }
    }
}

func displaySubscriptionDate(_ date: Date) -> String {
    date.formatted(
        Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)/\(month: .twoDigits)/\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: Locale(identifier: "zh_CN"),
            timeZone: .autoupdatingCurrent,
            calendar: .qingLiGregorian
        )
    )
}
