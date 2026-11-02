import Charts
import SwiftData
import SwiftUI

private struct DailyVolumePoint: Identifiable {
    let id = UUID()
    let date: Date
    let volume: Double
}

private enum TrainingTrendMode: String, CaseIterable, Identifiable {
    case overall
    case exercise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overall: return "总容量"
        case .exercise: return "按动作"
        }
    }
}

struct StatsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var sessions: [WorkoutSession]
    @Query private var schedules: [ScheduledWorkout]
    @Query private var setLogs: [SetLog]
    @Query private var sessionExercises: [SessionExercise]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var bodyMeasurements: [BodyMeasurement]

    @State private var selectedExerciseKey: String?
    @State private var trainingTrendMode: TrainingTrendMode = .overall
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

    private var volumeTrends: TrainingVolumeTrends {
        TrainingMetrics.volumeTrends(
            sessions: sessions,
            sessionExercises: sessionExercises,
            exercises: exercises,
            setLogs: setLogs
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                SprintPageHeader(title: "训练趋势", icon: "chart.xyaxis.line")
                segmentControl
                if selectedSegment == 0 {
                    workoutFrequencyCard
                    summaryGrid
                    goalProgressCard
                    volumeTrendCard
                    historyLink
                } else if selectedSegment == 1 {
                    workoutFrequencyCard
                    summaryGrid
                    volumeTrendCard
                    historyLink
                } else {
                    bodyStatsCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .sprintPage()
        .navigationTitle("训练趋势")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .environment(\.defaultMinListRowHeight, 52)
        .onAppear {
            if selectedExerciseKey == nil {
                selectedExerciseKey = volumeTrends.exercises.first?.key
            }
        }
        .onChange(of: volumeTrends.exercises.map(\.key)) { _, keys in
            if let selectedExerciseKey, !keys.contains(selectedExerciseKey) {
                self.selectedExerciseKey = keys.first
            } else if selectedExerciseKey == nil {
                selectedExerciseKey = keys.first
            }
        }
    }

    private var segmentControl: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            segmentButton("概览", value: 0)
            segmentButton("训练", value: 1)
            segmentButton("身体", value: 2)
        }
        .padding(4)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.line, lineWidth: 1))
    }

    private func segmentButton(_ title: String, value: Int) -> some View {
        Button {
            selectedSegment = value
        } label: {
            Label(title, systemImage: value == 0 ? "square.grid.2x2" : value == 1 ? "dumbbell" : "figure.arms.open")
                .font(.caption.bold())
                .foregroundStyle(selectedSegment == value ? AppTheme.ink : AppTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selectedSegment == value ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var workoutFrequencyCard: some View {
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return VStack(alignment: .leading, spacing: 16) {
            headerLayout {
                VStack(alignment: .leading, spacing: 3) {
                    Label("近 7 天容量", systemImage: "dumbbell")
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text("完成 \(recentSessions.count) 次训练")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text("近 7 天")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink)
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
            .frame(height: 150).sprintChart()

            if recentSessions.isEmpty {
                Text("完成训练后显示容量")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .cardSurface()
    }

    private var summaryGrid: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) { summaryValues }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { summaryValues }
                    VStack(alignment: .leading, spacing: 16) { summaryValues }
                }
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private var summaryValues: some View {
        FatLossMetric(value: "\(Int(TrainingMetrics.volume(for: recentLogs, sessionExercises: sessionExercises)).formatted()) kg", label: "近 7 天容量")
        FatLossMetric(value: "\(activeMinutes) 分钟", label: "累计训练时长")
    }

    private var goalProgressCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return VStack(alignment: .leading, spacing: 10) {
            layout {
                Label("到期计划", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text("\(completionRate)%").font(.headline.monospacedDigit()).foregroundStyle(AppTheme.ink)
            }
            ProgressView(value: Double(completionRate), total: 100).tint(AppTheme.ink)
        }.cardSurface()
    }

    private var volumeTrendCard: some View {
        let selectorLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 4))
        let detailLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label("容量趋势", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(
                    trainingTrendMode == .overall
                        ? "已完成的 kg 动作"
                        : "所选动作每次训练的训练量 · \(selectedExerciseTrend?.unit.symbol ?? "")"
                )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            selectorLayout {
                ForEach(TrainingTrendMode.allCases) { mode in
                    Button {
                        trainingTrendMode = mode
                    } label: {
                        Text(mode.title)
                            .font(.caption.bold())
                            .foregroundStyle(trainingTrendMode == mode ? AppTheme.ink : AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                trainingTrendMode == mode ? AppTheme.accent : .clear,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.title)
                    .accessibilityIdentifier(mode == .overall ? "查看总容量" : "按动作查看")
                }
            }
            .padding(3)
            .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 11))

            if trainingTrendMode == .exercise, !volumeTrends.exercises.isEmpty {
                Menu {
                    ForEach(volumeTrends.exercises) { exercise in
                        Button("\(exercise.name) · \(exercise.unit.symbol)") {
                            selectedExerciseKey = exercise.key
                        }
                    }
                } label: {
                    detailLayout {
                        Text("动作")
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(selectedExerciseTrend?.name ?? "选择动作")
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        Image(systemName: "chevron.down")
                            .foregroundStyle(AppTheme.ink)
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 11))
                }
                .accessibilityLabel("选择趋势动作")
                .accessibilityIdentifier("选择趋势动作")
            }

            if displayedTrendPoints.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 9) {
                        SprintIcon(systemName: "chart.line.uptrend.xyaxis", size: 48)
                        Text(trainingTrendMode == .overall ? "完成训练后显示容量变化" : "这个动作还没有完成组记录")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                }
                .frame(height: 130)
            } else {
                Chart(displayedTrendPoints) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("训练容量", point.volume)
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
                        y: .value("训练容量", point.volume)
                    )
                    .foregroundStyle(AppTheme.ink)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("训练容量", point.volume)
                    )
                    .foregroundStyle(AppTheme.ink)
                    .symbolSize(42)
                    .accessibilityLabel(
                        "\(point.date.formatted(date: .abbreviated, time: .omitted))，\(Int(point.volume)) \(displayedTrendUnit.symbol)，\(point.completedSets) 个完成组"
                    )
                }
                .chartYScale(domain: 0...displayedTrendCeiling)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.month().day())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(AppTheme.line)
                        AxisValueLabel().foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(height: 180).sprintChart()
                .accessibilityIdentifier("训练容量趋势图")

                detailLayout {
                    Text("\(displayedTrendSessionCount) 次训练 · \(displayedTrendCompletedSets) 个完成组")
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text("累计 \(formattedTrendVolume(displayedTrendTotalVolume, unit: displayedTrendUnit))")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("趋势记录摘要")

                if displayedTrendTotalVolume == 0, displayedTrendCompletedSets > 0 {
                    Text("这些完成组没有可计量的数据，动作记录已保留，但训练量为 0 \(displayedTrendUnit.symbol)。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .cardSurface()
        .accessibilityIdentifier("训练容量趋势卡片")
    }

    private var historyLink: some View {
        NavigationLink(destination: HistoryView()) {
            FatLossNavigationRow(title: "完整训练历史", icon: "clock.arrow.circlepath")
        }.buttonStyle(.plain)
    }

    private var bodyStatsCard: some View {
        BodyWeightTrendCard(measurements: bodyMeasurements, showsHistoryLink: true)
    }

    private var dailyVolumePoints: [DailyVolumePoint] {
        (0..<7).map { offset in
            let date = recentStart.addingDays(offset)
            let sessionIDs = Set(recentSessions.filter { $0.startedAt.isSameDay(as: date) }.map(\.id))
            let logs = setLogs.filter { $0.isCompleted && sessionIDs.contains($0.sessionID) }
            return DailyVolumePoint(
                date: date,
                volume: TrainingMetrics.volume(
                    for: logs,
                    sessionExercises: sessionExercises
                )
            )
        }
    }

    private var selectedExerciseTrend: ExerciseVolumeTrend? {
        guard let selectedExerciseKey else { return volumeTrends.exercises.first }
        return volumeTrends.exercises.first(where: { $0.key == selectedExerciseKey })
    }

    private var displayedTrendPoints: [TrainingVolumeTrendPoint] {
        trainingTrendMode == .overall ? volumeTrends.overall : selectedExerciseTrend?.points ?? []
    }

    private var displayedTrendCeiling: Double {
        max((displayedTrendPoints.map(\.volume).max() ?? 0) * 1.12, 1)
    }

    private var displayedTrendTotalVolume: Double {
        if trainingTrendMode == .exercise {
            return selectedExerciseTrend?.totalVolume ?? 0
        }
        return displayedTrendPoints.reduce(0) { $0 + $1.volume }
    }

    private var displayedTrendCompletedSets: Int {
        if trainingTrendMode == .exercise {
            return selectedExerciseTrend?.completedSets ?? 0
        }
        return displayedTrendPoints.reduce(0) { $0 + $1.completedSets }
    }

    private var displayedTrendSessionCount: Int {
        if trainingTrendMode == .exercise {
            return selectedExerciseTrend?.sessionCount ?? 0
        }
        return displayedTrendPoints.reduce(0) { $0 + $1.sessionCount }
    }

    private var displayedTrendUnit: ExerciseVolumeUnit {
        trainingTrendMode == .exercise ? selectedExerciseTrend?.unit ?? .kilogram : .kilogram
    }

    private func formattedTrendVolume(_ volume: Double, unit: ExerciseVolumeUnit) -> String {
        if volume >= 10_000 {
            return String(format: "%.1f 万 %@", volume / 10_000, unit.symbol)
        }
        return "\(Int(volume).formatted()) \(unit.symbol)"
    }
}
