import SwiftUI
import QingLiCore

struct MonthPicker: View {
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
                    Image(systemName: "chevron.left").frame(width: 29, height: 29)
                }
                    .buttonStyle(QingLiIconButtonStyle(palette: palette))
                    .disabled(year <= 1900)
                Spacer()
                HStack(spacing: 4) {
                    TextField("年份", text: $yearText)
                        .font(.system(size: 14.4, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(width: 69, height: 25)
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
                        .font(.system(size: 12.6, weight: .semibold))
                }
                Spacer()
                Button { setYear(min(2100, year + 1)) } label: {
                    Image(systemName: "chevron.right").frame(width: 29, height: 29)
                }
                    .buttonStyle(QingLiIconButtonStyle(palette: palette))
                    .disabled(year >= 2100)
            }
            .padding(.bottom, 14)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                ForEach(1...12, id: \.self) { month in
                    Button {
                        choose(month)
                    } label: {
                        Text("\(month)月")
                            .font(.system(size: 12.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                year == displayedMonth.year && month == displayedMonth.month
                                    ? palette.blue : .clear,
                                in: RoundedRectangle(cornerRadius: 8)
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
                .font(.system(size: 9))
                .foregroundStyle(palette.muted)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .frame(height: 232, alignment: .top)
        .background(palette.glass, in: RoundedRectangle(cornerRadius: 14))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.line, lineWidth: 1)
        }
        .shadow(color: Color(red: 20 / 255, green: 49 / 255, blue: 89 / 255).opacity(0.2), radius: 16, y: 9)
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
