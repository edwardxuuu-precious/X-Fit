import Charts
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledWorkout.plannedDate) private var schedules: [ScheduledWorkout]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var exercises: [Exercise]
    @Query private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var setLogs: [SetLog]

    @State private var workoutSessionID: UUID?
    @State private var showWorkout = false
    @State private var errorMessage: String?
    @State private var progressPeriod: TrainingProgressPeriod = CommandLine.arguments.contains(
        "--ui-testing-progress-month"
    ) ? .month : .week

    private var activeSession: WorkoutSession? {
        sessions.first { $0.status == .inProgress }
    }

    private var todaySchedules: [ScheduledWorkout] {
        schedules
            .filter { $0.plannedDate.isSameDay(as: .now) && $0.status != .skipped }
            .sorted { left, right in
                let leftOneOff = templates.first(where: { $0.id == left.templateID })?.isOneOff == true
                let rightOneOff = templates.first(where: { $0.id == right.templateID })?.isOneOff == true
                if leftOneOff != rightOneOff { return leftOneOff }
                if left.status != right.status { return left.status == .planned }
                return left.createdAt > right.createdAt
            }
    }

    private var upcomingSchedules: [ScheduledWorkout] {
        schedules.filter {
            $0.plannedDate > Date.now.startOfDay && $0.status == .planned
        }
        .prefix(3)
        .map { $0 }
    }

    private var progressSummary: TrainingProgressSummary {
        TrainingMetrics.progressSummary(
            period: progressPeriod,
            schedules: schedules,
            sessions: sessions,
            setLogs: setLogs
        )
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

                SectionHeader(title: "今日训练")

                if let activeSession {
                    resumeCard(activeSession)
                } else if let schedule = todaySchedules.first {
                    todayPlanCard(schedule)
                } else {
                    restDayCard
                }

                SectionHeader(title: "快捷入口")
                quickActions
                historySyncShortcut

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
        let summary = progressSummary

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(summary.period.title)进度")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("周期进度标题")
                    Text("完成率按计划，容量按已完成工作组")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 4)
                progressPeriodControl
            }

            HStack(spacing: 16) {
                NeonProgressRing(
                    progress: summary.completionProgress,
                    value: "\(Int((summary.completionProgress * 100).rounded()))%",
                    detail: summary.targetWorkouts == 0
                        ? "暂无计划"
                        : "\(summary.completedSessions)/\(summary.targetWorkouts) 次"
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(summary.period.title)完成率 \(Int((summary.completionProgress * 100).rounded()))%，完成 \(summary.completedSessions) 次，目标 \(summary.targetWorkouts) 次"
                )

                Rectangle()
                    .fill(AppTheme.line)
                    .frame(width: 1, height: 88)

                VStack(spacing: 12) {
                    dashboardMetric(
                        icon: "flame.fill",
                        tint: AppTheme.orange,
                        title: "完成训练",
                        value: "\(summary.completedSessions) 次"
                    )
                    dashboardMetric(
                        icon: "dumbbell.fill",
                        tint: AppTheme.accent,
                        title: "训练容量",
                        value: formattedVolume(summary.volume)
                    )
                }
            }

            Divider().overlay(AppTheme.line)

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.period.bucketSubtitle)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)

                progressVolumeChart(summary)
            }

            HStack(spacing: 0) {
                progressFootMetric(value: "\(summary.workingSets)", label: "工作组")
                progressFootMetric(value: "\(summary.activeMinutes)", label: "分钟")
                progressFootMetric(
                    value: summary.plannedWorkouts == 0 ? "—" : "\(summary.plannedWorkouts)",
                    label: "计划"
                )
            }

            Label(comparisonText(for: summary), systemImage: comparisonIcon(for: summary))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier("周期容量对比")
        }
        .cardSurface(padding: 18, cornerRadius: 20)
    }

    private var progressPeriodControl: some View {
        HStack(spacing: 2) {
            progressPeriodButton(.week)
            progressPeriodButton(.month)
        }
        .padding(3)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line, lineWidth: 1))
    }

    private func progressPeriodButton(_ period: TrainingProgressPeriod) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                progressPeriod = period
            }
        } label: {
            Text(period == .week ? "周" : "月")
                .font(.caption.bold())
                .foregroundStyle(progressPeriod == period ? .black : AppTheme.secondaryText)
                .frame(width: 34, height: 28)
                .background(
                    progressPeriod == period ? AppTheme.accent : .clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(period.title)
        .accessibilityAddTraits(progressPeriod == period ? .isSelected : [])
    }

    private func progressVolumeChart(_ summary: TrainingProgressSummary) -> some View {
        let ceiling = max(summary.buckets.map(\.volume).max() ?? 0, 1)

        return Chart(summary.buckets) { bucket in
            BarMark(
                x: .value("周期", bucket.label),
                y: .value("训练容量", bucket.volume)
            )
            .foregroundStyle(AppTheme.accent)
            .cornerRadius(4)
            .accessibilityLabel(
                "\(bucket.label)，\(Int(bucket.volume)) 公斤，\(bucket.completedSessions) 次训练，\(bucket.workingSets) 个工作组"
            )
        }
        .chartXAxis {
            AxisMarks(values: summary.buckets.map(\.label)) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                AxisTick().foregroundStyle(.clear)
                AxisGridLine().foregroundStyle(.clear)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(ceiling * 1.08))
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 96)
        .overlay {
            if summary.volume == 0 {
                Text("完成训练后生成容量柱图")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.bottom, 18)
            }
        }
        .accessibilityIdentifier("周期训练容量图")
    }

    private func progressFootMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedVolume(_ volume: Double) -> String {
        if volume >= 10_000 {
            return String(format: "%.1f 万 kg", volume / 10_000)
        }
        return "\(Int(volume).formatted()) kg"
    }

    private func comparisonText(for summary: TrainingProgressSummary) -> String {
        guard let change = summary.volumeChangePercent else {
            return "完成更多训练后建立与\(summary.period.previousTitle)同期的容量基线"
        }
        let rounded = Int(change.rounded())
        let sign = rounded > 0 ? "+" : ""
        return "较\(summary.period.previousTitle)同期训练容量 \(sign)\(rounded)%"
    }

    private func comparisonIcon(for summary: TrainingProgressSummary) -> String {
        guard let change = summary.volumeChangePercent else { return "circle.dotted" }
        if change > 0.5 { return "arrow.up.right" }
        if change < -0.5 { return "arrow.down.right" }
        return "arrow.right"
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "figure.cooldown")
                    .font(.title.bold())
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 58, height: 58)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text("今天还没有训练菜单")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("可以选择想练的肌群，让 X-Fit 根据近期记录推荐一套不重复的动作。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            NavigationLink(destination: DailyWorkoutBuilderView()) {
                Label("选择肌群并编排今天训练", systemImage: "wand.and.stars")
                    .neonButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var quickActions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            NavigationLink(destination: DailyWorkoutBuilderView()) {
                QuickActionTile(title: "编排", icon: "wand.and.stars", tint: AppTheme.accent)
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

    private var historySyncShortcut: some View {
        NavigationLink(destination: HistoricalWorkoutImportView()) {
            HStack(spacing: 13) {
                Image(systemName: "square.and.arrow.down")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("同步过去几周训练")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("导入 CSV，或前往训练历史逐次补录")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .cardSurface(padding: 14, cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("同步过去几周训练")
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
