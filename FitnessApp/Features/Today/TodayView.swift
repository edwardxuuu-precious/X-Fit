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
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]
    @Query(sort: \DailyBodyCheckIn.date, order: .reverse) private var bodyCheckIns: [DailyBodyCheckIn]

    @State private var workoutSessionID: UUID?
    @State private var showWorkout = false
    @State private var showBodyCheckIn = false
    @State private var errorMessage: String?

    private var activeSession: WorkoutSession? {
        sessions.first { $0.status == .inProgress }
    }

    private var todayBodyCheckIn: DailyBodyCheckIn? {
        bodyCheckIns.first { $0.date.isSameDay(as: .now) }
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

    private var latestCompletedSession: WorkoutSession? {
        sessions
            .filter { $0.status == .completed }
            .max { left, right in
                (left.completedAt ?? left.startedAt) < (right.completedAt ?? right.startedAt)
            }
    }

    private var recentVolumePoints: [TrainingVolumeTrendPoint] {
        TrainingMetrics.recentOverallVolumePoints(
            through: .now,
            limit: 6,
            sessions: sessions,
            sessionExercises: sessionExercises,
            exercises: exercises,
            setLogs: setLogs
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                todayHeader

                if let activeSession {
                    resumeCard(activeSession)
                } else if let schedule = todaySchedules.first {
                    todayPlanCard(schedule)
                } else {
                    emptyPlanCard
                }

                homeStatusRail
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 112)
        }
        .homeScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showWorkout) {
            if let workoutSessionID {
                ActiveWorkoutView(sessionID: workoutSessionID)
            }
        }
        .sheet(isPresented: $showBodyCheckIn) {
            NavigationStack {
                DailyBodyCheckInEditor(checkIn: todayBodyCheckIn)
            }
            .preferredColorScheme(.dark)
            .tint(AppTheme.accent)
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

    private var todayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(Date.now, format: .dateTime.day())
                .font(.system(size: 46, weight: .black, design: .rounded))
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(AppTheme.posterWarmWhite)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppTheme.accent)
                .frame(width: 3, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now, format: .dateTime.month(.wide))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(AppTheme.posterWarmWhite)

                Text(Date.now, format: .dateTime.weekday(.wide))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Text("X—FIT")
                .font(.caption2.weight(.black).monospaced())
                .tracking(1.8)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Date.now, format: .dateTime.year().month().day().weekday(.wide)))
        .accessibilityIdentifier("首页日期")
    }

    private var homeStatusRail: some View {
        VStack(spacing: 0) {
            bodyCheckInCard

            if let latestCompletedSession {
                Rectangle()
                    .fill(AppTheme.line)
                    .frame(height: 1)
                    .padding(.leading, 56)

                latestWorkoutRow(latestCompletedSession)
            }
        }
        .floatingGlassSurface(cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("首页状态轨道")
    }

    private var bodyCheckInCard: some View {
        Button { showBodyCheckIn = true } label: {
            HStack(spacing: 12) {
                if let checkIn = todayBodyCheckIn {
                    Text(ConditionScorePresentation.emoji(for: checkIn.conditionScore))
                        .font(.title3)
                        .frame(width: 32)

                    Text(bodyCheckInSummary(checkIn))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Image(systemName: "figure.mind.and.body")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 32)

                    Text("今天感觉怎么样")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(todayBodyCheckIn == nil ? "记录今日体感" : "修改今日体感")
    }

    private func bodyCheckInSummary(_ checkIn: DailyBodyCheckIn) -> String {
        let regionCount = Set(checkIn.bodyMarkers.map(\.regionID)).count
        let status = ConditionScorePresentation.shortTitle(for: checkIn.conditionScore)
        if regionCount > 0 {
            return "\(status) · \(regionCount) 处不适"
        }
        return status
    }

    private func resumeCard(_ session: WorkoutSession) -> some View {
        let snapshots = sessionExercises.filter { $0.sessionID == session.id }
        let logs = setLogs.filter { $0.sessionID == session.id && !$0.isWarmup }
        let completedSets = logs.filter(\.isCompleted).count
        let identity = WorkoutPosterIdentity(
            name: session.templateName,
            muscleGroups: snapshots.map(\.muscleGroup)
        )

        return workoutPoster(
            identity: identity,
            eyebrow: "正在训练",
            title: session.templateName,
            metadata: "\(snapshots.count) 个动作 · \(completedSets)/\(logs.count) 组"
        ) {
            Text("LIVE")
                .font(.caption2.weight(.black).monospaced())
                .tracking(1.2)
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.accent, in: Capsule())
        } action: {
            Button {
                openSession(session.id)
            } label: {
                posterActionLabel("继续训练", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("继续记录训练")
        }
    }

    private func todayPlanCard(_ schedule: ScheduledWorkout) -> some View {
        let items = items(for: schedule)
        let completedSession = completedSession(for: schedule)
        let isCompleted = schedule.status == .completed
        let identity = WorkoutPosterIdentity(
            name: schedule.templateName,
            muscleGroups: items.compactMap { item in
                exercises.first(where: { $0.id == item.exerciseID })?.muscleGroup
            }
        )

        return workoutPoster(
            identity: identity,
            eyebrow: isCompleted ? "今天已完成" : nil,
            title: schedule.templateName,
            metadata: "\(items.count) 个动作",
            accessoryAlignment: .title
        ) {
            if isCompleted, let completedSession {
                NavigationLink(destination: HistoricalWorkoutEditView(sessionID: completedSession.id)) {
                    posterAccessoryIcon("pencil")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改今日记录")
                .accessibilityIdentifier("修改今日记录")
            } else if !isCompleted {
                NavigationLink(destination: DailyWorkoutBuilderView(
                    initialDate: schedule.plannedDate,
                    initialScheduleID: schedule.id
                )) {
                    posterAccessoryIcon("list.bullet")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("调整今日计划")
                .accessibilityIdentifier("修改今日计划")
            }
        } action: {
            if isCompleted, let completedSession {
                NavigationLink(destination: WorkoutDetailView(sessionID: completedSession.id)) {
                    posterActionLabel("查看训练记录", systemImage: "arrow.up.right")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("查看今日训练记录")
            } else if !isCompleted {
                Button {
                    start(schedule)
                } label: {
                    posterActionLabel("开始训练", systemImage: "arrow.right")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("开始记录训练")
            }
        }
    }

    private var emptyPlanCard: some View {
        workoutPoster(
            identity: WorkoutPosterIdentity(name: "自由训练"),
            eyebrow: nil,
            title: "安排一场训练",
            metadata: "从今天的状态开始"
        ) {
            Image(systemName: "plus")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.posterWarmWhite)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.28), in: Circle())
        } action: {
            NavigationLink(destination: DailyWorkoutBuilderView(initialDate: .now)) {
                posterActionLabel("制定今日计划", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("编排今日训练")
        }
    }

    private func workoutPoster<Accessory: View, Action: View>(
        identity: WorkoutPosterIdentity,
        eyebrow: String?,
        title: String,
        metadata: String,
        accessoryAlignment: WorkoutPosterAccessoryAlignment = .top,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder action: () -> Action
    ) -> some View {
        let accessoryContent = accessory()

        return VStack(spacing: 0) {
            ZStack {
                WorkoutPosterArtwork(identity: identity)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        if let eyebrow {
                            Text(eyebrow)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.posterWarmWhite.opacity(0.68))
                        }

                        Spacer(minLength: 12)
                        if accessoryAlignment == .top {
                            accessoryContent
                        }
                    }
                    .frame(minHeight: 44, alignment: .top)

                    Spacer(minLength: 34)

                    HStack(alignment: .center, spacing: 12) {
                        Text(title)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .tracking(-1.1)
                            .foregroundStyle(AppTheme.posterWarmWhite)
                            .lineLimit(2)
                            .minimumScaleFactor(0.68)
                            .layoutPriority(1)
                            .accessibilityAddTraits(.isHeader)

                        if accessoryAlignment == .title {
                            Spacer(minLength: 8)
                            accessoryContent
                        }
                    }

                    Text(metadata)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .tracking(0.35)
                        .foregroundStyle(AppTheme.posterWarmWhite.opacity(0.58))
                        .padding(.top, 12)
                }
                .padding(24)
            }
            .frame(minHeight: 246)

            action()
                .frame(minHeight: 64)
                .background(AppTheme.accent)
        }
        .background(AppTheme.posterBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.76), radius: 38, y: 26)
        .shadow(color: AppTheme.accent.opacity(0.085), radius: 48, y: 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("今日训练海报")
    }

    private func posterActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.headline.weight(.black))
                .foregroundStyle(.black)

            Spacer(minLength: 12)

            Image(systemName: systemImage)
                .font(.subheadline.weight(.black))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(.black, in: Circle())
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 64)
        .contentShape(Rectangle())
    }

    private func posterAccessoryIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.bold())
            .foregroundStyle(AppTheme.posterWarmWhite)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var quickRecordActions: some View {
        HStack(spacing: 10) {
            NavigationLink(destination: HistoricalWorkoutEntryView()) {
                quickActionLabel("补录", detail: "加入记录", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("补录训练入口")

            NavigationLink(destination: HistoryView()) {
                quickActionLabel("历史", detail: "查看编辑", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("训练历史入口")

            NavigationLink(destination: ScheduleView()) {
                quickActionLabel("日程", detail: "调整计划", systemImage: "calendar")
            }
            .accessibilityIdentifier("训练日程入口")
        }
        .buttonStyle(.plain)
    }

    private var recentVolumeCard: some View {
        let points = recentVolumePoints
        let ceiling = max(points.map(\.volume).max() ?? 0, 1)
        let chartCeiling = ceiling <= Double.greatestFiniteMagnitude / 1.28
            ? ceiling * 1.28
            : Double.greatestFiniteMagnitude

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近训练容量")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("日期与实际完成容量 · kg")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                NavigationLink("全部记录", destination: HistoryView())
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }

            if points.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("完成或补录训练后，这里会显示最近训练日的容量变化。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    NavigationLink("补录一场训练", destination: HistoricalWorkoutEntryView())
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                latestVolumeSummary(points)

                Chart(points) { point in
                    AreaMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("训练容量", point.volume)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.26), AppTheme.accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("训练容量", point.volume)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("训练容量", point.volume)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .symbolSize(48)
                    .annotation(position: .top, spacing: 5) {
                        Text(formattedCompactVolume(point.volume))
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(
                        "\(point.date.formatted(.dateTime.month().day()))，训练容量 \(formattedVolume(point.volume))，\(point.completedSets) 个工作组"
                    )
                    .accessibilityIdentifier("最近容量点-\(point.date.compactDayMonthLabel)")
                }
                .chartXAxis {
                    AxisMarks(values: points.map(\.date)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month(.defaultDigits).day())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        AxisTick().foregroundStyle(.clear)
                        AxisGridLine().foregroundStyle(.clear)
                    }
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...chartCeiling)
                .chartPlotStyle { plot in
                    plot.background(Color.clear)
                }
                .frame(height: 150)
                .accessibilityLabel("最近训练容量图")
                .accessibilityValue(
                    points.map {
                        "\($0.date.compactDayMonthLabel): \(formattedVolume($0.volume))"
                    }
                    .joined(separator: "; ")
                )
                .accessibilityIdentifier("最近训练容量图")

                Text("每个点代表当天已完成的非热身工作组；完整周/月分析保留在“进度”。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .cardSurface()
    }

    private func latestVolumeSummary(_ points: [TrainingVolumeTrendPoint]) -> some View {
        let latest = points[points.count - 1]

        return HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(latest.date, format: .dateTime.month().day().weekday(.short))
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
                Text(formattedVolume(latest.volume))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }

            Spacer()

            if points.count > 1 {
                let previous = points[points.count - 2]
                Text(volumeChangeText(current: latest.volume, previous: previous.volume))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(volumeChangeColor(current: latest.volume, previous: previous.volume))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        volumeChangeColor(current: latest.volume, previous: previous.volume).opacity(0.12),
                        in: Capsule()
                    )
            } else {
                Text("已建立首个基线")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func planMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.line).frame(width: 1, height: 28)
        }
    }

    private func quickActionLabel(_ title: String, detail: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.headline.bold())
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(AppTheme.line, lineWidth: 1))
    }

    private func formattedVolume(_ volume: Double) -> String {
        guard volume.isFinite, volume > 0 else { return "0 kg" }
        if volume >= 1_000_000_000 {
            return volume.formatted(
                .number.notation(.scientific).precision(.fractionLength(1))
            ) + " kg"
        }
        if volume >= 10_000 {
            return String(format: "%.1f 万 kg", volume / 10_000)
        }
        return "\(Int(volume).formatted()) kg"
    }

    private func formattedCompactVolume(_ volume: Double) -> String {
        guard volume.isFinite, volume > 0 else { return "0" }
        if volume >= 1_000_000_000 {
            return volume.formatted(
                .number.notation(.scientific).precision(.fractionLength(1))
            )
        }
        if volume >= 10_000 {
            return String(format: "%.1f万", volume / 10_000)
        }
        if volume >= 1_000 {
            return String(format: "%.1fk", volume / 1_000)
        }
        return "\(Int(volume))"
    }

    private func volumeChangeText(current: Double, previous: Double) -> String {
        guard previous > 0 else { return "新基线" }
        let change = (current - previous) / previous * 100
        guard change.isFinite,
              change >= Double(Int.min),
              change <= Double(Int.max) else {
            return "较上次变化超出范围"
        }
        let rounded = Int(change.rounded())
        let sign = rounded > 0 ? "+" : ""
        return "较上次 \(sign)\(rounded)%"
    }

    private func volumeChangeColor(current: Double, previous: Double) -> Color {
        guard previous > 0 else { return AppTheme.secondaryText }
        if current > previous { return AppTheme.accent }
        if current < previous { return AppTheme.orange }
        return AppTheme.secondaryText
    }

    private func latestWorkoutRow(_ session: WorkoutSession) -> some View {
        NavigationLink(destination: WorkoutDetailView(sessionID: session.id)) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("最近一次训练")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(session.templateName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(session.completedAt ?? session.startedAt, format: .dateTime.month().day())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("最近一次训练入口")
    }

    private func completedSession(for schedule: ScheduledWorkout) -> WorkoutSession? {
        sessions.first {
            $0.scheduledWorkoutID == schedule.id && $0.status == .completed
        }
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

private enum WorkoutPosterAccessoryAlignment {
    case top
    case title
}

private struct WorkoutPosterIdentity {
    let heroKind: WorkoutHeroKind

    init(name: String, muscleGroups: [String] = []) {
        heroKind = WorkoutHeroKind.resolve(workoutName: name, muscleGroups: muscleGroups)
    }
}

private struct WorkoutPosterArtwork: View {
    let identity: WorkoutPosterIdentity

    var body: some View {
        ZStack {
            HeroWorkoutImage(kind: identity.heroKind)
                .saturation(0.78)
                .contrast(1.08)

            Color.black.opacity(0.16)

            LinearGradient(
                colors: [.black.opacity(0.88), .black.opacity(0.48), .black.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.76)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum ConditionScorePresentation {
    static func emoji(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "😵"
        case 2: return "😣"
        case 3: return "😐"
        case 4: return "🙂"
        default: return "💪"
        }
    }

    static func title(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "状态很差，建议休息或明显降量"
        case 2: return "状态偏差，训练时注意反馈"
        case 3: return "状态一般，按实际感觉调整"
        case 4: return "状态不错，可以正常训练"
        default: return "状态很好，准备充分"
        }
    }

    static func shortTitle(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "状态很差"
        case 2: return "状态偏差"
        case 3: return "状态一般"
        case 4: return "状态不错"
        default: return "状态很好"
        }
    }
}

private struct DailyBodyCheckInEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let checkIn: DailyBodyCheckIn?

    @State private var score: Int
    @State private var notes: String
    @State private var selectedKind: BodyMarkerKind = .area
    @State private var markers: [BodyMapMarker]
    @State private var errorMessage: String?
    @State private var inferenceMessage: String?

    init(checkIn: DailyBodyCheckIn?) {
        self.checkIn = checkIn
        _score = State(initialValue: checkIn?.conditionScore ?? 3)
        _notes = State(initialValue: checkIn?.discomfortNotes ?? "")
        _markers = State(initialValue: checkIn?.bodyMarkers ?? [])
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                scoreCard
                notesCard
                anatomyCard
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("今日体感")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .accessibilityIdentifier("取消今日体感")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("保存今日体感")
            }
        }
        .alert("保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("训练前整体状态（1 差 → 5 好）")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        score = value
                    } label: {
                        VStack(spacing: 5) {
                            Text(ConditionScorePresentation.emoji(for: value))
                                .font(.title2)
                            Text("\(value)")
                                .font(.caption2.bold().monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            score == value ? AppTheme.accent.opacity(0.18) : AppTheme.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(score == value ? AppTheme.accent : AppTheme.line, lineWidth: score == value ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("体感 \(value) 分，\(ConditionScorePresentation.title(for: value))")
                    .accessibilityIdentifier("body-score-\(value)")
                    .accessibilityAddTraits(score == value ? .isSelected : [])
                }
            }

            Text(ConditionScorePresentation.title(for: score))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("不适备注")
                .font(.headline)
            TextField("例如：右肩前侧抬手疼，左膝下蹲发紧", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("body-discomfort-notes")

            Button {
                let result = BodyRegionCatalog.inferMarkers(in: notes, kind: selectedKind)
                merge(result.markers)
                if result.requiresConfirmation {
                    inferenceMessage = "无法确定\(result.unresolvedTerms.joined(separator: "、"))的前后或左右位置，请在人体图上确认。"
                } else if result.markers.isEmpty, !result.ignoredNegatedTerms.isEmpty {
                    inferenceMessage = "已忽略否定描述，没有自动添加标记。"
                } else if result.markers.isEmpty {
                    inferenceMessage = "没有识别到明确部位，请在人体图上手动点选。"
                } else if !result.ignoredNegatedTerms.isEmpty {
                    inferenceMessage = "已标记明确不适，并忽略了否定描述。"
                } else {
                    inferenceMessage = "已标记 \(result.markers.count) 个明确部位，请确认后保存。"
                }
            } label: {
                Label("按备注识别并标记部位", systemImage: "sparkles")
                    .font(.caption.bold())
            }
            .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("按备注标记部位")

            if let inferenceMessage {
                Text(inferenceMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("body-inference-result")
            }
        }
        .cardSurface()
    }

    private var anatomyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("不适部位")
                    .font(.headline)
                Text("先选标记类型，再点正面或背面的部位。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("标记类型", selection: $selectedKind) {
                ForEach(BodyMarkerKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("body-marker-kind")

            BodyMapDiagram(
                markers: markers,
                selectedKind: selectedKind,
                isInteractive: true,
                onTap: toggle
            )
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Label("红色区域：肌肉 / 部位", systemImage: "rectangle.inset.filled")
                Label("红点：关节 / 筋膜", systemImage: "circle.fill")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if markers.isEmpty {
                Text("还没有标记。没有不适时可以只保存体感分数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已标注")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(sortedMarkers) { marker in
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: marker.kind == .jointFascia ? 8 : 13, height: 8)
                            Text("\(BodyRegionCatalog.definition(for: marker.regionID)?.name ?? marker.regionID) · \(marker.kind.title)")
                                .font(.caption)
                            Spacer()
                            Button {
                                markers.removeAll { $0.id == marker.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除\(BodyRegionCatalog.definition(for: marker.regionID)?.name ?? marker.regionID)的\(marker.kind.title)标注")
                            .accessibilityIdentifier("remove-body-marker-\(marker.id)")
                        }
                    }
                }
            }
        }
        .cardSurface()
    }

    private var sortedMarkers: [BodyMapMarker] {
        markers.sorted {
            (BodyRegionCatalog.definition(for: $0.regionID)?.name ?? $0.regionID)
                < (BodyRegionCatalog.definition(for: $1.regionID)?.name ?? $1.regionID)
        }
    }

    private func merge(_ incoming: [BodyMapMarker]) {
        guard !incoming.isEmpty else { return }
        for marker in incoming {
            markers.removeAll { $0.id == marker.id }
            markers.append(marker)
        }
    }

    private func toggle(_ regionID: String) {
        if markers.contains(where: { $0.regionID == regionID && $0.kind == selectedKind }) {
            markers.removeAll { $0.regionID == regionID && $0.kind == selectedKind }
        } else {
            markers.append(BodyMapMarker(regionID: regionID, kind: selectedKind))
        }
    }

    private func save() {
        do {
            try DailyBodyCheckInService.save(
                existing: checkIn,
                date: .now,
                conditionScore: score,
                discomfortNotes: notes,
                bodyMarkers: markers,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BodyMapDiagram: View {
    let markers: [BodyMapMarker]
    let selectedKind: BodyMarkerKind
    let isInteractive: Bool
    let onTap: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("MuscleMapBase")
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("正面和背面肌肉图")
                    .accessibilityIdentifier("body-muscle-map")

                ForEach(BodyRegionCatalog.all) { region in
                    let placement = BodyRegionImageLayout.placement(for: region)
                    regionControl(region, placement: placement, in: proxy.size)
                        .position(
                            x: proxy.size.width * placement.x,
                            y: proxy.size.height * placement.y
                        )
                }

                viewSideLabel("正面", x: 0.28, in: proxy.size)
                viewSideLabel("背面", x: 0.735, in: proxy.size)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正面和背面肌肉不适标注图")
        .accessibilityIdentifier("body-muscle-map-container")
    }

    @ViewBuilder
    private func regionControl(
        _ region: BodyRegionDefinition,
        placement: BodyRegionImagePlacement,
        in size: CGSize
    ) -> some View {
        let hasAreaMarker = markers.contains { $0.regionID == region.id && $0.kind == .area }
        let hasJointMarker = markers.contains { $0.regionID == region.id && $0.kind == .jointFascia }
        let isSelectedForCurrentKind = markers.contains {
            $0.regionID == region.id && $0.kind == selectedKind
        }
        let markerDescription: String = {
            switch (hasAreaMarker, hasJointMarker) {
            case (true, true): return "肌肉 / 区域和关节 / 筋膜"
            case (true, false): return BodyMarkerKind.area.title
            case (false, true): return BodyMarkerKind.jointFascia.title
            case (false, false): return "未标记"
            }
        }()
        let control = ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    hasAreaMarker
                        ? Color.red.opacity(0.46)
                        : Color.white.opacity(isInteractive ? 0.018 : 0)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            hasAreaMarker
                                ? Color.red
                                : Color.white.opacity(isInteractive ? 0.10 : 0),
                            lineWidth: hasAreaMarker ? 1.5 : 0.7
                        )
                }
                .shadow(color: hasAreaMarker ? Color.red.opacity(0.65) : .clear, radius: 7)

            if hasJointMarker {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                    .shadow(color: Color.red.opacity(0.9), radius: 5)
            }
        }
        .frame(
            width: max(20, size.width * placement.width),
            height: max(16, size.height * placement.height)
        )

        if isInteractive {
            Button { onTap(region.id) } label: {
                control
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(region.name)，\(markerDescription)")
            .accessibilityHint("点按切换为\(selectedKind.title)标记")
            .accessibilityIdentifier("body-region-\(region.id)")
            .accessibilityAddTraits(isSelectedForCurrentKind ? .isSelected : [])
        } else {
            control
                .accessibilityHidden(true)
        }
    }

    private func viewSideLabel(_ title: String, x: CGFloat, in size: CGSize) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .position(x: size.width * x, y: 18)
            .accessibilityHidden(true)
    }
}
