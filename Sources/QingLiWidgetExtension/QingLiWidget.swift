import SwiftUI
import WidgetKit
import QingLiCore

@main
struct QingLiWidgetBundle: WidgetBundle {
    var body: some Widget {
        QingLiWidget()
    }
}

struct QingLiWidget: Widget {
    let kind = "QingLiWidgetV2"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QingLiTimelineProvider()) { entry in
            QingLiWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("清历")
        .description("查看今天的农历、节气与中国法定休班安排。")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct QingLiTimelineEntry: TimelineEntry {
    let date: Date
    let today: CivilDate
}

struct QingLiTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QingLiTimelineEntry {
        QingLiTimelineEntry(date: .now, today: CivilDate(year: 2026, month: 9, day: 14))
    }

    func getSnapshot(in context: Context, completion: @escaping (QingLiTimelineEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QingLiTimelineEntry>) -> Void) {
        let entry = currentEntry()
        let calendar = Calendar.autoupdatingCurrent
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.date)) ?? entry.date.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func currentEntry(now: Date = .now) -> QingLiTimelineEntry {
        QingLiTimelineEntry(date: now, today: CivilDate(now) ?? CivilDate(year: 2026, month: 1, day: 1))
    }
}

struct QingLiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: QingLiTimelineEntry
    private let dateService: QingLiDateService
    private let engine = CalendarEngine()

    init(entry: QingLiTimelineEntry) {
        self.entry = entry
        dateService = WidgetHolidayDatasetLoader.makeDateService()
    }

    var body: some View {
        GeometryReader { proxy in
            let designSize = designSize(for: family)
            let scale = min(proxy.size.width / designSize.width, proxy.size.height / designSize.height)
            Group {
                switch family {
                case .systemSmall:
                    SmallWidget(today: entry.today, information: dateService.information(for: entry.today))
                default:
                    LargeWidget(month: engine.month(containing: entry.today), today: entry.today, dateService: dateService)
                }
            }
            .frame(width: designSize.width, height: designSize.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(
                x: (proxy.size.width - designSize.width * scale) / 2,
                y: (proxy.size.height - designSize.height * scale) / 2
            )
            .foregroundStyle(WidgetPalette(colorScheme).ink)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(WidgetPalette(colorScheme).border, lineWidth: 1)
        }
    }

    private func designSize(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 208, height: 251)
        default: CGSize(width: 526, height: 502)
        }
    }
}

private struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WidgetPalette(colorScheme).glass
    }
}

private struct WidgetPalette {
    let ink: Color
    let muted: Color
    let blue: Color
    let holiday: Color
    let holidayBackground: Color
    let hover: Color
    let todayBackground: Color
    let line: Color
    let glass: Color
    let border: Color

    init(_ colorScheme: ColorScheme) {
        if colorScheme == .dark {
            ink = Color(red: 226 / 255, green: 235 / 255, blue: 247 / 255)
            muted = Color(red: 160 / 255, green: 177 / 255, blue: 200 / 255)
            blue = Color(red: 112 / 255, green: 170 / 255, blue: 255 / 255)
            holiday = Color(red: 255 / 255, green: 157 / 255, blue: 170 / 255)
            holidayBackground = Color(red: 177 / 255, green: 68 / 255, blue: 87 / 255, opacity: 0.22)
            hover = Color(red: 166 / 255, green: 194 / 255, blue: 228 / 255, opacity: 0.12)
            todayBackground = Color(red: 73 / 255, green: 113 / 255, blue: 167 / 255, opacity: 0.10)
            line = Color(red: 175 / 255, green: 198 / 255, blue: 225 / 255, opacity: 0.17)
            glass = Color(red: 29 / 255, green: 45 / 255, blue: 65 / 255, opacity: 0.88)
            border = Color(red: 205 / 255, green: 225 / 255, blue: 248 / 255, opacity: 0.16)
        } else {
            ink = Color(red: 20 / 255, green: 45 / 255, blue: 75 / 255)
            muted = Color(red: 88 / 255, green: 113 / 255, blue: 142 / 255)
            blue = Color(red: 8 / 255, green: 101 / 255, blue: 247 / 255)
            holiday = Color(red: 188 / 255, green: 71 / 255, blue: 86 / 255)
            holidayBackground = Color(red: 249 / 255, green: 225 / 255, blue: 228 / 255)
            hover = Color(red: 86 / 255, green: 135 / 255, blue: 190 / 255, opacity: 0.10)
            todayBackground = Color(red: 236 / 255, green: 245 / 255, blue: 255 / 255, opacity: 0.52)
            line = Color(red: 67 / 255, green: 104 / 255, blue: 146 / 255, opacity: 0.15)
            glass = Color(red: 245 / 255, green: 250 / 255, blue: 255 / 255, opacity: 0.87)
            border = Color.white.opacity(0.56)
        }
    }
}

/// 小组件与主 App 共享的节假日数据文件。
///
/// 主 App 在用户确认更新后，将校验完成的完整 `HolidayDataset` 原子写入
/// App Group 容器根目录的 `holiday-dataset.json`，随后调用
/// `WidgetCenter.shared.reloadTimelines(ofKind: "QingLiWidgetV2")` 刷新本小组件。
private enum WidgetHolidayDatasetLoader {
    private static let appGroupIdentifier = "group.com.qingli.app"
    private static let datasetFileName = "holiday-dataset.json"

    static func makeDateService() -> QingLiDateService {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return QingLiDateService()
        }

        let datasetURL = containerURL.appending(path: datasetFileName)
        guard let data = try? Data(contentsOf: datasetURL),
              let dataset = try? JSONDecoder().decode(HolidayDataset.self, from: data),
              (try? HolidayDatasetValidator.validate(dataset)) != nil else {
            return QingLiDateService()
        }

        return QingLiDateService(holidayProvider: HolidayProvider(dataset: dataset))
    }
}

private struct SmallWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    let today: CivilDate
    let information: DayInformation

    var body: some View {
        let palette = WidgetPalette(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text("\(today.month)月")
                Text(QingLiDateFormatter.weekday(today))
            }
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(1)

            Text("\(today.day)")
                .font(.system(size: 78, weight: .medium))
                .kerning(-4)
                .frame(height: 83, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 9)
                .minimumScaleFactor(0.7)

            Text(information.lunar.map { "农历 \($0.shortDate)" } ?? "农历数据不可用")
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)

            let events = [information.festival, information.solarTerm]
                .compactMap { $0 }
                .joined(separator: " · ")
            if !events.isEmpty {
                Text(events)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.holiday)
                    .lineLimit(1)
                    .padding(.top, 6)
            }

            StatusChip(date: today, information: information)
                .padding(.top, 13)

            Spacer(minLength: 0)
        }
        .padding(22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("清历，\(information.accessibilitySummary)")
    }
}

private struct StatusChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let date: CivilDate
    let information: DayInformation

    var body: some View {
        let palette = WidgetPalette(colorScheme)
        Text(label)
            .font(.system(size: 12))
            .foregroundStyle(foreground(palette))
            .frame(height: 17)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(background(palette), in: RoundedRectangle(cornerRadius: 7))
    }

    private var label: String {
        if let holiday = information.holiday {
            return "\(holiday.name) · \(holiday.kind == .holiday ? "放假" : "调休补班")"
        }
        guard information.isHolidayArrangementCovered else {
            return "该年度节假日安排未内置"
        }
        guard let foundationDate = date.date(in: .qingLiGregorian) else {
            return "普通工作日"
        }
        let weekday = Calendar.qingLiGregorian.component(.weekday, from: foundationDate)
        return weekday == 1 || weekday == 7 ? "普通周末" : "普通工作日"
    }

    private func foreground(_ palette: WidgetPalette) -> Color {
        guard let holiday = information.holiday else { return palette.muted }
        return holiday.kind == .holiday ? palette.holiday : palette.blue
    }

    private func background(_ palette: WidgetPalette) -> Color {
        guard let holiday = information.holiday else { return palette.hover }
        return holiday.kind == .holiday
            ? palette.holidayBackground
            : Color(red: 28 / 255, green: 105 / 255, blue: 224 / 255, opacity: 31 / 255)
    }
}

private struct LargeWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    let month: CalendarMonth
    let today: CivilDate
    let dateService: QingLiDateService

    var body: some View {
        let palette = WidgetPalette(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "\(month.year)年\(month.month)月")
                    .font(.system(size: 20, weight: .semibold))
                    .kerning(-0.6)
                Spacer()
                Text("农历 · 节日 · 节气")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 17)

            MonthGrid(month: month, today: today, dateService: dateService)

            let info = dateService.information(for: today)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
                HStack {
                    Text("今天 · \(QingLiDateFormatter.weekday(today))")
                        .foregroundStyle(palette.muted)
                    Spacer()
                    Text(todaySummary(info))
                        .fontWeight(.medium)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 4)
                .padding(.top, 17)
            }
            .padding(.top, 13)
        }
        .padding(.top, 24)
        .padding(.horizontal, 21)
        .padding(.bottom, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(month.year)年\(month.month)月清历")
    }

    private func todaySummary(_ information: DayInformation) -> String {
        var text = information.lunar?.shortDate ?? "农历数据不可用"
        if let event = information.festival ?? information.solarTerm {
            text += " · \(event)"
        }
        return text
    }
}

private struct MonthGrid: View {
    @Environment(\.colorScheme) private var colorScheme
    private let engine = CalendarEngine()
    let month: CalendarMonth
    let today: CivilDate
    let dateService: QingLiDateService

    var body: some View {
        let palette = WidgetPalette(colorScheme)
        VStack(spacing: 0) {
            LazyVGrid(columns: columns(spacing: 4), spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(height: 29)
            .padding(.bottom, 7)

            LazyVGrid(columns: columns(spacing: 4), spacing: 7) {
                ForEach(month.days) { day in
                    let info = dateService.information(for: day.date)
                    MonthGridDay(
                        day: day,
                        information: info,
                        isToday: day.date == today
                    )
                }
            }
        }
    }

    private func columns(spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7)
    }

}

private struct MonthGridDay: View {
    @Environment(\.colorScheme) private var colorScheme
    let day: CalendarDay
    let information: DayInformation
    let isToday: Bool

    var body: some View {
        let palette = WidgetPalette(colorScheme)
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Text("\(day.date.day)")
                    .font(.system(size: 16))
                    .foregroundStyle(numberColor(palette))
                Text(secondaryLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryColor(palette))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let holiday = information.holiday {
                Text(holiday.kind.label)
                    .font(.system(size: 10))
                    .foregroundStyle(holiday.kind == .holiday ? palette.holiday : palette.blue)
                    .padding(.top, 4)
                    .padding(.trailing, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 49)
        .background(isToday ? palette.todayBackground : .clear, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(isToday ? palette.blue : .clear, lineWidth: 1.5)
        }
        .opacity(day.isInDisplayedMonth ? 1 : 0.62)
        .accessibilityLabel(information.accessibilitySummary)
    }

    private var secondaryLabel: String {
        information.calendarGridLabel
    }

    private func numberColor(_ palette: WidgetPalette) -> Color {
        information.holiday?.kind == .holiday ? palette.holiday : palette.ink
    }

    private func secondaryColor(_ palette: WidgetPalette) -> Color {
        if information.holiday?.kind == .holiday { return palette.holiday }
        if information.holiday?.kind == .adjustedWorkday { return palette.blue }
        return palette.muted
    }
}
