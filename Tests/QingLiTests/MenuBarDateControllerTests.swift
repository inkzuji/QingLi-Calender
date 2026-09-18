import AppKit
import Combine
import XCTest
@testable import QingLi

@MainActor
final class MenuBarDateControllerTests: XCTestCase {
    func testBackgroundNotificationsRefreshOnMainThread() async {
        let notifications: [(Notification.Name, Bool)] = [
            (.NSCalendarDayChanged, false),
            (.NSSystemClockDidChange, false),
            (.NSSystemTimeZoneDidChange, false),
            (NSApplication.didBecomeActiveNotification, false),
            (NSWorkspace.didWakeNotification, true)
        ]

        for (name, usesWorkspaceCenter) in notifications {
            let notificationCenter = NotificationCenter()
            let workspaceNotificationCenter = NotificationCenter()
            let controller = MenuBarDateController(
                notificationCenter: notificationCenter,
                workspaceNotificationCenter: workspaceNotificationCenter
            )
            let refreshed = expectation(description: "\(name.rawValue) refreshes on the main thread")
            let observation = controller.objectWillChange.sink {
                XCTAssertTrue(Thread.isMainThread)
                refreshed.fulfill()
            }
            let postingCenter = usesWorkspaceCenter ? workspaceNotificationCenter : notificationCenter

            DispatchQueue.global(qos: .userInteractive).async {
                postingCenter.post(name: name, object: nil)
            }

            await fulfillment(of: [refreshed], timeout: 1)
            withExtendedLifetime(observation) {}
        }
    }
}
