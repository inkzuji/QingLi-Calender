import Foundation
import QingLiCore
import XCTest
@testable import QingLi

@MainActor
final class HolidayDataControllerTests: XCTestCase {
    func testCancelledCheckIgnoresLateResponse() async throws {
        let fixture = SubscriptionFixture()
        let requestStarted = expectation(description: "等待开始下载")
        let client = DeferredSubscriptionHTTPClient(requestStarted: requestStarted)
        let store = SubscriptionTestStore(dataset: fixture.dataset)
        let controller = makeController(client: client, store: store)

        let task = try XCTUnwrap(controller.checkHolidayCalendar())
        await fulfillment(of: [requestStarted], timeout: 1)
        XCTAssertTrue(controller.isChecking)

        controller.cancelPendingUpdate()
        await client.complete(fixture.response)
        await task.value

        XCTAssertFalse(controller.isChecking)
        XCTAssertNil(controller.preview)
        XCTAssertNil(controller.lastCheckedAt)
        XCTAssertEqual(controller.dataset.revision, fixture.dataset.revision)
    }

    func testSaveFailurePreservesPreviewAndAllowsRetry() async throws {
        let fixture = SubscriptionFixture()
        let store = SubscriptionTestStore(dataset: fixture.dataset, failFirstSave: true)
        var reloadCount = 0
        let controller = makeController(client: ImmediateSubscriptionHTTPClient(response: fixture.response), store: store) {
            reloadCount += 1
        }

        let check = try XCTUnwrap(controller.checkHolidayCalendar())
        await check.value
        let preview = try XCTUnwrap(controller.preview)
        XCTAssertTrue(preview.years.contains { $0.year == fixture.year && $0.isSelectable })

        let failedSave = try XCTUnwrap(controller.applyPreview(selectedYears: [fixture.year]))
        XCTAssertTrue(controller.isSaving)
        await failedSave.value

        XCTAssertFalse(controller.isSaving)
        XCTAssertEqual(controller.preview?.baseRevision, preview.baseRevision)
        XCTAssertNotNil(controller.previewError)
        XCTAssertEqual(controller.dataset.revision, fixture.dataset.revision)
        XCTAssertEqual(store.snapshot().revision, fixture.dataset.revision)
        XCTAssertEqual(reloadCount, 0)

        let retry = try XCTUnwrap(controller.applyPreview(selectedYears: [fixture.year]))
        await retry.value

        XCTAssertNil(controller.preview)
        XCTAssertNil(controller.previewError)
        XCTAssertEqual(controller.coveredYears, [fixture.year - 1, fixture.year])
        XCTAssertEqual(controller.dataset.revision, store.snapshot().revision)
        XCTAssertNotNil(controller.lastUpdatedAt)
        XCTAssertEqual(reloadCount, 1)
    }

    private func makeController(
        client: any HolidayHTTPClient,
        store: SubscriptionTestStore,
        reloadWidget: @escaping @MainActor () -> Void = {}
    ) -> HolidayDataController {
        HolidayDataController(
            updater: HolidayCalendarUpdater(client: client),
            loadDataset: store.snapshot,
            store: store,
            metadataStore: nil,
            defaults: UserDefaults(suiteName: "com.qingli.tests.\(UUID().uuidString)")!,
            reloadWidget: reloadWidget
        )
    }
}

private struct SubscriptionFixture {
    let year = Calendar.qingLiGregorian.component(.year, from: .now) + 1

    var dataset: HolidayDataset {
        HolidayDataset(
            revision: "baseline",
            coveredYears: [year - 1],
            records: [HolidayRecord(date: CivilDate(year: year - 1, month: 1, day: 1), name: "元旦", kind: .holiday)],
            yearSources: [year - 1: HolidayYearSource(name: "测试夹具")],
            lastUpdatedAt: nil
        )
    }

    var response: HolidayHTTPResponse {
        let holidays = [
            ("0101", "元旦"), ("0206", "春节"), ("0405", "清明节"), ("0501", "劳动节"),
            ("0610", "端午节"), ("0918", "中秋节"), ("1001", "国庆节")
        ]
        let events = holidays.map { date, name in
            "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:\(year)\(date)\r\nSUMMARY:\(name) 假期 第1天/共1天\r\nEND:VEVENT"
        }
        let workday = "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:\(year)0214\r\nSUMMARY:春节 补班 第1天/共1天\r\nEND:VEVENT"
        let calendar = (["BEGIN:VCALENDAR", "VERSION:2.0"] + events + [workday, "END:VCALENDAR"]).joined(separator: "\r\n")
        return HolidayHTTPResponse(url: HolidaySubscription.recommended.url, data: Data(calendar.utf8), statusCode: 200)
    }
}

private actor DeferredSubscriptionHTTPClient: HolidayHTTPClient {
    private let requestStarted: XCTestExpectation
    private var pendingResponse: CheckedContinuation<HolidayHTTPResponse, Never>?
    private var earlyResponse: HolidayHTTPResponse?

    init(requestStarted: XCTestExpectation) {
        self.requestStarted = requestStarted
    }

    func data(for url: URL) async throws -> HolidayHTTPResponse {
        requestStarted.fulfill()
        if let earlyResponse { return earlyResponse }
        return await withCheckedContinuation { pendingResponse = $0 }
    }

    func complete(_ value: HolidayHTTPResponse) {
        if let pendingResponse {
            pendingResponse.resume(returning: value)
            self.pendingResponse = nil
        } else {
            earlyResponse = value
        }
    }
}

private struct ImmediateSubscriptionHTTPClient: HolidayHTTPClient {
    let response: HolidayHTTPResponse

    func data(for url: URL) async throws -> HolidayHTTPResponse { response }
}

private final class SubscriptionTestStore: HolidayDatasetStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var dataset: HolidayDataset
    private var failFirstSave: Bool

    init(dataset: HolidayDataset, failFirstSave: Bool = false) {
        self.dataset = dataset
        self.failFirstSave = failFirstSave
    }

    func snapshot() -> HolidayDataset { lock.withLock { dataset } }

    func loadCached() throws -> HolidayDataset? { snapshot() }

    func save(_ dataset: HolidayDataset) throws {
        try lock.withLock {
            if failFirstSave {
                failFirstSave = false
                throw CocoaError(.fileWriteNoPermission)
            }
            self.dataset = dataset
        }
    }
}
