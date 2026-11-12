import AppKit
import SwiftUI
import QingLiCore

@main
struct QingLiApp: App {
    @NSApplicationDelegateAdaptor(QingLiAppDelegate.self) private var appDelegate
    @StateObject private var navigation = DesktopNavigation()
    @StateObject private var holidayData = HolidayDataController()
    @StateObject private var menuBarDate = MenuBarDateController()

    private static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            let calendarBody = NSBezierPath(
                roundedRect: NSRect(x: 2, y: 2, width: 18, height: 18),
                xRadius: 4,
                yRadius: 4
            )
            calendarBody.addClip()
            NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.93, alpha: 1).setFill()
            calendarBody.fill()

            let apricot = NSColor(calibratedRed: 1, green: 0.56, blue: 0.28, alpha: 1)
            apricot.setFill()
            NSRect(x: 2, y: 15, width: 18, height: 5).fill()

            for row in 0..<2 {
                for column in 0..<3 {
                    let color = row == 0 && column == 2 ? apricot : NSColor.darkGray
                    color.setFill()
                    NSBezierPath(
                        roundedRect: NSRect(
                            x: 5 + CGFloat(column) * 4,
                            y: 5 + CGFloat(row) * 5,
                            width: 3,
                            height: 3
                        ),
                        xRadius: 0.7,
                        yRadius: 0.7
                    ).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Window("清历", id: DesktopNavigation.windowID) {
            DesktopCalendarView(navigation: navigation, holidayData: holidayData, appDelegate: appDelegate)
        }
        .defaultSize(width: 1200, height: 865)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            QingLiCalendarView(holidayData: holidayData)
        } label: {
            Label {
                Text("\(menuBarDate.day)")
            } icon: {
                Image(nsImage: Self.menuBarIcon)
                    .renderingMode(.original)
            }
            .accessibilityLabel("清历，\(menuBarDate.day)日")
        }
        .menuBarExtraStyle(.window)
    }
}
