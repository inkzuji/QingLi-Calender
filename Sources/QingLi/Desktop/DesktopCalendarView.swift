import AppKit
import SwiftUI
import QingLiCore

struct DesktopCalendarView: View {
    @ObservedObject var navigation: DesktopNavigation
    @ObservedObject var holidayData: HolidayDataController
    let appDelegate: QingLiAppDelegate

    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var columns = NavigationSplitViewVisibility.all

    private var palette: DesktopPalette { DesktopPalette(scheme: colorScheme) }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .frame(width: 190)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(190)
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider().overlay(palette.line)
                switch navigation.page {
                case .calendar:
                    DesktopDateBrowser(navigation: navigation, holidayData: holidayData, palette: palette)
                case .holidays:
                    DesktopHolidayOverview(navigation: navigation, holidayData: holidayData, palette: palette)
                case .subscription:
                    HolidaySubscriptionView(holidayData: holidayData)
                }
            }
            .background(palette.surface)
            .ignoresSafeArea(.container, edges: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .foregroundStyle(palette.ink)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            let open = openWindow
            appDelegate.reopenDesktop = {
                NSApplication.shared.activate()
                open(id: DesktopNavigation.windowID)
            }
            NSApplication.shared.activate()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("清历")
                .font(.system(size: 24, weight: .semibold))
                .tracking(3)
                .padding(.horizontal, 12)
                .padding(.top, 74)
            sectionLabel("浏览")
                .padding(.top, 23)
            sidebarButton(.calendar)
            sidebarButton(.holidays)
            sectionLabel("设置")
                .padding(.top, 17)
            sidebarButton(.subscription)
            Spacer()
            Text(coverage)
                .font(.system(size: 10))
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 12)
                .padding(.bottom, 23)
        }
        .padding(.horizontal, 16)
        .background(palette.sidebar)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var coverage: String {
        let years = holidayData.dataset.coveredYears.sorted()
        guard let first = years.first, let last = years.last else { return "暂无休班数据" }
        if years.count == last - first + 1 {
            return "数据覆盖至 \(last.formatted(.number.grouping(.never))) 年"
        }
        return "已覆盖 \(years.map(String.init).joined(separator: "、")) 年"
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10))
            .tracking(1)
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private func sidebarButton(_ page: DesktopNavigation.Page) -> some View {
        let selected = navigation.page == page
        return Button {
            navigation.page = page
        } label: {
            Text(page.rawValue)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(selected ? palette.sidebarSelection : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .padding(.vertical, 3)
    }

    private var toolbar: some View {
        HStack {
            Text(navigation.page.breadcrumb)
                .font(.system(size: 12))
                .foregroundStyle(palette.muted)
            Spacer()
            if navigation.page == .calendar {
                HStack(spacing: 2) {
                    ForEach(DesktopNavigation.CalendarMode.allCases, id: \.self) { mode in
                        let selected = navigation.mode == mode
                        Button {
                            navigation.mode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(selected ? palette.ink : palette.muted)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 4)
                                .background(selected ? palette.surface : .clear, in: RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(palette.line) }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("日历视图")
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 58)
    }
}
