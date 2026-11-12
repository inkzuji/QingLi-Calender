import SwiftUI

struct QingLiIconButtonStyle: ButtonStyle {
    let palette: QingLiPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(configuration.isPressed ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
            .modifier(QingLiHoverBackground(palette: palette, cornerRadius: 7))
    }
}

private struct QingLiHoverBackground: ViewModifier {
    let palette: QingLiPalette
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}
