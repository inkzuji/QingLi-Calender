import AppKit
import SwiftUI
import QingLiCore

struct DesktopHolidayOverview: View {
    @ObservedObject var navigation: DesktopNavigation
    @ObservedObject var holidayData: HolidayDataController
    let palette: DesktopPalette

    private var year: Int { navigation.overviewYear }
    private var years: [Int] {
        let today = DesktopNavigation.today.year
        return Array(Set(holidayData.dataset.coveredYears + [today, min(today + 1, QingLiSupportedDates.range.upperBound.year), year])).sorted()
    }

    var body: some View {
        let records = holidayData.dataset.records.filter { $0.date.year == year }
        let holidays = Dictionary(grouping: records.filter { $0.kind == .holiday }, by: \.name)
            .values.map { $0.sorted { $0.date < $1.date } }
            .sorted { $0[0].date < $1[0].date }
        let workdays = records.filter { $0.kind == .adjustedWorkday }.sorted { $0.date < $1.date }

        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    Text("全年休班")
                        .font(.system(size: 23, weight: .semibold))
                    Spacer()
                    Menu {
                        Picker("休班年份", selection: $navigation.overviewYear) {
                            ForEach(years, id: \.self) { Text(verbatim: String($0)).tag($0) }
                        }
                    } label: {
                        Text(verbatim: String(year))
                            .font(.system(size: 14))
                            .frame(width: 50, alignment: .leading)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 80, height: 34)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(palette.line).allowsHitTesting(false) }
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.muted)
                            .padding(.trailing, 8)
                            .allowsHitTesting(false)
                    }
                    .accessibilityLabel("休班年份")
                    .accessibilityValue(String(year))
                }

                if records.isEmpty {
                    VStack(spacing: 10) {
                        Text("尚未导入 \(year.formatted(.number.grouping(.never))) 年安排")
                            .font(.system(size: 15, weight: .semibold))
                        Text("检查订阅后，预览并确认保存该年份。")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.muted)
                        Button("前往节假日订阅") { navigation.page = .subscription }
                            .buttonStyle(.borderedProminent)
                            .tint(palette.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(45)
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(palette.line) }
                } else {
                    VStack(spacing: 14) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                            ForEach(holidays, id: \.self) { days in
                                holidayCard(days)
                            }
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            Text("调休补班 · \(workdays.count) 天")
                                .font(.system(size: 13, weight: .semibold))
                            Text(workdays.map { String($0.date.description.suffix(5)) }.joined(separator: "　"))
                                .font(.system(size: 12))
                                .foregroundStyle(palette.muted)
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: 97, alignment: .leading)
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(palette.line) }
                    }
                }
            }
            .padding(28)
        }
    }

    private func holidayCard(_ days: [HolidayRecord]) -> some View {
        let first = days[0]
        let last = days[days.count - 1]
        return Button {
            navigation.select(first.date)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(first.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Text("休 \(days.count) 天")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.holiday)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.holidayBackground, in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(.bottom, 5)
                Text("\(first.date.description) 至 \(last.date.description)")
                Text("在月历中查看")
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 20)
            .frame(minHeight: 122)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(palette.line) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
