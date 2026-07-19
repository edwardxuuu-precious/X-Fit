import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledWorkout.plannedDate) private var schedules: [ScheduledWorkout]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var workoutSessionID: UUID?
    @State private var showWorkout = false
    @State private var errorMessage: String?

    private var activeSession: WorkoutSession? {
        sessions.first { $0.status == .inProgress }
    }

    private var todaySchedules: [ScheduledWorkout] {
        schedules.filter { $0.plannedDate.isSameDay(as: .now) && $0.status != .skipped }
    }

    private var upcomingSchedules: [ScheduledWorkout] {
        schedules.filter {
            $0.plannedDate > Date.now.startOfDay && $0.status == .planned
        }
        .prefix(3)
        .map { $0 }
    }

    private var currentWeekSchedules: [ScheduledWorkout] {
        let start = Date.now.addingDays(-6).startOfDay
        return schedules.filter { $0.plannedDate >= start && $0.plannedDate <= Date.now.startOfDay }
    }

    private var weeklyCompletedCount: Int {
        currentWeekSchedules.filter { $0.status == .completed }.count
    }

    private var weeklyProgress: Double {
        guard !currentWeekSchedules.isEmpty else { return 0 }
        return Double(weeklyCompletedCount) / Double(currentWeekSchedules.count)
    }

    private var completedMinutes: Int {
        sessions
            .filter { $0.status == .completed && $0.startedAt >= Date.now.addingDays(-6).startOfDay }
            .compactMap { session -> Int? in
                guard let end = session.completedAt else { return nil }
                return max(1, Int(end.timeIntervalSince(session.startedAt) / 60))
            }
            .reduce(0, +)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                ScreenHeader(
                    eyebrow: "你好，训练者",
                    title: greeting,
                    trailingSystemImage: "bell.fill"
                )

                weeklyDashboard

                SectionHeader(title: "今日训练", actionTitle: "查看全部")

                if let activeSession {
                    resumeCard(activeSession)
                } else if let schedule = todaySchedules.first {
                    todayPlanCard(schedule)
                } else {
                    restDayCard
                }

                SectionHeader(title: "快捷入口")
                quickActions

                if !upcomingSchedules.isEmpty {
                    upcomingSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showWorkout) {
            if let workoutSessionID {
                ActiveWorkoutView(sessionID: workoutSessionID)
            }
        }
        .alert("无法开始训练", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "准备好突破了吗？"
        case 12..<18: return "今天，继续变强"
        default: return "完成今天的目标"
        }
    }

    private var weeklyDashboard: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("本周进度")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
                NeonProgressRing(
                    progress: weeklyProgress,
                    value: "\(Int((weeklyProgress * 100).rounded()))%",
                    detail: "\(weeklyCompletedCount)/\(max(currentWeekSchedules.count, 1))"
                )
            }

            Rectangle()
                .fill(AppTheme.line)
                .frame(width: 1, height: 88)

            VStack(spacing: 14) {
                dashboardMetric(
                    icon: "flame.fill",
                    tint: AppTheme.orange,
                    title: "完成训练",
                    value: "\(weeklyCompletedCount) 次"
                )
                dashboardMetric(
                    icon: "timer",
                    tint: AppTheme.accent,
                    title: "活跃时间",
                    value: completedMinutes == 0 ? "等待记录" : "\(completedMinutes) 分钟"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 18, cornerRadius: 20)
    }

    private func dashboardMetric(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
    }

    private func resumeCard(_ session: WorkoutSession) -> some View {
        ZStack(alignment: .bottomLeading) {
            HeroWorkoutImage()
                .frame(height: 270)
                .clipped()
            AppTheme.heroGradient

            VStack(alignment: .leading, spacing: 12) {
                Label("训练进行中", systemImage: "bolt.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                Text(session.templateName)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("开始于 \(session.startedAt, format: .dateTime.hour().minute()) · 记录已自动保存")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))

                Button {
                    openSession(session.id)
                } label: {
                    Label("继续训练", systemImage: "play.fill")
                        .neonButtonStyle()
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.line, lineWidth: 1))
    }

    private func todayPlanCard(_ schedule: ScheduledWorkout) -> some View {
        let items = items(for: schedule)
        let totalSets = items.reduce(0) { $0 + $1.targetSets }

        return ZStack(alignment: .bottomLeading) {
            HeroWorkoutImage()
                .frame(height: 310)
                .clipped()
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.48), Color.black.opacity(0.98)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 13) {
                Text(schedule.status == .completed ? "今日已完成" : "TODAY'S WORKOUT")
                    .font(.caption2.weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.accent)
                Text(schedule.templateName)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text(items.prefix(3).map { exerciseName(for: $0.exerciseID) }.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)

                HStack(spacing: 0) {
                    heroMetric("\(items.count)", label: "动作")
                    heroMetric("\(max(25, totalSets * 3))", label: "分钟")
                    heroMetric("\(totalSets)", label: "工作组")
                }

                Button {
                    start(schedule)
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: schedule.status == .completed ? "checkmark" : "play.fill")
                        Text(schedule.status == .completed ? "训练已完成" : "开始训练")
                        Spacer()
                    }
                    .neonButtonStyle()
                }
                .disabled(schedule.status == .completed)
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.line, lineWidth: 1))
    }

    private func heroMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.line).frame(width: 1, height: 26)
        }
    }

    private var restDayCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.cooldown")
                .font(.title.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 58, height: 58)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text("今天是恢复日")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text("轻度活动、补水和睡眠，也是训练计划的一部分。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var quickActions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            NavigationLink(destination: PlanView()) {
                QuickActionTile(title: "动作", icon: "figure.strengthtraining.traditional", tint: AppTheme.accent)
            }
            NavigationLink(destination: NutritionView()) {
                QuickActionTile(title: "营养", icon: "fork.knife", tint: AppTheme.orange)
            }
            NavigationLink(destination: StatsView()) {
                QuickActionTile(title: "进度", icon: "chart.line.uptrend.xyaxis", tint: AppTheme.purple)
            }
            NavigationLink(destination: ScheduleView()) {
                QuickActionTile(title: "日程", icon: "calendar", tint: .pink)
            }
        }
        .buttonStyle(.plain)
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "接下来")
                Spacer()
                NavigationLink("管理日程", destination: ScheduleView())
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }

            ForEach(upcomingSchedules) { schedule in
                HStack(spacing: 14) {
                    VStack(spacing: 0) {
                        Text(schedule.plannedDate, format: .dateTime.day())
                            .font(.title3.weight(.black).monospacedDigit())
                        Text(schedule.plannedDate, format: .dateTime.weekday(.short))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 52)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(schedule.templateName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("\(items(for: schedule).count) 个动作 · 约 \(max(25, items(for: schedule).count * 10)) 分钟")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .cardSurface()
    }

    private func items(for schedule: ScheduledWorkout) -> [TemplateExercise] {
        templateExercises
            .filter { $0.templateID == schedule.templateID }
            .sorted { $0.order < $1.order }
    }

    private func exerciseName(for id: UUID) -> String {
        exercises.first(where: { $0.id == id })?.name ?? "未知动作"
    }

    private func start(_ schedule: ScheduledWorkout) {
        do {
            let sessionID = try WorkoutService.start(schedule: schedule, in: modelContext)
            openSession(sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openSession(_ id: UUID) {
        workoutSessionID = id
        showWorkout = true
    }
}

private struct QuickActionTile: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.headline.bold())
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(AppTheme.line, lineWidth: 1))
    }
}
