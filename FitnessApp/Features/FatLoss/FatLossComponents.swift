import SwiftUI

struct FatLossProgressLink: View {
    var body: some View {
        NavigationLink(destination: FatLossDashboardView()) {
            HStack(spacing: 14) {
                SprintIcon(systemName: "chart.xyaxis.line", size: 48, prominent: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("减脂周期").font(.headline).foregroundStyle(AppTheme.ink)
                    Text("体重 · 餐食 · 训练")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.secondaryText)
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("打开减脂周期")
    }
}

struct FatLossMetric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(AppTheme.ink)
            Text(label).font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FatLossNote: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption).foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FatLossNavigationRow: View {
    let title: String
    let icon: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 13) {
            SprintIcon(systemName: icon, size: 36)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(AppTheme.secondaryText)
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
    }
}

struct FatLossQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minHeight: 44).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    func fatLossInput() -> some View {
        scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成输入") { KeyboardDismissal.dismiss() }
                        .accessibilityIdentifier("减脂完成输入")
                }
            }
    }

    func fatLossCalendar() -> some View {
        environment(\.calendar, FatLossCalendar.calendar)
            .environment(\.timeZone, FatLossCalendar.calendar.timeZone)
            .environment(\.defaultMinListRowHeight, 52)
            .buttonStyle(FatLossQuietButtonStyle())
            .sprintPage()
    }

    func fatLossError(_ message: Binding<String?>) -> some View {
        alert("未能保存", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("知道了", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "请重试")
        }
    }
}
