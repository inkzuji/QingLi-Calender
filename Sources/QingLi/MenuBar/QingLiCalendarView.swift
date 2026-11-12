import AppKit
import SwiftUI
import QingLiCore

private struct MenuBarWindowBackground: NSViewRepresentable {
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // 圆角外由窗口透出桌面，避免系统底色在内容四角露出。
            window.backgroundColor = .clear
            window.isOpaque = false
        }
    }

    func makeNSView(context: Context) -> WindowView {
        WindowView()
    }

    func updateNSView(_ nsView: WindowView, context: Context) {}
}

struct QingLiCalendarView: View {
    private enum FocusTarget: Hashable {
        case monthTitle
        case day(CivilDate)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var holidayData: HolidayDataController
    private let engine = CalendarEngine()
    private let supportedRange = QingLiSupportedDates.range

    @State private var today: CivilDate
    @State private var displayedMonth: CivilDate
    @State private var selectedDate: CivilDate
    @State private var isMonthPickerPresented = false
    @State private var isMonthTitleHovered = false
    @State private var isTodayButtonHovered = false
    @State private var isQuitButtonHovered = false
    @FocusState private var focusedTarget: FocusTarget?

    init(holidayData: HolidayDataController) {
        self.holidayData = holidayData
        let today = CivilDate(Date()) ?? CivilDate(year: 2026, month: 1, day: 1)
        _today = State(initialValue: today)
        _displayedMonth = State(initialValue: today)
        _selectedDate = State(initialValue: today)
    }

    private var month: CalendarMonth { engine.month(containing: displayedMonth) }
    private var palette: QingLiPalette { QingLiPalette(colorScheme: colorScheme) }

    var body: some View {
        let panelShape = RoundedRectangle(cornerRadius: 5)

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 21)
                weekdayHeader
                    .padding(.bottom, 5)
                calendarGrid
                compactDetail
                    .padding(.top, 14)
            }
            .padding(.top, 23)
            .padding(.horizontal, 24)
            .padding(.bottom, 15)

            if isMonthPickerPresented {
                MonthPicker(
                    displayedMonth: $displayedMonth,
                    selectedDate: $selectedDate,
                    isPresented: $isMonthPickerPresented,
                    palette: palette,
                    onSelectionCommitted: { date in
                        focusedTarget = .day(date)
                    }
                )
                .padding(.horizontal, 24)
                .padding(.top, 69)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // 直接按最终尺寸排版，避免整体缩放在 1× 屏幕上使文字边缘发虚。
        .font(.system(size: 11.7))
        .foregroundStyle(palette.ink)
        .frame(width: 436, height: 542, alignment: .top)
        .background(palette.glass)
        .background(.ultraThinMaterial)
        .clipShape(panelShape)
        .overlay {
            panelShape
                .stroke(palette.border, lineWidth: 1)
        }
        .shadow(color: Color(red: 31 / 255, green: 66 / 255, blue: 108 / 255).opacity(0.18), radius: 32, y: 14)
        .shadow(color: Color(red: 17 / 255, green: 55 / 255, blue: 90 / 255).opacity(0.07), radius: 4, y: 2)
        .background(MenuBarWindowBackground().allowsHitTesting(false))
        .onKeyPress { press in
            guard press.modifiers.contains(.control),
                  !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  press.key == "t" else {
                return .ignored
            }
            returnToToday()
            return .handled
        }
        .onExitCommand {
            if isMonthPickerPresented {
                isMonthPickerPresented = false
                focusedTarget = .monthTitle
            } else {
                dismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshToday()
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button {
                isMonthPickerPresented.toggle()
            } label: {
                Text(verbatim: "\(displayedMonth.year)年\(displayedMonth.month)月")
                    .font(.system(size: 21.6, weight: .semibold))
                    .tracking(-0.675)
                    .foregroundStyle(isMonthTitleHovered ? palette.blue : palette.ink)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .focused($focusedTarget, equals: .monthTitle)
            .onHover { isMonthTitleHovered = $0 }
            .accessibilityLabel("选择年份和月份")

            Spacer()

            HStack(spacing: 5) {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 29, height: 29)
                }
                .buttonStyle(QingLiIconButtonStyle(palette: palette))
                .disabled(!canChangeMonth(by: -1))
                .accessibilityLabel("上个月")

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 29, height: 29)
                }
                .buttonStyle(QingLiIconButtonStyle(palette: palette))
                .disabled(!canChangeMonth(by: 1))
                .accessibilityLabel("下个月")

                Button {
                    returnToToday()
                } label: {
                    Text("今天")
                        .font(.system(size: 13.5))
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(
                            isTodayButtonHovered
                                ? Color(red: 38 / 255, green: 112 / 255, blue: 217 / 255).opacity(0.16)
                                : palette.hover,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
                .padding(.leading, 5)
                .onHover { isTodayButtonHovered = $0 }
                .keyboardShortcut("t", modifiers: .command)
                .accessibilityHint("快捷键 Command T")
            }
        }
        .frame(height: 35)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                Text(weekday)
                    .font(.system(size: 12.6))
                    .foregroundStyle(palette.muted)
                    .opacity(weekday == "六" || weekday == "日" ? 0.85 : 1)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("星期\(weekday)")
            }
        }
        .frame(height: 31, alignment: .top)
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 7) {
            ForEach(month.days) { day in
                let information = holidayData.dateService.information(for: day.date)
                CalendarDayButton(
                    day: day,
                    information: information,
                    isToday: day.date == today,
                    isSelected: day.date == selectedDate,
                    palette: palette
                ) {
                    select(day.date)
                }
                .disabled(!isAllowed(day.date))
                .focused($focusedTarget, equals: .day(day.date))
            }
        }
        .onKeyPress { press in
            guard press.modifiers.intersection([.command, .control, .option]).isEmpty else {
                return .ignored
            }
            switch press.key {
            case .leftArrow: moveSelection(by: -1)
            case .rightArrow: moveSelection(by: 1)
            case .upArrow: moveSelection(by: -7)
            case .downArrow: moveSelection(by: 7)
            default: return .ignored
            }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(displayedMonth.year)年\(displayedMonth.month)月月历")
    }

    private var compactDetail: some View {
        let information = holidayData.dateService.information(for: selectedDate)
        return HStack(spacing: 11) {
            Text(information.lunar.map { "农历\($0.fullDate)" } ?? "农历数据超出支持范围")
                .font(.system(size: 14.4))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
            Spacer()
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出清历", systemImage: "power")
                    .font(.system(size: 10.8))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 5)
                    .frame(height: 28)
                    .background(isQuitButtonHovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .onHover { isQuitButtonHovered = $0 }
            .accessibilityLabel("退出清历")
        }
        .padding(.top, 19)
        .frame(height: 49, alignment: .top)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("日期详情，\(information.accessibilitySummary)")
    }

    private func select(_ date: CivilDate) {
        guard isAllowed(date) else { return }
        selectedDate = date
        if date.year != displayedMonth.year || date.month != displayedMonth.month {
            displayedMonth = date
        }
        focusedTarget = .day(date)
    }

    private func changeMonth(by value: Int) {
        guard let date = engine.addingMonths(value, to: selectedDate, limitedTo: supportedRange) else { return }
        displayedMonth = date
        selectedDate = date
        isMonthPickerPresented = false
        focusedTarget = .day(date)
    }

    private func moveSelection(by value: Int) {
        guard let date = engine.addingDays(value, to: selectedDate), isAllowed(date) else { return }
        select(date)
    }

    private func returnToToday() {
        displayedMonth = today
        selectedDate = today
        isMonthPickerPresented = false
        focusedTarget = .day(today)
    }

    private func canChangeMonth(by value: Int) -> Bool {
        if value < 0 {
            return displayedMonth.year > supportedRange.lowerBound.year || displayedMonth.month > supportedRange.lowerBound.month
        }
        return displayedMonth.year < supportedRange.upperBound.year || displayedMonth.month < supportedRange.upperBound.month
    }

    private func isAllowed(_ date: CivilDate) -> Bool {
        supportedRange.contains(date)
    }

    private func refreshToday() {
        guard let newToday = CivilDate(Date()), newToday != today else { return }
        let wasShowingToday = selectedDate == today
        today = newToday
        if wasShowingToday {
            displayedMonth = newToday
            selectedDate = newToday
        }
    }
}

private struct CalendarDayButton: View {
    @State private var isHovered = false
    let day: CalendarDay
    let information: DayInformation
    let isToday: Bool
    let isSelected: Bool
    let palette: QingLiPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                VStack(spacing: 0) {
                    Text("\(day.date.day)")
                        .font(.system(size: 16.2, weight: .medium))
                        .foregroundStyle(numberColor)
                    Text(secondaryLabel)
                        .font(.system(size: 10.8))
                        .foregroundStyle(secondaryColor)
                        .padding(.top, 6)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let holiday = information.holiday {
                    Text(holiday.kind.label)
                        .font(.system(size: 9))
                        .foregroundStyle(markColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, isSelected ? 6 : 4)
                        .padding(.trailing, isSelected ? 4 : 2)
                }
            }
            .frame(height: 52)
        }
        .buttonStyle(CalendarDayButtonStyle(
            isToday: isToday,
            isSelected: isSelected,
            isOutsideMonth: !day.isInDisplayedMonth,
            isHovered: isHovered,
            palette: palette
        ))
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        var label = "\(information.accessibilitySummary)，\(QingLiDateFormatter.weekday(day.date))"
        if isToday { label += "，今天" }
        if isSelected { label += "，已选择" }
        return label
    }

    private var secondaryLabel: String {
        information.calendarGridLabel
    }

    private var numberColor: Color {
        if isSelected { return .white }
        return information.holiday?.kind == .holiday ? palette.holiday : palette.ink
    }

    private var secondaryColor: Color {
        if isSelected { return .white }
        if information.holiday?.kind == .holiday { return palette.holiday }
        if information.holiday?.kind == .adjustedWorkday { return palette.blue }
        return palette.muted
    }

    private var markColor: Color {
        if isSelected { return .white }
        return information.holiday?.kind == .holiday ? palette.holiday : palette.blue
    }
}

private struct CalendarDayButtonStyle: ButtonStyle {
    let isToday: Bool
    let isSelected: Bool
    let isOutsideMonth: Bool
    let isHovered: Bool
    let palette: QingLiPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(background(configuration: configuration))
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(isToday ? palette.glass : .clear, lineWidth: 2)
                        .padding(2)
                    Circle()
                        .stroke(isToday ? palette.blue : .clear, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isToday ? palette.blue : .clear, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isOutsideMonth && !isSelected ? 0.62 : 1)
            .shadow(color: isSelected ? palette.blue.opacity(0.15) : .clear, radius: 3, y: 3)
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        if isSelected {
            Circle().fill(palette.selection)
        } else if configuration.isPressed || isHovered {
            RoundedRectangle(cornerRadius: 12).fill(palette.hover)
        } else if isToday {
            RoundedRectangle(cornerRadius: 12).fill(palette.todayBackground)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(.clear)
        }
    }
}
