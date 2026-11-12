import SwiftUI
import QingLiCore

struct SubscriptionPreviewView: View {
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
