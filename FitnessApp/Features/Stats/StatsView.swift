import Charts
import SwiftData
import SwiftUI

private struct DailyVolumePoint: Identifiable {
    let id = UUID()
    let date: Date
    let volume: Double
}

private struct StrengthPoint: Identifiable {
    let id = UUID()
    let date: Date
    let estimatedMax: Double
}

struct StatsView: View {
    @Query private var sessions: [WorkoutSession]
    @Query private var schedules: [ScheduledWorkout]
    @Query private var setLogs: [SetLog]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var selectedExerciseID: UUID?
    @State private var selectedSegment = 0

    private var completedSessions: [WorkoutSession] {
        sessions.filter { $0.status == .completed }
    }

    private var recentStart: Date {
        Date.now.addingDays(-6).startOfDay
    }

    private var recentSessions: [WorkoutSession] {
        completedSessions.filter { $0.startedAt >= recentStart }
    }

    private var recentSessionIDs: Set<UUID> {
        Set(recentSessions.map(\.id))
    }

    private var recentLogs: [SetLog] {
        setLogs.filter { $0.isCompleted && recentSessionIDs.contains($0.sessionID) }
    }

    private var completionRate: Int {
        let eligible = schedules.filter {
            $0.plannedDate >= recentStart && $0.plannedDate <= Date.now.startOfDay
        }
        guard !eligible.isEmpty else { return 0 }
        let completed = eligible.filter { $0.status == .completed }.count
        return Int((Double(completed) / Double(eligible.count) * 100).rounded())
    }

    private var activeMinutes: Int {
        recentSessions.compactMap { session in
            session.completedAt.map { max(1, Int($0.timeIntervalSince(session.startedAt) / 60)) }
        }.reduce(0, +)
    }

    private var availableExercises: [Exercise] {
        exercises.filter { exercise in
            setLogs.contains { $0.exerciseID == exercise.id && $0.isCompleted }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: "YOUR PERFORMANCE", title: "训练进度")
                segmentControl
                if selectedSegment == 0 {
                    workoutFrequencyCard
                    summaryGrid
                    goalProgressCard
                    strengthTrendCard
                    historyLink
                } else if selectedSegment == 1 {
                    workoutFrequencyCard
                    summaryGrid
                    strengthTrendCard
                    historyLink
                } else {
                    bodyStatsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if selectedExerciseID == nil {
                selectedExerciseID = availableExercises.first?.id
            }
        }
        .onChange(of: availableExercises.map(\.id)) { _, ids in
            if let selectedExerciseID, !ids.contains(selectedExerciseID) {
                self.selectedExerciseID = ids.first
            } else if selectedExerciseID == nil {
                selectedExerciseID = ids.first
            }
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 3) {
            segmentButton("概览", value: 0)
            segmentButton("训练", value: 1)
            segmentButton("身体数据", value: 2)
        }
        .padding(4)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.line, lineWidth: 1))
    }

    private func segmentButton(_ title: String, value: Int) -> some View {
        Button {
            selectedSegment = value
        } label: {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(selectedSegment == value ? .black : AppTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selectedSegment == value ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var workoutFrequencyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("训练频率")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("本周完成 \(recentSessions.count) 次训练")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text("本周")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }

            Chart(dailyVolumePoints) { point in
                BarMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("容量", max(point.volume, 0))
                )
                .foregroundStyle(
                    point.volume > 0
                    ? AnyShapeStyle(AppTheme.accent.gradient)
                    : AnyShapeStyle(AppTheme.elevatedSurface)
                )
                .cornerRadius(5)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .foregroundStyle(AppTheme.secondaryText)
                    AxisGridLine().foregroundStyle(.clear)
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(Color.clear)
            }
            .frame(height: 150)

            if recentSessions.isEmpty {
                Text("完成第一次训练后，这里会开始形成你的节奏。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .cardSurface()
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                title: "训练容量",
                value: "\(Int(TrainingMetrics.volume(for: recentLogs)))",
                detail: "近 7 天 · kg",
                systemImage: "flame.fill",
                tint: AppTheme.orange
            )
            MetricCard(
                title: "活跃时间",
                value: activeMinutes == 0 ? "0m" : "\(activeMinutes)m",
                detail: "近 7 天累计",
                systemImage: "timer",
                tint: AppTheme.purple
            )
        }
    }

    private var goalProgressCard: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("目标进度")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
                Text("保持训练节奏")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text("计划完成率按最近 7 天已到期训练计算。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                ProgressView(value: Double(completionRate), total: 100)
                    .tint(AppTheme.accent)
            }
            Spacer()
            NeonProgressRing(
                progress: Double(completionRate) / 100,
                value: "\(completionRate)%",
                detail: "计划"
            )
        }
        .cardSurface()
    }

    private var strengthTrendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("力量趋势")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("每次训练的最高估算 1RM")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()

                if !availableExercises.isEmpty {
                    Menu {
                        ForEach(availableExercises) { exercise in
                            Button(exercise.name) {
                                selectedExerciseID = exercise.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedExerciseName).lineLimit(1)
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                    }
                }
            }

            if strengthPoints.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 9) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title)
                            .foregroundStyle(AppTheme.accent)
                        Text("完成训练后显示力量曲线")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                }
                .frame(height: 130)
            } else {
                Chart(strengthPoints) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("估算 1RM", point.estimatedMax)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.28), AppTheme.accent.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("估算 1RM", point.estimatedMax)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(AppTheme.secondaryText) } }
                .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel().foregroundStyle(AppTheme.secondaryText) } }
                .frame(height: 180)
            }
        }
        .cardSurface()
    }

    private var historyLink: some View {
        NavigationLink(destination: HistoryView()) {
            HStack(spacing: 13) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.headline.bold())
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("完整训练历史")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("查看每次训练的动作、组数和容量")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var bodyStatsCard: some View {
        NavigationLink(destination: BodyMeasurementsView()) {
            VStack(spacing: 18) {
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 84, height: 84)
                    .background(AppTheme.accent.opacity(0.10), in: Circle())
                Text("身体数据")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("记录体重、体脂和围度，查看随训练变化的趋势。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.secondaryText)
                Label("打开身体记录", systemImage: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var dailyVolumePoints: [DailyVolumePoint] {
        (0..<7).map { offset in
            let date = recentStart.addingDays(offset)
            let sessionIDs = Set(recentSessions.filter { $0.startedAt.isSameDay(as: date) }.map(\.id))
            let logs = setLogs.filter { $0.isCompleted && sessionIDs.contains($0.sessionID) }
            return DailyVolumePoint(date: date, volume: TrainingMetrics.volume(for: logs))
        }
    }

    private var selectedExerciseName: String {
        exercises.first(where: { $0.id == selectedExerciseID })?.name ?? "选择动作"
    }

    private var strengthPoints: [StrengthPoint] {
        guard let selectedExerciseID else { return [] }
        let sessionByID = Dictionary(uniqueKeysWithValues: completedSessions.map { ($0.id, $0) })
        let relevantLogs = setLogs.filter {
            $0.exerciseID == selectedExerciseID && $0.isCompleted && sessionByID[$0.sessionID] != nil
        }
        let grouped = Dictionary(grouping: relevantLogs, by: \.sessionID)

        return grouped.compactMap { sessionID, logs in
            guard let session = sessionByID[sessionID],
                  let best = logs.max(by: {
                      TrainingMetrics.estimatedOneRepMax(weight: $0.actualWeight, reps: $0.actualReps)
                      < TrainingMetrics.estimatedOneRepMax(weight: $1.actualWeight, reps: $1.actualReps)
                  }) else { return nil }

            return StrengthPoint(
                date: session.startedAt,
                estimatedMax: TrainingMetrics.estimatedOneRepMax(weight: best.actualWeight, reps: best.actualReps)
            )
        }
        .sorted { $0.date < $1.date }
    }
}
