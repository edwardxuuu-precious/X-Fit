import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query private var sessions: [WorkoutSession]
    @Query private var schedules: [ScheduledWorkout]
    @State private var showSettings = false

    private var completedSessions: [WorkoutSession] {
        sessions.filter { $0.status == .completed }
    }

    private var activeMinutes: Int {
        completedSessions.compactMap { session in
            session.completedAt.map { max(1, Int($0.timeIntervalSince(session.startedAt) / 60)) }
        }.reduce(0, +)
    }

    private var completedPlans: Int {
        schedules.filter { $0.status == .completed }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: "PERSONAL CENTER",
                    title: "我的",
                    trailingSystemImage: "gearshape.fill",
                    trailingAccessibilityLabel: "打开设置",
                    trailingAction: { showSettings = true }
                )
                profileCard
                targetCard

                SectionHeader(title: "健康概览")
                NutritionPreviewCard()

                SectionHeader(title: "更多")
                VStack(spacing: 0) {
                    NavigationLink(destination: HistoryView()) {
                        settingsRow(icon: "clock.arrow.circlepath", title: "训练历史", subtitle: "查看全部完成记录")
                    }
                    Divider().overlay(AppTheme.line).padding(.leading, 54)
                    NavigationLink(destination: NutritionView()) {
                        settingsRow(icon: "fork.knife", title: "营养记录", subtitle: "记录热量和宏量营养")
                    }
                    Divider().overlay(AppTheme.line).padding(.leading, 54)
                    NavigationLink(destination: BodyMeasurementsView()) {
                        settingsRow(icon: "figure.arms.open", title: "身体数据", subtitle: "记录体重、体脂和围度")
                    }
                    Divider().overlay(AppTheme.line).padding(.leading, 54)
                    NavigationLink(destination: AppSettingsView()) {
                        settingsRow(icon: "gearshape.fill", title: "设置与数据", subtitle: "提醒、健康和备份")
                    }
                }
                .cardSurface(padding: 0, cornerRadius: 18)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            AppSettingsView()
        }
    }

    private var profileCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 15) {
                ZStack {
                    Circle().fill(AppTheme.elevatedSurface)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 72, height: 72)
                .overlay(Circle().stroke(AppTheme.accent.opacity(0.45), lineWidth: 2))

                VStack(alignment: .leading, spacing: 5) {
                    Text("训练者")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("持续、记录、进步")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Label("本地训练档案", systemImage: "checkmark.seal.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
            }

            HStack(spacing: 0) {
                profileMetric("\(completedSessions.count)", label: "训练次数")
                profileMetric("\(activeMinutes)", label: "训练分钟")
                profileMetric("\(completedPlans)", label: "完成计划")
            }
        }
        .cardSurface(padding: 18, cornerRadius: 20)
    }

    private func profileMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.line).frame(width: 1, height: 28)
        }
    }

    private var targetCard: some View {
        HStack(spacing: 18) {
            NeonProgressRing(
                progress: min(Double(completedSessions.count) / 12, 1),
                value: "\(min(completedSessions.count, 12))/12",
                detail: "训练"
            )
            VStack(alignment: .leading, spacing: 7) {
                Text("阶段目标")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                Text("完成 12 次高质量训练")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text("不用追求完美，只要每一次都留下真实记录。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 38, height: 38)
                .background(AppTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(14)
    }
}
