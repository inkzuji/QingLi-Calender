import SwiftUI

struct QingLiPalette {
    let ink: Color
    let muted: Color
    let blue: Color
    let selection: Color
    let holiday: Color
    let holidayBackground: Color
    let line: Color
    let glass: Color
    let border: Color
    let hover: Color
    let todayBackground: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            ink = Color(red: 226 / 255, green: 235 / 255, blue: 247 / 255)
            muted = Color(red: 160 / 255, green: 177 / 255, blue: 200 / 255)
            blue = Color(red: 112 / 255, green: 170 / 255, blue: 255 / 255)
            selection = Color(red: 53 / 255, green: 123 / 255, blue: 217 / 255)
            holiday = Color(red: 255 / 255, green: 157 / 255, blue: 170 / 255)
            holidayBackground = Color(red: 177 / 255, green: 68 / 255, blue: 87 / 255).opacity(0.22)
            line = Color(red: 175 / 255, green: 198 / 255, blue: 225 / 255).opacity(0.17)
            glass = Color(red: 29 / 255, green: 45 / 255, blue: 65 / 255).opacity(0.88)
            border = Color(red: 205 / 255, green: 225 / 255, blue: 248 / 255).opacity(0.16)
            hover = Color(red: 166 / 255, green: 194 / 255, blue: 228 / 255).opacity(0.12)
            todayBackground = Color(red: 73 / 255, green: 113 / 255, blue: 167 / 255).opacity(0.1)
        } else {
            ink = Color(red: 20 / 255, green: 45 / 255, blue: 75 / 255)
            muted = Color(red: 88 / 255, green: 113 / 255, blue: 142 / 255)
            blue = Color(red: 8 / 255, green: 101 / 255, blue: 247 / 255)
            selection = Color(red: 8 / 255, green: 101 / 255, blue: 247 / 255)
            holiday = Color(red: 188 / 255, green: 71 / 255, blue: 86 / 255)
            holidayBackground = Color(red: 249 / 255, green: 225 / 255, blue: 228 / 255)
            line = Color(red: 67 / 255, green: 104 / 255, blue: 146 / 255).opacity(0.15)
            glass = Color(red: 245 / 255, green: 250 / 255, blue: 255 / 255).opacity(0.87)
            border = Color.white.opacity(0.56)
            hover = Color(red: 86 / 255, green: 135 / 255, blue: 190 / 255).opacity(0.1)
            todayBackground = Color(red: 236 / 255, green: 245 / 255, blue: 255 / 255).opacity(0.52)
        }
    }
}
