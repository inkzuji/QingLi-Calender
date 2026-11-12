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

struct HolidaySubscriptionView: View {
    private enum Field { case name, address }

    @ObservedObject var holidayData: HolidayDataController
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var contentHeight: CGFloat = 806

    private var palette: SubscriptionPalette { SubscriptionPalette(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heading
                    .padding(.bottom, 23)
                importedData
                    .padding(.bottom, 25)
                sourceSettings

                if let feedback = holidayData.feedback {
                    SubscriptionFeedback(feedback: feedback, palette: palette)
                        .padding(.top, 17)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                HStack(spacing: 20) {
                    Text("最近检查：\(holidayData.lastCheckedAt.map(displaySubscriptionDate) ?? "尚未检查")")
                    Text("最近成功导入：\(holidayData.lastUpdatedAt.map(displaySubscriptionDate) ?? "尚无记录")")
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.base.muted)
                .frame(minHeight: 16.5)
                .padding(.top, 20)

                footer
                    .padding(.top, 20)
            }
            .foregroundStyle(palette.base.ink)
            .frame(maxWidth: 720)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
            contentHeight = $0
        }
        .sheet(isPresented: Binding(
            get: { holidayData.preview != nil },
            set: { if !$0 { holidayData.cancelPendingUpdate() } }
        )) {
            if let preview = holidayData.preview {
                SubscriptionPreviewView(preview: preview, holidayData: holidayData, height: min(845, contentHeight + 38))
            }
        }
        .onChange(of: focusedField) { oldField, _ in
            if oldField != nil { holidayData.persistCustomDraft() }
        }
        .onDisappear {
            holidayData.persistCustomDraft()
            holidayData.cancelPendingUpdate()
        }
    }

    private var heading: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("节假日订阅")
                    .font(.system(size: 23, weight: .bold))
                    .tracking(0.5)
                    .frame(minHeight: 34.5)
                Text("管理放假与调休安排的数据来源")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.base.muted)
                    .frame(minHeight: 18)
            }
            Spacer()
            Text(holidayData.coveredYears.isEmpty ? "尚无本地数据" : "本地数据可用")
                .font(.system(size: 11))
                .foregroundStyle(holidayData.coveredYears.isEmpty ? palette.warningInk : palette.successInk)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(holidayData.coveredYears.isEmpty ? palette.warningBackground : palette.successBackground, in: Capsule())
        }
    }

    private var importedData: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已导入的数据")
                .font(.system(size: 13, weight: .semibold))
                .frame(minHeight: 19.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(coverageLabel).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("按年份保留来源")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.base.muted)
                }
                .frame(minHeight: 21)
                .padding(.bottom, 9)

                ForEach(holidayData.coveredYears, id: \.self) { year in
                    HStack {
                        Text("\(String(year)) 年").fontWeight(.semibold)
                        Spacer()
                        Text(holidayData.dataset.yearSources[year]?.name ?? "来源未知")
                            .foregroundStyle(palette.base.muted)
                    }
                    .font(.system(size: 12))
                    .frame(minHeight: 18)
                    .padding(.vertical, 9)
                    if year != holidayData.coveredYears.last {
                        palette.line.frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .subscriptionPanel(fill: palette.surface, line: palette.line, radius: 12)
        }
    }

    private var coverageLabel: String {
        let years = holidayData.coveredYears
        guard let first = years.first, let last = years.last else { return "暂无可用年份" }
        if first == last { return "\(first) 年" }
        if last - first + 1 == years.count { return "\(first) — \(last) 年" }
        return years.map(String.init).joined(separator: "、") + " 年"
    }

    private var sourceSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("当前选择的订阅源").font(.system(size: 13, weight: .semibold))
                Spacer()
                if holidayData.sourceChoice == .custom {
                    Button("恢复推荐源") {
                        focusedField = nil
                        holidayData.choose(.recommended, restoring: true)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.base.blue)
                }
            }
            .frame(minHeight: 19.5)
            .padding(.bottom, 12)

            HStack(spacing: 0) {
                ForEach(HolidayDataController.SourceChoice.allCases) { choice in
                    let selected = holidayData.sourceChoice == choice
                    Button {
                        focusedField = nil
                        holidayData.choose(choice)
                    } label: {
                        Text(choice.title)
                            .font(.system(size: 14, weight: selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .frame(height: 35)
                            .contentShape(Rectangle())
                            .background(selected ? palette.surface : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .shadow(color: selected ? .black.opacity(0.09) : .clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(palette.segment, in: RoundedRectangle(cornerRadius: 9))
            .padding(.bottom, 15)

            Group {
                if holidayData.sourceChoice == .recommended {
                    recommendedCard
                } else {
                    customCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(minHeight: holidayData.sourceChoice == .recommended ? 140 : 243, alignment: .topLeading)
            .subscriptionPanel(fill: palette.surface, line: palette.line, radius: 12)

            VStack(alignment: .leading, spacing: 0) {
                Text("切换订阅源只影响下一次检查，已导入的数据保持不变。")
                    .frame(minHeight: 19.8, alignment: .leading)
                Text("第三方订阅仅供参考，请以官方发布的节假日安排为准。")
                    .frame(minHeight: 19.8, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundStyle(palette.base.muted)
            .padding(.top, 12)
        }
        .disabled(holidayData.isChecking || holidayData.isSaving)
    }

    private var recommendedCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text("中国节假日日历").font(.system(size: 14, weight: .semibold))
                Text("推荐")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.base.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.infoBackground, in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(minHeight: 21)
            Text("由 lanceliao 社区项目维护 · 包含放假与补班")
                .font(.system(size: 12))
                .foregroundStyle(palette.base.muted)
                .frame(minHeight: 18)
            Text(HolidaySubscription.recommended.url.absoluteString)
                .font(.system(size: 11))
                .foregroundStyle(palette.base.muted)
                .textSelection(.enabled)
                .frame(minHeight: 18.7)
                .padding(.top, 3)
                .padding(.bottom, 7)
            Link(destination: HolidaySubscription.projectURL) {
                Text("查看源项目 ↗")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.base.blue)
                    .frame(minHeight: 18)
            }
            .buttonStyle(.plain)
        }
    }

    private var customCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("添加你信任的订阅")
                .font(.system(size: 14, weight: .semibold))
                .frame(minHeight: 21)
            customField(
                "订阅名称",
                prompt: "例如：我的中国节假日",
                text: Binding(get: { holidayData.customName }, set: { holidayData.editCustomName($0) }),
                field: .name
            )
            customField(
                "ICS 订阅地址",
                prompt: "https://example.com/holidays.ics",
                text: Binding(get: { holidayData.customAddress }, set: { holidayData.editCustomAddress($0) }),
                field: .address
            )
            Text("支持 HTTPS；webcal:// 地址将自动转换。仅支持可识别放假与补班的中国节假日订阅。")
                .font(.system(size: 11))
                .foregroundStyle(palette.base.muted)
                .lineSpacing(3)
                .frame(minHeight: 19.8, alignment: .leading)
        }
    }

    private func customField(_ title: String, prompt: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .frame(minHeight: 18)
            TextField(title, text: text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .frame(height: 39)
                .subscriptionPanel(
                    fill: palette.surface,
                    line: focusedField == field ? palette.base.blue : palette.line,
                    radius: 7
                )
                .focused($focusedField, equals: field)
                .onSubmit {
                    holidayData.persistCustomDraft()
                    focusedField = nil
                }
        }
    }

    private var footer: some View {
        HStack(spacing: 15) {
            Text("检查后预览差异，由你确认保存。")
                .font(.system(size: 11))
                .foregroundStyle(palette.base.muted)
            Spacer()
            Button(holidayData.isChecking ? "正在检查…" : "检查更新") {
                focusedField = nil
                holidayData.checkHolidayCalendar()
            }
            .buttonStyle(SubscriptionButtonStyle(palette: palette, isPrimary: true))
            .disabled(holidayData.isChecking || holidayData.isSaving)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 17)
        .subscriptionPanel(fill: palette.footer, line: palette.line, radius: 10)
    }
}

private struct SubscriptionPreviewView: View {
    let preview: HolidaySubscriptionPreview
    @ObservedObject var holidayData: HolidayDataController
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedYears: Set<Int>
    @State private var filter: HolidayDateChangeKind?

    private var palette: SubscriptionPalette { SubscriptionPalette(colorScheme: colorScheme) }
    private var displayedYears: [HolidayYearUpdate] { preview.years.filter { $0.status != .unchanged } }
    private var selectedUpdates: [HolidayYearUpdate] { preview.years.filter { selectedYears.contains($0.year) } }
    private var selectedChanges: [HolidayDateChange] { selectedUpdates.flatMap(\.changes) }

    init(preview: HolidaySubscriptionPreview, holidayData: HolidayDataController, height: CGFloat) {
        self.preview = preview
        self.holidayData = holidayData
        self.height = height
        _selectedYears = State(initialValue: Set(preview.years.filter(\.isSelectable).map(\.year)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("预览节假日更新")
                        .font(.system(size: 23, weight: .bold))
                        .tracking(0.5)
                        .frame(minHeight: 34)
                    Text("本次来源：\(preview.subscription.name)")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.base.muted)
                        .frame(minHeight: 18)
                        .padding(.top, 5)
                    Text("下载时间：\(displaySubscriptionDate(preview.downloadedAt)) · 非官方公告发布时间")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.base.muted)
                        .frame(minHeight: 18)
                        .padding(.top, 23)

                    years
                        .padding(.vertical, 18)
                    metrics
                    filterBar
                        .padding(.top, 20)
                    changeTable
                        .padding(.top, 8)
                }
                .padding(.horizontal, 30)
                .padding(.top, 27)
            }
            .scrollIndicators(.hidden)
            .disabled(holidayData.isSaving)

            VStack(spacing: 12) {
                SubscriptionFeedback(
                    feedback: .init(text: verificationMessage, kind: .information),
                    palette: palette
                )
                if let error = holidayData.previewError {
                    SubscriptionFeedback(feedback: .init(text: error, kind: .failure), palette: palette)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 17)
            .padding(.bottom, 27)

            palette.line.frame(height: 1)
            footer
        }
        .foregroundStyle(palette.base.ink)
        .background(palette.previewBackground)
        .frame(width: 690, height: height)
        .interactiveDismissDisabled(holidayData.isSaving)
    }

    private var years: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
            count: max(1, min(3, displayedYears.count))
        )
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(displayedYears, id: \.year) { year in
                yearChoice(year)
            }
        }
    }

    private func yearChoice(_ year: HolidayYearUpdate) -> some View {
        let isSelected = selectedYears.contains(year.year)
        let toggle = Binding(
            get: { selectedYears.contains(year.year) },
            set: { if $0 { selectedYears.insert(year.year) } else { selectedYears.remove(year.year) } }
        )
        return VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: toggle) {
                Text("\(String(year.year)) 年 · \(title(for: year.status))")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.base.ink)
                    .frame(minHeight: 19, alignment: .leading)
            }
            .toggleStyle(.checkbox)
            .tint(palette.base.blue)
            .disabled(!year.isSelectable)

            Text(year.failureReason ?? counts(for: year))
                .font(.system(size: 11))
                .foregroundStyle(year.failureReason == nil ? palette.base.muted : palette.errorInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 17, alignment: .leading)
                .padding(.leading, 23)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .subscriptionPanel(
            fill: isSelected ? palette.selectedYear : palette.surface,
            line: isSelected ? palette.base.blue : palette.line,
            radius: 10
        )
    }

    private func counts(for year: HolidayYearUpdate) -> String {
        let holidays = year.records.filter { $0.kind == .holiday }.count
        let workdays = year.records.count - holidays
        return "放假 \(holidays) 天 / 补班 \(workdays) 天"
    }

    private func title(for status: HolidayYearUpdateStatus) -> String {
        switch status {
        case .added: "新增"
        case .revised: "修订"
        case .sourceOnly: "安排无变化，仅更新来源"
        case .unchanged: "没有变化"
        case .invalid: "不可导入"
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric("新增日期", kind: .added)
            palette.line.frame(width: 1, height: 54)
            metric("修改日期", kind: .modified)
            palette.line.frame(width: 1, height: 54)
            metric("移除日期", kind: .removed)
        }
        .padding(.vertical, 15)
        .subscriptionPanel(fill: palette.surface, line: palette.line, radius: 10)
    }

    private func metric(_ title: String, kind: HolidayDateChangeKind) -> some View {
        VStack(spacing: 2) {
            Text(selectedChanges.filter { $0.kind == kind }.count.formatted(.number.grouping(.never)))
                .font(.system(size: 23, weight: .bold))
                .monospacedDigit()
                .frame(minHeight: 35)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(palette.base.muted)
                .frame(minHeight: 17)
        }
        .frame(maxWidth: .infinity)
    }

    private var filterBar: some View {
        HStack(spacing: 17) {
            filterButton("全部差异", kind: nil)
            filterButton("新增", kind: .added)
            filterButton("修改", kind: .modified)
            filterButton("移除", kind: .removed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) { palette.line.frame(height: 1) }
    }

    private func filterButton(_ title: String, kind: HolidayDateChangeKind?) -> some View {
        let isSelected = filter == kind
        return Button {
            filter = kind
        } label: {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? palette.base.blue : palette.base.muted)
                .frame(height: 35)
                .overlay(alignment: .bottom) {
                    if isSelected { palette.base.blue.frame(height: 2) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var changeTable: some View {
        let rows = selectedChanges.filter { filter == nil || $0.kind == filter }
        return ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("日期").frame(width: 215, alignment: .leading)
                    Text("安排变化").frame(maxWidth: .infinity, alignment: .leading)
                    Text("类型")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.base.muted)
                .padding(.horizontal, 6)
                .frame(height: 38)
                palette.line.frame(height: 1)

                if rows.isEmpty {
                    Text("没有符合条件的差异")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.base.muted)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                } else {
                    ForEach(rows, id: \.date) { row in
                        changeRow(row)
                        palette.line.frame(height: 1)
                    }
                }
            }
        }
        .frame(height: min(280, rows.isEmpty ? 117 : CGFloat(rows.count * 59 + 39)))
    }

    private func changeRow(_ change: HolidayDateChange) -> some View {
        HStack(spacing: 0) {
            Text(change.date.description)
                .monospacedDigit()
                .frame(width: 215, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(change.after?.name ?? change.before?.name ?? "")
                HStack(spacing: 6) {
                    if let before = change.before {
                        Text(change.after?.name != before.name && change.after != nil ? "\(before.name) \(before.kind.label)" : before.kind.label)
                            .foregroundStyle(palette.base.muted)
                            .strikethrough()
                    }
                    Text(change.after?.kind.label ?? "恢复普通日期")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let (label, ink, fill) = style(for: change.kind)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(fill, in: RoundedRectangle(cornerRadius: 4))
        }
        .font(.system(size: 12))
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
    }

    private func style(for kind: HolidayDateChangeKind) -> (String, Color, Color) {
        switch kind {
        case .added: ("新增", palette.successInk, palette.successBackground)
        case .modified: ("修改", palette.warningInk, palette.warningBackground)
        case .removed: ("移除", palette.errorInk, palette.errorBackground)
        }
    }

    private var verificationMessage: String {
        guard displayedYears.contains(where: \.isSelectable) else {
            return "本次没有通过格式与覆盖检查的年份，请核对订阅内容。"
        }
        var lines = [
            "确认后将替换所选年份的完整安排，其他年份的数据会保留。",
            "通过格式与覆盖检查，安排以官方发布为准。"
        ]
        let unverified = selectedUpdates.filter { !$0.totalsWereVerified }.map { String($0.year) }
        if !unverified.isEmpty {
            lines.append("\(unverified.joined(separator: "、")) 年订阅缺少天数编号，无法核对放假与补班总数。")
        }
        return lines.joined(separator: "\n")
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("已选择 \(selectedYears.count) 个年份")
                .font(.system(size: 11))
                .foregroundStyle(palette.base.muted)
            Spacer()
            Button("取消", role: .cancel, action: holidayData.cancelPendingUpdate)
                .buttonStyle(SubscriptionButtonStyle(palette: palette, isPrimary: false))
                .keyboardShortcut(.cancelAction)
                .disabled(holidayData.isSaving)
            Button(holidayData.isSaving ? "正在保存…" : "确认保存") {
                holidayData.applyPreview(selectedYears: selectedYears)
            }
            .buttonStyle(SubscriptionButtonStyle(palette: palette, isPrimary: true))
            .disabled(selectedYears.isEmpty || holidayData.isSaving)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 17)
        .background(palette.footer)
    }
}

private struct SubscriptionFeedback: View {
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

private struct SubscriptionButtonStyle: ButtonStyle {
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

private struct SubscriptionPalette {
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

private extension Color {
    init(subscriptionRGB rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255
        )
    }
}

private extension View {
    func subscriptionPanel(fill: Color, line: Color, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return background(fill, in: shape)
            .overlay { shape.strokeBorder(line, lineWidth: 1).allowsHitTesting(false) }
    }
}

private func displaySubscriptionDate(_ date: Date) -> String {
    date.formatted(
        Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)/\(month: .twoDigits)/\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: Locale(identifier: "zh_CN"),
            timeZone: .autoupdatingCurrent,
            calendar: .qingLiGregorian
        )
    )
}
