import AppKit
import SwiftUI
import QingLiCore

struct DesktopOutlineButtonStyle: ButtonStyle {
    let palette: DesktopPalette
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(hovering || configuration.isPressed ? palette.hover : palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.line) }
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }
}

struct DesktopHoverButtonStyle: ButtonStyle {
    let color: Color
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if hovering || configuration.isPressed {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.45)).allowsHitTesting(false)
                }
            }
            .onHover { hovering = $0 }
    }
}

struct DesktopPalette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }
    private var base: QingLiPalette { QingLiPalette(colorScheme: scheme) }
    var ink: Color { base.ink }
    var muted: Color { base.muted }
    var blue: Color { base.blue }
    var holiday: Color { dark ? base.holiday : Color(red: 197 / 255, green: 66 / 255, blue: 87 / 255) }
    var holidayBackground: Color { dark ? base.holidayBackground : Color(red: 1, green: 240 / 255, blue: 242 / 255) }
    var line: Color { dark ? base.line : Color(red: 220 / 255, green: 229 / 255, blue: 238 / 255) }
    var surface: Color { dark ? Color(nsColor: .windowBackgroundColor) : .white }
    var sidebar: Color { dark ? Color(nsColor: .underPageBackgroundColor) : Color(red: 246 / 255, green: 247 / 255, blue: 249 / 255) }
    var sidebarSelection: Color { dark ? base.hover : Color(red: 232 / 255, green: 237 / 255, blue: 244 / 255) }
    var hover: Color { dark ? base.hover : Color(red: 237 / 255, green: 242 / 255, blue: 248 / 255) }
    var weekend: Color { Color(red: 146 / 255, green: 155 / 255, blue: 167 / 255) }
    var weekendBackground: Color { dark ? base.hover : Color(red: 242 / 255, green: 244 / 255, blue: 247 / 255) }
}
