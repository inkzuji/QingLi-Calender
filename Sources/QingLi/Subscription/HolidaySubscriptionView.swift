import SwiftUI
import QingLiCore

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
