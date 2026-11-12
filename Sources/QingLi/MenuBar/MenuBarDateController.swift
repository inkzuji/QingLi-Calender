import AppKit
import SwiftUI
import QingLiCore

@MainActor
final class MenuBarDateController: NSObject, ObservableObject {
    @Published private(set) var day: Int
    private var midnightTimer: Timer?

    init(
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        day = CivilDate(Date())?.day ?? 1
        super.init()
        notificationCenter.addObserver(self, selector: #selector(handleRefreshNotification(_:)), name: .NSCalendarDayChanged, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleRefreshNotification(_:)), name: .NSSystemClockDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleRefreshNotification(_:)), name: .NSSystemTimeZoneDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleRefreshNotification(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleRefreshNotification(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        scheduleMidnightRefresh()
    }

    @objc nonisolated private func handleRefreshNotification(_: Notification) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    @objc private func refresh() {
        day = CivilDate(Date())?.day ?? 1
        scheduleMidnightRefresh()
    }

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
        let timer = Timer(fireAt: nextDay.addingTimeInterval(0.1), interval: 0, target: self, selector: #selector(refresh), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
