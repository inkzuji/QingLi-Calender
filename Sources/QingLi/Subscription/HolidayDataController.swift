import SwiftUI
import WidgetKit
import QingLiCore

@MainActor
final class HolidayDataController: ObservableObject {
    enum SourceChoice: String, CaseIterable, Identifiable {
        case recommended, custom

        var id: Self { self }
        var title: String { self == .recommended ? "推荐源" : "自定义" }
    }

    struct Feedback {
        enum Kind { case information, success, failure }

        let text: String
        let kind: Kind
    }

    private enum Operation {
        case idle(Feedback?)
        case checking(UUID)
        case preview(HolidaySubscriptionPreview, String?)
        case saving(HolidaySubscriptionPreview)
    }

    private enum PreferenceKey {
        static let choice = "holidaySubscription.choice"
        static let custom = "holidaySubscription.custom"
    }

    @Published private(set) var dataset: HolidayDataset
    @Published private(set) var sourceChoice: SourceChoice
    @Published private(set) var customName: String
    @Published private(set) var customAddress: String
    @Published private(set) var lastCheckedAt: Date?
    @Published private var operation: Operation = .idle(nil)

    private(set) var dateService: QingLiDateService
    private let updater: HolidayCalendarUpdater
    private let loadDataset: @Sendable () throws -> HolidayDataset
    private let store: (any HolidayDatasetStoring)?
    private let metadataStore: HolidayUpdateMetadataStore?
    private let defaults: UserDefaults
    private let reloadWidget: @MainActor () -> Void
    private let legacyLastUpdatedAt: Date?
    private var checkTask: Task<Void, Never>?

    init(
        updater: HolidayCalendarUpdater = HolidayCalendarUpdater(),
        loadDataset: @escaping @Sendable () throws -> HolidayDataset = { try HolidayProvider().holidayDataset },
        store: (any HolidayDatasetStoring)? = try? HolidayDatasetStore.appGroup(),
        metadataStore: HolidayUpdateMetadataStore? = try? HolidayUpdateMetadataStore.appGroup(),
        defaults: UserDefaults = .standard,
        reloadWidget: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: "QingLiWidgetV2") }
    ) {
        self.updater = updater
        self.loadDataset = loadDataset
        self.store = store
        self.metadataStore = metadataStore
        self.defaults = defaults
        self.reloadWidget = reloadWidget
        let initialDataset = (try? loadDataset()) ?? HolidayDataset(
            revision: UUID().uuidString,
            coveredYears: [],
            records: [],
            yearSources: [:],
            lastUpdatedAt: nil
        )
        dataset = initialDataset
        dateService = QingLiDateService(holidayProvider: HolidayProvider(dataset: initialDataset))
        sourceChoice = defaults.string(forKey: PreferenceKey.choice)
            .flatMap(SourceChoice.init(rawValue:)) ?? .recommended
        let custom = defaults.data(forKey: PreferenceKey.custom)
            .flatMap { try? JSONDecoder().decode(HolidaySubscription.self, from: $0) }
        customName = custom?.name ?? ""
        customAddress = custom?.url.absoluteString ?? ""
        let metadata = try? metadataStore?.loadMetadata()
        lastCheckedAt = metadata?.lastCheckedAt
        legacyLastUpdatedAt = metadata?.lastUpdatedAt
    }

    var coveredYears: [Int] { dataset.coveredYears.sorted() }
    var lastUpdatedAt: Date? {
        if let updatedAt = dataset.lastUpdatedAt { return updatedAt }
        let hasLegacyImport = dataset.yearSources.values.contains {
            $0.requestURL == ICloudHolidayCalendarUpdater.calendarURL && $0.importedAt == nil
        }
        return hasLegacyImport ? legacyLastUpdatedAt : nil
    }

    var isChecking: Bool {
        if case .checking = operation { return true }
        return false
    }

    var isSaving: Bool {
        if case .saving = operation { return true }
        return false
    }

    var preview: HolidaySubscriptionPreview? {
        switch operation {
        case let .preview(preview, _), let .saving(preview): preview
        default: nil
        }
    }

    var previewError: String? {
        if case let .preview(_, error) = operation { return error }
        return nil
    }

    var feedback: Feedback? {
        switch operation {
        case let .idle(feedback): feedback
        case .checking: Feedback(text: "正在下载订阅并比较年度安排…", kind: .information)
        default: nil
        }
    }

    func choose(_ choice: SourceChoice, restoring: Bool = false) {
        guard !isChecking, !isSaving, choice != sourceChoice else { return }
        if sourceChoice == .custom { persistCustomDraft() }
        sourceChoice = choice
        defaults.set(choice.rawValue, forKey: PreferenceKey.choice)
        operation = .idle(restoring ? Feedback(text: "已恢复推荐源。已导入的数据未改变。", kind: .information) : nil)
    }

    func editCustomName(_ name: String) {
        guard !isChecking, !isSaving else { return }
        customName = String(name.prefix(60))
        operation = .idle(nil)
    }

    func editCustomAddress(_ address: String) {
        guard !isChecking, !isSaving else { return }
        customAddress = address
        operation = .idle(nil)
    }

    func persistCustomDraft() {
        guard sourceChoice == .custom, !isChecking, !isSaving else { return }
        if let normalizedURL = try? HolidaySubscription.normalizedURL(for: customAddress) {
            customAddress = normalizedURL.absoluteString
        }
        if let subscription = try? HolidaySubscription(name: customName, address: customAddress) {
            persist(subscription)
        }
    }

    @discardableResult
    func checkHolidayCalendar() -> Task<Void, Never>? {
        guard case .idle = operation else { return nil }
        let subscription: HolidaySubscription
        do {
            if sourceChoice == .recommended {
                subscription = .recommended
            } else {
                subscription = try HolidaySubscription(name: customName, address: customAddress)
                persist(subscription)
            }
        } catch {
            operation = .idle(Feedback(text: error.localizedDescription, kind: .failure))
            return nil
        }

        let id = UUID()
        let baseline = dataset
        let currentYear = Calendar.qingLiGregorian.component(.year, from: .now)
        operation = .checking(id)
        let task = Task { [weak self, updater] in
            do {
                let preview = try await updater.prepareUpdate(
                    subscription: subscription,
                    currentDataset: baseline,
                    currentYear: currentYear
                )
                self?.finishCheck(id, result: .success(preview))
            } catch {
                self?.finishCheck(id, result: .failure(error))
            }
        }
        checkTask = task
        return task
    }

    func cancelPendingUpdate() {
        switch operation {
        case .checking:
            checkTask?.cancel()
            checkTask = nil
            operation = .idle(nil)
        case .preview:
            operation = .idle(Feedback(text: "已取消本次导入，现有数据未改变。", kind: .information))
        default:
            break
        }
    }

    @discardableResult
    func applyPreview(selectedYears: Set<Int>) -> Task<Void, Never>? {
        guard case let .preview(preview, _) = operation, !selectedYears.isEmpty else { return nil }
        guard let store else {
            operation = .preview(preview, HolidayUpdateError.unavailableSharedContainer.localizedDescription)
            return nil
        }

        operation = .saving(preview)
        return Task {
            do {
                let result = try await Task.detached { [updater, loadDataset] in
                    let latest = try loadDataset()
                    guard latest.revision == preview.baseRevision else { return (latest, false) }
                    let next = try updater.applying(preview, selectedYears: selectedYears, to: latest)
                    try store.save(next)
                    return (next, true)
                }.value
                let (updated, didSave) = result
                dateService = QingLiDateService(holidayProvider: HolidayProvider(dataset: updated))
                dataset = updated
                if didSave {
                    let years = selectedYears.sorted().map(String.init).joined(separator: "、")
                    operation = .idle(Feedback(text: "已保存 \(years) 年安排，小组件正在刷新。", kind: .success))
                    reloadWidget()
                } else {
                    operation = .idle(Feedback(text: "节假日数据已更新，请重新检查后再导入。", kind: .failure))
                }
            } catch {
                operation = .preview(preview, "无法保存节假日数据。\(error.localizedDescription)")
            }
        }
    }

    private func persist(_ subscription: HolidaySubscription) {
        guard let data = try? JSONEncoder().encode(subscription) else { return }
        defaults.set(data, forKey: PreferenceKey.custom)
        customName = subscription.name
        customAddress = subscription.url.absoluteString
    }

    private func finishCheck(_ id: UUID, result: Result<HolidaySubscriptionPreview, Error>) {
        guard case let .checking(activeID) = operation, id == activeID else { return }
        checkTask = nil
        let checkedAt = Date()
        lastCheckedAt = checkedAt
        try? metadataStore?.markChecked(at: checkedAt)
        switch result {
        case let .success(preview):
            if preview.years.isEmpty {
                operation = .idle(Feedback(text: "订阅源未提供今年或后续年份的休班安排。", kind: .information))
            } else if preview.years.contains(where: { $0.status != .unchanged }) {
                operation = .preview(preview, nil)
            } else {
                operation = .idle(Feedback(text: "已是最新安排，没有发现日期变化。", kind: .success))
            }
        case let .failure(error):
            operation = .idle(Feedback(text: error.localizedDescription, kind: .failure))
        }
    }
}
