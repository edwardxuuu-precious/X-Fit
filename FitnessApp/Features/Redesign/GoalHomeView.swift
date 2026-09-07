import Charts
import SwiftData
import SwiftUI

struct GoalWeightComparison {
    let current: FatLossWeightAverage
    let previous: FatLossWeightAverage

    var changeKg: Double? {
        guard current.recordedDays >= 3, previous.recordedDays >= 3,
              let currentValue = current.value, let previousValue = previous.value,
              currentValue.isFinite, previousValue.isFinite else { return nil }
        return currentValue - previousValue
    }
}

struct GoalHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @Query private var revisions: [ProgramTargetRevision]
    @Query private var sessions: [WorkoutSession]
    @Query private var schedules: [ScheduledWorkout]
    @Query private var bodyCheckIns: [DailyBodyCheckIn]
    @Query private var dailyLogs: [ProgramDailyLog]
    @State private var showsWeight = false
    @State private var showsFeeling = false
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .title) private var currentWeightNumberSize = 36

    private var program: FatLossProgram? { programs.first { $0.statusRaw == "active" } }
    private var today: Date { FatLossCalendar.day(.now) }
    private var weekStart: Date { FatLossCalendar.adding(-6, to: today) }
    private var todayCheckIn: DailyBodyCheckIn? {
        bodyCheckIns.filter { FatLossCalendar.sameDay($0.date, today) }
            .max { $0.updatedAt < $1.updatedAt }
    }
    private var feelingSummary: String {
        guard let checkIn = todayCheckIn else { return "记录今日体感" }
        let title = ConditionScorePresentation.shortTitle(for: checkIn.conditionScore)
        let regions = Set(checkIn.bodyMarkers.map(\.regionID)).count
        return regions > 0 ? "\(title) · \(regions) 处不适" : title
    }
    private var weights: [BodyWeightDailyValue] {
        BodyMeasurementService.dailyRepresentativeWeights(from: measurements, calendar: FatLossCalendar.calendar)
            .filter { $0.date <= today }
    }
    private var average: FatLossWeightAverage { FatLossService.average(endingOn: today, values: weights) }
    private var previousAverage: FatLossWeightAverage {
        FatLossService.average(endingOn: FatLossCalendar.adding(-7, to: today), values: weights)
    }
    private var averageChange: Double? {
        GoalWeightComparison(current: average, previous: previousAverage).changeKg
    }
    private var recentWorkouts: [WorkoutSession] {
        sessions.filter {
            $0.status == .completed
                && FatLossCalendar.day($0.completedAt ?? $0.plannedDate) >= weekStart
                && FatLossCalendar.day($0.completedAt ?? $0.plannedDate) <= today
        }
    }
    private var dueSchedules: [ScheduledWorkout] {
        schedules.filter {
            FatLossCalendar.day($0.plannedDate) >= weekStart
                && FatLossCalendar.day($0.plannedDate) <= today
                && $0.status != .skipped
        }
    }
    private var recentWaist: BodyMeasurement? {
        measurements.first { $0.date <= .now && $0.waistCm != nil }
    }
    private var todayDailyLog: ProgramDailyLog? {
        guard let program else { return nil }
        return dailyLogs.filter { $0.programID == program.id && FatLossCalendar.sameDay($0.date, today) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let program {
                    goalTrajectory(program)
                    supportMetrics(program)
                    NavigationLink(destination: MuscleCoverageView()) {
                        GoalWideLink(
                            eyebrow: "实际完成记录",
                            title: "训练肌群分布",
                            detail: "按完成工作组查看训练覆盖",
                            icon: "figure.strengthtraining.traditional"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("目标-训练分布")
                    nutritionStatus(program)
                    secondaryLinks(program)
                } else {
                    FatLossIntroductionView { _ = try FatLossService.createProgram(in: context) }
                    feelingEntry
                    NavigationLink(destination: StatsView()) {
                        FatLossNavigationRow(title: "查看已有训练趋势", icon: "chart.xyaxis.line")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .fatLossCalendar()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsWeight) {
            QuickBodyWeightEntryView().preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showsFeeling) {
            NavigationStack {
                DailyBodyCheckInEditor(checkIn: todayCheckIn, date: today)
            }
            .preferredColorScheme(.dark)
        }
        .fatLossError($errorMessage)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("X-FIT / PROGRESS")
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(AppTheme.secondaryText)
                Text("目标")
                    .font(AppTheme.pageTitle)
                    .foregroundStyle(AppTheme.posterWarmWhite)
            }
            Spacer()
            if let program {
                NavigationLink(destination: FatLossTargetsView(program: program)) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.045), in: Circle())
                }
                .accessibilityLabel("目标与健康档案")
                .accessibilityIdentifier("目标与健康档案")
            }
        }
    }

    private var feelingEntry: some View {
        Button { showsFeeling = true } label: {
            FatLossNavigationRow(
                title: feelingSummary,
                icon: "figure.stand",
                trailing: todayCheckIn == nil ? nil : "今日体感"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("目标-记录体感")
    }

    private func targetRevision(_ program: FatLossProgram) -> ProgramTargetRevision? {
        revisions.filter { $0.programID == program.id && $0.effectiveDate <= max(today, program.startDate) }
            .sorted {
                $0.effectiveDate == $1.effectiveDate
                    ? $0.createdAt > $1.createdAt
                    : $0.effectiveDate > $1.effectiveDate
            }
            .first
    }

    private func targetWeight(_ program: FatLossProgram) -> Double? {
        let current = targetRevision(program)
        return current == nil ? program.targetWeightKg : current?.targetWeightKg
    }

    private func goalTrajectory(_ program: FatLossProgram) -> some View {
        let target = targetWeight(program)
        let points = weights.filter { $0.date >= weekStart }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(program.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.posterWarmWhite)
                    Text("\(FatLossCalendar.label(program.startDate)) — \(FatLossCalendar.label(program.endDate))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Text(phase(program))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.accent.opacity(0.11), in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("最近 7 日均重")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(average.value.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.system(size: currentWeightNumberSize, weight: .semibold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .foregroundStyle(AppTheme.posterWarmWhite)
                        Text("kg")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("最近 7 日均重")
                    .accessibilityValue(average.value.map { String(format: "%.1f kg", $0) } ?? "数据不足")
                    .accessibilityIdentifier("目标-当前均重")
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 7) {
                    Text("目标参照")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(target.map { String(format: "%.1f kg", $0) } ?? "待设定")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                    Text("记录 \(average.recordedDays)/7 天")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.posterWarmWhite)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.055), in: Capsule())
                        .accessibilityIdentifier("目标-称重覆盖率")
                        .accessibilityValue("\(average.recordedDays)/7 天")
                }
            }

            weightChart(points)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: changeIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(changeColor)
                Text(changeText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.posterWarmWhite)
                    .accessibilityIdentifier(averageChange == nil ? "目标-变化数据不足" : "目标-均重变化")
                Spacer(minLength: 0)
            }

            let actions = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            actions {
                Button { showsWeight = true } label: {
                    Label("记录体重", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("目标-记录体重")

                NavigationLink(destination: FatLossReviewView(program: program)) {
                    Label("本周复盘", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.posterWarmWhite)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(AppTheme.line, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("减脂每周复盘")
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.elevatedSurface, AppTheme.surface.opacity(0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(AppTheme.accent)
                .frame(width: 42, height: 3)
                .padding(.leading, 18)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.065), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("目标-主目标")
    }

    @ViewBuilder
    private func weightChart(_ points: [BodyWeightDailyValue]) -> some View {
        if points.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(AppTheme.secondaryText)
                Text("记录体重后生成 7 日轨迹")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 126)
            .background(Color.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("目标-七日均重")
        } else {
            let values = points.map(\.weightKg)
            let lower = (values.min() ?? 0) - 0.35
            let upper = (values.max() ?? 0) + 0.35
            Chart(points) { point in
                AreaMark(
                    x: .value("日期", point.date),
                    yStart: .value("图表下界", lower),
                    yEnd: .value("实测体重", point.weightKg)
                )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.18), AppTheme.accent.opacity(0.015)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                LineMark(x: .value("日期", point.date), y: .value("实测体重", point.weightKg))
                    .foregroundStyle(AppTheme.posterWarmWhite)
                    .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("日期", point.date), y: .value("实测体重", point.weightKg))
                    .foregroundStyle(point.date == points.last?.date ? AppTheme.accent : AppTheme.posterWarmWhite.opacity(0.62))
                    .symbolSize(point.date == points.last?.date ? 42 : 16)
            }
            .chartYScale(domain: lower...upper)
            .chartXAxis {
                AxisMarks(values: [points.first?.date, points.last?.date].compactMap { $0 }) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                        .foregroundStyle(AppTheme.secondaryText)
                    AxisTick().foregroundStyle(.clear)
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(Color.black.opacity(0.10))
            }
            .frame(height: 142)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("近7个自然日实测体重")
            .accessibilityIdentifier("目标-七日均重")
        }
    }

    private func supportMetrics(_ program: FatLossProgram) -> some View {
        VStack(spacing: 10) {
            metricRow(
                NavigationLink(destination: StatsView()) {
                    GoalMetricTile(
                        title: "训练执行",
                        value: "\(recentWorkouts.count) 次",
                        detail: trainingDetail,
                        icon: "bolt.fill",
                        tint: AppTheme.accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("目标-力量趋势"),
                NavigationLink(destination: BodyMeasurementsView()) {
                    GoalMetricTile(
                        title: "腰围",
                        value: recentWaist?.waistCm.map { String(format: "%.1f cm", $0) } ?? "未记录",
                        detail: recentWaist.map { FatLossCalendar.label($0.date) } ?? "建立身体基线",
                        icon: "ruler",
                        tint: AppTheme.posterWarmWhite
                    )
                }
                .buttonStyle(.plain)
            )

            metricRow(
                NavigationLink(destination: FatLossDailyEditor(program: program, date: today)) {
                    GoalMetricTile(
                        title: "步数 · 睡眠",
                        value: dailyLogValue,
                        detail: dailyLogDetail,
                        icon: "moon.zzz.fill",
                        tint: AppTheme.posterWarmWhite
                    )
                }
                .buttonStyle(.plain)
                .disabled(!program.contains(today))
                .accessibilityIdentifier("目标-日常记录"),
                Button { showsFeeling = true } label: {
                    GoalMetricTile(
                        title: "今日体感",
                        value: todayCheckIn.map { ConditionScorePresentation.shortTitle(for: $0.conditionScore) } ?? "待记录",
                        detail: feelingDetail,
                        icon: "figure.stand",
                        tint: todayCheckIn == nil ? AppTheme.secondaryText : AppTheme.accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("目标-记录体感")
            )
        }
    }

    private func metricRow<First: View, Second: View>(_ first: First, _ second: Second) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            first.frame(maxWidth: .infinity)
            second.frame(maxWidth: .infinity)
        }
    }

    private func nutritionStatus(_ program: FatLossProgram) -> some View {
        NavigationLink(destination: FatLossTargetsView(program: program)) {
            HStack(spacing: 10) {
                Image(systemName: targetRevision(program)?.isNutritionConfirmed == true ? "checkmark.shield.fill" : "info.circle.fill")
                    .foregroundStyle(targetRevision(program)?.isNutritionConfirmed == true ? AppTheme.accent : AppTheme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(targetRevision(program)?.isNutritionConfirmed == true ? "营养目标已确认" : "营养目标待确认")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.posterWarmWhite)
                    Text(targetRevision(program)?.isNutritionConfirmed == true ? "查看当前目标版本" : "医学参数未知，不计算剩余额度")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 62)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func secondaryLinks(_ program: FatLossProgram) -> some View {
        VStack(spacing: 0) {
            NavigationLink(destination: FatLossTimelineView(program: program)) {
                FatLossNavigationRow(title: "完整周期记录", icon: "calendar")
            }
            .accessibilityIdentifier("目标-完整周期")
            Divider().overlay(AppTheme.line)
            NavigationLink(destination: FatLossTargetsView(program: program)) {
                FatLossNavigationRow(title: "目标历史与健康资料", icon: "heart.text.clipboard")
            }
            Divider().overlay(AppTheme.line)
            NavigationLink(destination: BodyMeasurementsView()) {
                FatLossNavigationRow(title: "身体数据", icon: "ruler")
            }
        }
        .buttonStyle(.plain)
    }

    private var trainingDetail: String {
        dueSchedules.isEmpty
            ? "近 7 天 · 未安排到期计划"
            : "到期计划 \(dueSchedules.filter { $0.status == .completed }.count)/\(dueSchedules.count)"
    }

    private var dailyLogValue: String {
        guard let log = todayDailyLog else { return "待记录" }
        if let steps = log.steps { return "\(steps.formatted()) 步" }
        if let sleep = log.sleepHours { return String(format: "%.1f 小时", sleep) }
        return "待补充"
    }

    private var dailyLogDetail: String {
        guard let log = todayDailyLog else { return "记录今日活动" }
        var values: [String] = []
        if let sleep = log.sleepHours { values.append(String(format: "睡眠 %.1fh", sleep)) }
        if let bloating = log.bloatingScore { values.append("腹胀 \(bloating)/3") }
        return values.isEmpty ? "补充睡眠与腹胀" : values.joined(separator: " · ")
    }

    private var feelingDetail: String {
        guard let checkIn = todayCheckIn else { return "记录身体状态" }
        let regions = Set(checkIn.bodyMarkers.map(\.regionID)).count
        return regions == 0 ? "无部位标记" : "\(regions) 处不适标记"
    }

    private var changeText: String {
        guard let change = averageChange else {
            return average.recordedDays < 3 ? "记录不足 3 天，暂不判断" : "前 7 天记录不足，暂不比较"
        }
        let rounded = (change * 10).rounded() / 10
        return rounded == 0
            ? "较前 7 天持平 · 0.0 kg"
            : "较前 7 天 \(String(format: "%+.1f", rounded)) kg"
    }

    private var changeIcon: String {
        guard let change = averageChange else { return "info.circle.fill" }
        if change < 0 { return "arrow.down.right" }
        if change > 0 { return "arrow.up.right" }
        return "arrow.right"
    }

    private var changeColor: Color {
        guard let change = averageChange else { return AppTheme.secondaryText }
        if change < 0 { return AppTheme.accent }
        if change > 0 { return AppTheme.orange }
        return AppTheme.secondaryText
    }

    private func phase(_ program: FatLossProgram) -> String {
        if today < program.startDate { return "待开始" }
        if today >= program.endDate { return "周期回顾" }
        return "第 \(program.weekNumber(on: today)) / 13 周"
    }
}

private struct GoalMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.posterWarmWhite)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

private struct GoalWideLink: View {
    let eyebrow: String
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.posterWarmWhite)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(15)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}
