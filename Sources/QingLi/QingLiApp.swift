import AppKit
import SwiftUI
import WidgetKit
import QingLiCore

@main
struct QingLiApp: App {
    @StateObject private var holidayData = HolidayDataController()
    @StateObject private var menuBarDate = MenuBarDateController()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            QingLiCalendarView(holidayData: holidayData)
        } label: {
            Label("\(menuBarDate.day)", systemImage: "calendar")
                .accessibilityLabel("清历，\(menuBarDate.day)日")
        }
        .menuBarExtraStyle(.window)

        Window("数据更新", id: "holiday-update") {
            HolidayDataUpdateView()
                .environmentObject(holidayData)
        }
        .defaultSize(width: 360, height: 330)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

    }
}

@MainActor
private final class MenuBarDateController: NSObject, ObservableObject {
    @Published private(set) var day: Int
    private var midnightTimer: Timer?

    override init() {
        day = CivilDate(Date())?.day ?? 1
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(refresh), name: .NSCalendarDayChanged, object: nil)
        center.addObserver(self, selector: #selector(refresh), name: .NSSystemClockDidChange, object: nil)
        center.addObserver(self, selector: #selector(refresh), name: .NSSystemTimeZoneDidChange, object: nil)
        center.addObserver(self, selector: #selector(refresh), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refresh),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        scheduleMidnightRefresh()
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

struct QingLiCalendarView: View {
    private enum FocusTarget: Hashable {
        case monthTitle
        case day(CivilDate)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
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
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 23)
                weekdayHeader
                    .padding(.bottom, 6)
                calendarGrid
                compactDetail
                    .padding(.top, 15)
            }
            .padding(.top, 26)
            .padding(.horizontal, 26)
            .padding(.bottom, 17)

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
                .padding(.horizontal, 26)
                .padding(.top, 77)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(palette.ink)
        .frame(width: 484, height: 602, alignment: .top)
        .background(palette.glass)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(palette.border, lineWidth: 1)
        }
        .shadow(color: Color(red: 31 / 255, green: 66 / 255, blue: 108 / 255).opacity(0.18), radius: 35, y: 16)
        .shadow(color: Color(red: 17 / 255, green: 55 / 255, blue: 90 / 255).opacity(0.07), radius: 4.5, y: 2)
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
        HStack(spacing: 10) {
            Button {
                isMonthPickerPresented.toggle()
            } label: {
                Text(verbatim: "\(displayedMonth.year)年\(displayedMonth.month)月")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.75)
                    .foregroundStyle(isMonthTitleHovered ? palette.blue : palette.ink)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .focused($focusedTarget, equals: .monthTitle)
            .onHover { isMonthTitleHovered = $0 }
            .accessibilityLabel("选择年份和月份")

            Spacer()

            HStack(spacing: 6) {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(QingLiIconButtonStyle(palette: palette))
                .disabled(!canChangeMonth(by: -1))
                .accessibilityLabel("上个月")

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(QingLiIconButtonStyle(palette: palette))
                .disabled(!canChangeMonth(by: 1))
                .accessibilityLabel("下个月")

                Button {
                    returnToToday()
                } label: {
                    Text("今天")
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .frame(height: 35)
                        .background(
                            isTodayButtonHovered
                                ? Color(red: 38 / 255, green: 112 / 255, blue: 217 / 255).opacity(0.16)
                                : palette.hover,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .onHover { isTodayButtonHovered = $0 }
                .keyboardShortcut("t", modifiers: .command)
                .accessibilityHint("快捷键 Command T")
            }
        }
        .frame(height: 39)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                Text(weekday)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.muted)
                    .opacity(weekday == "六" || weekday == "日" ? 0.85 : 1)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("星期\(weekday)")
            }
        }
        .frame(height: 34, alignment: .top)
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
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
        return HStack(spacing: 12) {
            Text(information.lunar.map { "农历\($0.fullDate)" } ?? "农历数据超出支持范围")
                .font(.system(size: 16))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 6) {
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "holiday-update")
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(palette.blue)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(QingLiIconButtonStyle(palette: palette))
                .help("节假日更新")
                .accessibilityLabel("节假日更新")
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出清历", systemImage: "power")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 5)
                        .frame(height: 31)
                        .background(isQuitButtonHovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .onHover { isQuitButtonHovered = $0 }
                .accessibilityLabel("退出清历")
            }
        }
        .padding(.top, 21)
        .frame(height: 54, alignment: .top)
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
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(numberColor)
                    Text(secondaryLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryColor)
                        .padding(.top, 7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let holiday = information.holiday {
                    Text(holiday.kind.label)
                        .font(.system(size: 10))
                        .foregroundStyle(markColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, isSelected ? 7 : 4)
                        .padding(.trailing, isSelected ? 4 : 2)
                }
            }
            .frame(height: 58)
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
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(isToday ? palette.blue : .clear, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .opacity(isOutsideMonth && !isSelected ? 0.62 : 1)
            .shadow(color: isSelected ? palette.blue.opacity(0.15) : .clear, radius: 3.5, y: 3)
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        if isSelected {
            Circle().fill(palette.selection)
        } else if configuration.isPressed || isHovered {
            RoundedRectangle(cornerRadius: 13).fill(palette.hover)
        } else if isToday {
            RoundedRectangle(cornerRadius: 13).fill(palette.todayBackground)
        } else {
            RoundedRectangle(cornerRadius: 13).fill(.clear)
        }
    }
}

private struct MonthPicker: View {
    @Binding var displayedMonth: CivilDate
    @Binding var selectedDate: CivilDate
    @Binding var isPresented: Bool
    let palette: QingLiPalette
    let onSelectionCommitted: (CivilDate) -> Void
    @State private var year: Int
    @State private var yearText: String
    @FocusState private var isYearFieldFocused: Bool

    init(
        displayedMonth: Binding<CivilDate>,
        selectedDate: Binding<CivilDate>,
        isPresented: Binding<Bool>,
        palette: QingLiPalette,
        onSelectionCommitted: @escaping (CivilDate) -> Void
    ) {
        _displayedMonth = displayedMonth
        _selectedDate = selectedDate
        _isPresented = isPresented
        _year = State(initialValue: displayedMonth.wrappedValue.year)
        _yearText = State(initialValue: String(displayedMonth.wrappedValue.year))
        self.palette = palette
        self.onSelectionCommitted = onSelectionCommitted
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { setYear(max(1900, year - 1)) } label: {
                    Image(systemName: "chevron.left").frame(width: 32, height: 32)
                }
                    .buttonStyle(QingLiIconButtonStyle(palette: palette))
                    .disabled(year <= 1900)
                Spacer()
                HStack(spacing: 4) {
                    TextField("年份", text: $yearText)
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(width: 77, height: 28)
                        .background(palette.hover, in: RoundedRectangle(cornerRadius: 5))
                        .focused($isYearFieldFocused)
                        .onChange(of: yearText) { _, value in
                            if let candidate = Int(value) {
                                year = candidate
                            }
                        }
                        .onKeyPress { press in
                            guard isYearFieldFocused else { return .ignored }
                            switch press.key {
                            case .leftArrow, .rightArrow, .upArrow, .downArrow:
                                return .handled
                            default:
                                return .ignored
                            }
                        }
                    Text("年")
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                Button { setYear(min(2100, year + 1)) } label: {
                    Image(systemName: "chevron.right").frame(width: 32, height: 32)
                }
                    .buttonStyle(QingLiIconButtonStyle(palette: palette))
                    .disabled(year >= 2100)
            }
            .padding(.bottom, 15)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(1...12, id: \.self) { month in
                    Button {
                        choose(month)
                    } label: {
                        Text("\(month)月")
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                year == displayedMonth.year && month == displayedMonth.month
                                    ? palette.blue : .clear,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .foregroundStyle(
                                year == displayedMonth.year && month == displayedMonth.month
                                    ? Color.white : palette.ink
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("支持 1900 年 1 月 31 日至 2100 年 12 月 31 日")
                .font(.system(size: 10))
                .foregroundStyle(palette.muted)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .frame(height: 257, alignment: .top)
        .background(palette.glass, in: RoundedRectangle(cornerRadius: 15))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(palette.line, lineWidth: 1)
        }
        .shadow(color: Color(red: 20 / 255, green: 49 / 255, blue: 89 / 255).opacity(0.2), radius: 17.5, y: 10)
        .accessibilityLabel("年月选择器")
    }

    private func choose(_ month: Int) {
        guard let selectedYear = parsedYear else { return }
        setYear(selectedYear)
        let day = selectedYear == 1900 && month == 1 ? 31 : 1
        let date = CivilDate(year: selectedYear, month: month, day: day)
        displayedMonth = date
        selectedDate = date
        isPresented = false
        onSelectionCommitted(date)
    }

    private var parsedYear: Int? {
        QingLiSupportedDates.year(from: yearText)
    }

    private func setYear(_ value: Int) {
        year = value
        yearText = String(value)
    }

}

private struct QingLiIconButtonStyle: ButtonStyle {
    let palette: QingLiPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(configuration.isPressed ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
            .modifier(QingLiHoverBackground(palette: palette, cornerRadius: 7))
    }
}

private struct QingLiHoverBackground: ViewModifier {
    let palette: QingLiPalette
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}

private struct QingLiPalette {
    let ink: Color
    let muted: Color
    let blue: Color
    let selection: Color
    let holiday: Color
    let holidayBackground: Color
    let line: Color
    let glass: Color
    let border: Color
    let hover: Color
    let todayBackground: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            ink = Color(red: 226 / 255, green: 235 / 255, blue: 247 / 255)
            muted = Color(red: 160 / 255, green: 177 / 255, blue: 200 / 255)
            blue = Color(red: 112 / 255, green: 170 / 255, blue: 255 / 255)
            selection = Color(red: 53 / 255, green: 123 / 255, blue: 217 / 255)
            holiday = Color(red: 255 / 255, green: 157 / 255, blue: 170 / 255)
            holidayBackground = Color(red: 177 / 255, green: 68 / 255, blue: 87 / 255).opacity(0.22)
            line = Color(red: 175 / 255, green: 198 / 255, blue: 225 / 255).opacity(0.17)
            glass = Color(red: 29 / 255, green: 45 / 255, blue: 65 / 255).opacity(0.88)
            border = Color(red: 205 / 255, green: 225 / 255, blue: 248 / 255).opacity(0.16)
            hover = Color(red: 166 / 255, green: 194 / 255, blue: 228 / 255).opacity(0.12)
            todayBackground = Color(red: 73 / 255, green: 113 / 255, blue: 167 / 255).opacity(0.1)
        } else {
            ink = Color(red: 20 / 255, green: 45 / 255, blue: 75 / 255)
            muted = Color(red: 88 / 255, green: 113 / 255, blue: 142 / 255)
            blue = Color(red: 8 / 255, green: 101 / 255, blue: 247 / 255)
            selection = Color(red: 8 / 255, green: 101 / 255, blue: 247 / 255)
            holiday = Color(red: 188 / 255, green: 71 / 255, blue: 86 / 255)
            holidayBackground = Color(red: 249 / 255, green: 225 / 255, blue: 228 / 255)
            line = Color(red: 67 / 255, green: 104 / 255, blue: 146 / 255).opacity(0.15)
            glass = Color(red: 245 / 255, green: 250 / 255, blue: 255 / 255).opacity(0.87)
            border = Color.white.opacity(0.56)
            hover = Color(red: 86 / 255, green: 135 / 255, blue: 190 / 255).opacity(0.1)
            todayBackground = Color(red: 236 / 255, green: 245 / 255, blue: 255 / 255).opacity(0.52)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@MainActor
final class HolidayDataController: ObservableObject {
    @Published private(set) var dateService: QingLiDateService
    @Published private(set) var statusMessage: String?
    @Published private(set) var isStatusError = false
    @Published private(set) var preview: HolidayNoticeUpdatePreview?
    @Published var isPreviewPresented = false
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastUpdatedAt: Date?

    private let updater = ICloudHolidayCalendarUpdater()
    private let store: (any HolidayDatasetStoring)?
    private let metadataStore: HolidayUpdateMetadataStore?
    private var currentDataset: HolidayDataset

    init() {
        let provider = try! HolidayProvider()
        currentDataset = provider.holidayDataset
        dateService = QingLiDateService(holidayProvider: provider)
        store = try? HolidayDatasetStore.appGroup()
        metadataStore = try? HolidayUpdateMetadataStore.appGroup()
        if let metadataStore, let metadata = try? metadataStore.loadMetadata() {
            lastCheckedAt = metadata.lastCheckedAt
            lastUpdatedAt = metadata.lastUpdatedAt
        } else {
            lastCheckedAt = nil
            lastUpdatedAt = nil
        }
        if let lastUpdatedAt {
            statusMessage = "上次成功导入：\(Self.displayDate(lastUpdatedAt))"
        } else {
            statusMessage = nil
        }
    }

    var coveredYears: [Int] { currentDataset.coveredYears.sorted() }

    func checkHolidayCalendar() {
        guard !isChecking else { return }
        guard let metadataStore else {
            present(error: HolidayUpdateError.unavailableSharedContainer)
            return
        }
        let dataset = currentDataset
        let updater = updater
        let checkedAt = Date()
        lastCheckedAt = checkedAt
        beginPreparing {
            try await updater.prepareUpdate(currentDataset: dataset, metadataStore: metadataStore, checkedAt: checkedAt)
        }
    }

    func applyPreview() {
        guard let preview else { return }
        guard let store, let metadataStore else {
            present(error: HolidayUpdateError.unavailableSharedContainer)
            return
        }
        do {
            let updatedAt = Date()
            let result = try updater.apply(preview, to: store, metadataStore: metadataStore, updatedAt: updatedAt)
            let dataset = result.dataset
            currentDataset = dataset
            dateService = QingLiDateService(holidayProvider: HolidayProvider(dataset: dataset))
            lastUpdatedAt = result.metadataWasSaved ? updatedAt : lastUpdatedAt
            isPreviewPresented = false
            self.preview = nil
            if result.metadataWasSaved {
                statusMessage = "已导入 \(dataset.coveredYears.max() ?? preview.targetYear) 年节假日安排，小组件正在刷新。"
                isStatusError = false
            } else {
                statusMessage = "节假日数据已导入，但未能保存最近更新时间；小组件正在刷新。"
                isStatusError = true
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "QingLiWidgetV2")
        } catch {
            present(error: error)
        }
    }

    func cancelPreview() {
        isPreviewPresented = false
        preview = nil
    }

    private func beginPreparing(_ operation: @escaping @Sendable () async throws -> HolidayNoticeUpdatePreview) {
        guard !isChecking else { return }
        isChecking = true
        statusMessage = nil
        isStatusError = false
        preview = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await operation()
                preview = result
                statusMessage = "已解析 \(result.targetYear) 年 iCloud 节假日日历，请确认后保存。"
                isStatusError = false
                isPreviewPresented = true
            } catch {
                present(error: error)
            }
            isChecking = false
        }
    }

    private func present(error: Error) {
        statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isStatusError = true
    }

    private static func displayDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

private struct HolidayDataUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var holidayData: HolidayDataController

    var body: some View {
        let palette = QingLiPalette(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("数据更新")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(QingLiIconButtonStyle(palette: palette))
                .accessibilityLabel("关闭数据更新")
            }
            .padding(.bottom, 18)

            Text("内置节假日与节气数据")
                .font(.system(size: 13))
                .foregroundStyle(palette.muted)
            Text(coveredYearsText)
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                Text("最近更新状态")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text("最近检查：\(displayDate(holidayData.lastCheckedAt))")
                Text("最近成功导入：\(displayDate(holidayData.lastUpdatedAt))")
            }
            .font(.system(size: 13))
            .foregroundStyle(palette.muted)
            .padding(.top, 16)

            if holidayData.isChecking {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("正在下载 iCloud 节假日日历…")
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.muted)
                .padding(.top, 14)
            } else if let statusMessage = holidayData.statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(holidayData.isStatusError ? Color.red : palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            HStack {
                Link("iCloud 中国大陆节假日日历", destination: ICloudHolidayCalendarUpdater.calendarURL)
                    .font(.system(size: 12))
                Spacer()
                Button("检查节假日日历更新") {
                    holidayData.checkHolidayCalendar()
                }
                .font(.system(size: 13))
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(holidayData.isChecking)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 360)
        .foregroundStyle(palette.ink)
        .background(palette.glass)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.line, lineWidth: 1)
        }
        .shadow(color: Color(red: 20 / 255, green: 45 / 255, blue: 75 / 255).opacity(0.2), radius: 40, y: 20)
        .sheet(isPresented: $holidayData.isPreviewPresented) {
            if let preview = holidayData.preview {
                HolidayUpdatePreviewView(
                    preview: preview,
                    confirm: holidayData.applyPreview,
                    cancel: holidayData.cancelPreview
                )
            }
        }
    }

    private var coveredYearsText: String {
        guard let first = holidayData.coveredYears.first,
              let last = holidayData.coveredYears.last else { return "暂无可用年份" }
        return first == last ? "\(first) 年" : "\(first)–\(last) 年"
    }

    private func displayDate(_ date: Date?) -> String {
        guard let date else { return "尚无记录" }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

private struct HolidayUpdatePreviewView: View {
    let preview: HolidayNoticeUpdatePreview
    let confirm: () -> Void
    let cancel: () -> Void

    private var holidayCount: Int { preview.records.filter { $0.kind == .holiday }.count }
    private var workdayCount: Int { preview.records.filter { $0.kind == .adjustedWorkday }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("确认导入 \(preview.targetYear) 年安排")
                .font(.title2.weight(.semibold))
            Text("iCloud 中国大陆节假日日历")
                .font(.headline)
            HStack {
                Text("下载日期：\(preview.notice.publishedAt)")
                Spacer()
                Link("查看数据源", destination: preview.notice.sourceURL)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("将新增 \(holidayCount) 个放假日和 \(workdayCount) 个调休上班日。")
                .font(.subheadline)

            List(preview.records.sorted { $0.date < $1.date }, id: \.date) { record in
                HStack {
                    Text(record.date.description).monospacedDigit()
                    Text(record.name)
                    Spacer()
                    Text(record.kind == .holiday ? "休" : "班")
                        .foregroundStyle(record.kind == .holiday ? .red : .blue)
                        .fontWeight(.semibold)
                }
            }
            .frame(minHeight: 210)

            HStack {
                Spacer()
                Button("取消", action: cancel)
                Button("确认保存", action: confirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520, height: 480)
    }
}
