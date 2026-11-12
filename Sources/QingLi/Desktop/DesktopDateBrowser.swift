import AppKit
import SwiftUI
import QingLiCore

struct DesktopDateBrowser: View {
    @ObservedObject var navigation: DesktopNavigation
    @ObservedObject var holidayData: HolidayDataController
    let palette: DesktopPalette

    @Environment(\.colorScheme) private var colorScheme
    @State private var today = DesktopNavigation.today
    @State private var showsMonthPicker = false
    private let engine = CalendarEngine()
    private let range = QingLiSupportedDates.range
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    private var month: CivilDate { navigation.displayedMonth }
    private var selection: CivilDate { navigation.selectedDate }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if navigation.mode == .year {
                        yearView(columns: geometry.size.width < 640 ? 3 : 4)
                    } else if geometry.size.width > 880 {
                        HStack(alignment: .top, spacing: 25) {
                            monthView(cellHeight: 83)
                            datePanel
                                .padding(.leading, 24)
                                .frame(width: 235, alignment: .leading)
                        }
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(palette.line)
                                .frame(width: 1)
                                .padding(.trailing, 234)
                                .allowsHitTesting(false)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            monthView(cellHeight: 73)
                            Divider().overlay(palette.line)
                            datePanel
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(navigation.mode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = DesktopNavigation.today
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            today = DesktopNavigation.today
        }
    }

    private func yearView(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Text(verbatim: "\(month.year)年")
                    .font(.system(size: 27, weight: .semibold))
                    .tracking(-0.9)
                Spacer()
                HStack(spacing: 5) {
                    Button("上一年") { changeMonth(by: -12) }
                        .disabled(month.year <= range.lowerBound.year)
                    Button("今年") { changeMonth(by: (today.year - month.year) * 12) }
                    Button("下一年") { changeMonth(by: 12) }
                        .disabled(month.year >= range.upperBound.year)
                }
                .buttonStyle(DesktopOutlineButtonStyle(palette: palette))
            }
            .frame(minHeight: 40)

            LazyVGrid(columns: gridColumns(columns, spacing: 30), spacing: 24) {
                ForEach(1...12, id: \.self) { number in
                    yearMonth(number)
                }
            }
            VStack(spacing: 15) {
                Divider().overlay(palette.line)
                HStack {
                    Text("红色：放假　蓝色下划线：补班")
                    Spacer()
                    if !holidayData.dataset.coveredYears.contains(month.year) {
                        Text("该年休班数据尚未导入")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(palette.muted)
            }
        }
    }

    private func yearMonth(_ number: Int) -> some View {
        let first = CivilDate(year: month.year, month: number, day: 1)
        let date = max(first, range.lowerBound)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                navigation.select(date)
            } label: {
                Text("\(number)月")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(height: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(month.year)年\(number)月 月视图"))
            .padding(.bottom, 10)
            weekdayRow(size: 9)
                .frame(height: 14)
                .padding(.bottom, 5)
            LazyVGrid(columns: gridColumns(7), spacing: 1) {
                ForEach(engine.month(containing: first).days) { day in
                    if day.isInDisplayedMonth, range.contains(day.date) {
                        yearDay(day.date)
                    } else {
                        Color.clear.frame(height: 23).accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func yearDay(_ date: CivilDate) -> some View {
        let holiday = holidayData.dateService.holidayProvider.holiday(on: date)
        let isToday = date == today
        let color = holiday.map { $0.kind == .holiday ? palette.holiday : palette.blue }
            ?? (isWeekend(date) ? palette.weekend : palette.ink)
        return Button {
            navigation.select(date)
        } label: {
            Text(date.day.formatted())
                .font(.system(size: 11))
                .monospacedDigit()
                .underline(!isToday && holiday?.kind == .adjustedWorkday)
                .foregroundStyle(isToday ? Color.white : color)
                .frame(maxWidth: .infinity)
                .frame(height: 23)
                .background(isToday ? palette.blue : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(DesktopHoverButtonStyle(color: palette.hover))
        .accessibilityLabel([date.description, holiday?.name, holiday?.kind.accessibilityLabel]
            .compactMap { $0 }.joined(separator: "，"))
    }

    private func monthView(cellHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "\(month.year)年\(month.month)月")
                    .font(.system(size: 23, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Button("上一月") { changeMonth(by: -1) }
                        .disabled(month.year == range.lowerBound.year && month.month == 1)
                    Button("今天") { navigation.select(today) }
                    Button("下一月") { changeMonth(by: 1) }
                        .disabled(month.year == range.upperBound.year && month.month == 12)
                }
                .buttonStyle(DesktopOutlineButtonStyle(palette: palette))
            }
            .padding(.bottom, 18)
            HStack(spacing: 8) {
                Spacer()
                Text("跳转")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                Button {
                    showsMonthPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: "\(month.year)年\(month.month)月")
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(DesktopOutlineButtonStyle(palette: palette))
                .popover(isPresented: $showsMonthPicker, arrowEdge: .bottom) {
                    MonthPicker(
                        displayedMonth: $navigation.displayedMonth,
                        selectedDate: $navigation.selectedDate,
                        isPresented: $showsMonthPicker,
                        palette: QingLiPalette(colorScheme: colorScheme),
                        onSelectionCommitted: { navigation.select($0) }
                    )
                    .frame(width: 320)
                }
                .accessibilityLabel("跳转到年月")
            }
            .padding(.bottom, 24)
            weekdayRow(size: 11)
                .frame(height: 17)
                .padding(.bottom, 12)
            LazyVGrid(columns: gridColumns(7), spacing: 0) {
                ForEach(engine.month(containing: month).days) { day in
                    monthDay(day, height: cellHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(palette.line).allowsHitTesting(false) }

            Text("休 法定放假　班 调休补班")
                .font(.system(size: 10))
                .foregroundStyle(palette.muted)
                .padding(.top, 15)
        }
    }

    private func monthDay(_ day: CalendarDay, height: CGFloat) -> some View {
        let information = holidayData.dateService.information(for: day.date)
        let holiday = information.holiday
        let selected = selection == day.date
        let isToday = day.date == today
        let weekend = holiday == nil && isWeekend(day.date)
        let isHoliday = holiday?.kind == .holiday
        let dayColor = isHoliday ? palette.holiday : (weekend && !isToday ? palette.weekend : palette.ink)
        let captionColor = isHoliday ? palette.holiday : (weekend && !isToday ? palette.weekend : palette.muted)

        return Button {
            navigation.select(day.date)
        } label: {
            VStack(spacing: 6) {
                Text(day.date.day.formatted())
                    .font(.system(size: 19, weight: isToday ? .bold : .medium))
                    .foregroundStyle(selected ? Color.white : (isToday ? palette.blue : dayColor))
                Text(information.solarTerm ?? information.lunar?.gridDate ?? "")
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white : captionColor)
            }
            .opacity(day.isInDisplayedMonth ? 1 : 0.4)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(selected ? palette.blue : (weekend ? palette.weekendBackground : palette.surface))
            .overlay(alignment: .topTrailing) {
                if let holiday {
                    Text(holiday.kind == .holiday ? "休" : "班")
                        .font(.system(size: 9))
                        .foregroundStyle(selected ? Color.white : (isHoliday ? palette.holiday : palette.blue))
                        .padding(5)
                        .opacity(day.isInDisplayedMonth ? 1 : 0.4)
                }
            }
            .overlay(alignment: .trailing) { Rectangle().fill(palette.line).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(DesktopHoverButtonStyle(color: palette.hover))
        .disabled(!range.contains(day.date))
        .accessibilityLabel(information.accessibilitySummary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var datePanel: some View {
        let information = holidayData.dateService.information(for: selection)
        let holiday = information.holiday
        let covered = information.isHolidayArrangementCovered
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(selection.month)月 · \(QingLiDateFormatter.weekday(selection))")
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
            Text(selection.day.formatted())
                .font(.system(size: 72, weight: .light))
                .tracking(-4)
                .padding(.top, 25)
                .padding(.bottom, 6)
            if let lunar = information.lunar {
                Text("农历 \(lunar.fullDate)")
                    .font(.system(size: 13))
                    .padding(.top, 6)
                    .padding(.bottom, 24)
            }
            detailBlock("这一天") {
                Text(holiday?.name ?? (covered ? (isWeekend(selection) ? "周末" : "普通工作日") : "节假日安排待更新"))
                    .font(.system(size: 12))
                Text(holiday?.kind.accessibilityLabel ?? (covered ? "无特殊休班安排" : "未导入该年数据"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                if let solarTerm = information.solarTerm {
                    Text("节气 · \(solarTerm)")
                        .font(.system(size: 12))
                }
            }
            detailBlock("数据来源") {
                Text(holidayData.dataset.yearSources[selection.year]?.name ?? "尚未覆盖 \(selection.year) 年")
                    .font(.system(size: 12))
                Button("管理节假日订阅") { navigation.page = .subscription }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func detailBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(palette.line)
                .padding(.bottom, 11)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.muted)
            content()
        }
        .padding(.bottom, 26)
    }

    private func weekdayRow(size: CGFloat) -> some View {
        LazyVGrid(columns: gridColumns(7)) {
            ForEach(weekdays, id: \.self) { Text($0) }
        }
        .font(.system(size: size))
        .foregroundStyle(palette.muted)
        .accessibilityHidden(true)
    }

    private func gridColumns(_ count: Int, spacing: CGFloat = 0) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: count)
    }

    private func changeMonth(by amount: Int) {
        guard let date = engine.addingMonths(amount, to: month, limitedTo: range) else { return }
        navigation.displayedMonth = date
        if navigation.mode == .month {
            navigation.selectedDate = date
        }
    }

    private func isWeekend(_ date: CivilDate) -> Bool {
        guard let value = date.date(in: engine.calendar) else { return false }
        return engine.calendar.isDateInWeekend(value)
    }
}
