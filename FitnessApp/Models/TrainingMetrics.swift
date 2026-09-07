import Foundation

enum TrainingProgressPeriod: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "本周"
        case .month: return "本月"
        }
    }

    var previousTitle: String {
        switch self {
        case .week: return "上周"
        case .month: return "上月"
        }
    }

    var bucketSubtitle: String {
        switch self {
        case .week: return "每日训练容量 · kg"
        case .month: return "每周训练容量 · kg"
        }
    }
}

struct TrainingProgressBucket: Identifiable, Equatable {
    let startDate: Date
    let label: String
    let completedSessions: Int
    let workingSets: Int
    let volume: Double
    let activeMinutes: Int

    var id: Date { startDate }
}

struct TrainingProgressSummary: Equatable {
    let period: TrainingProgressPeriod
    let interval: DateInterval
    let completedSessions: Int
    let plannedWorkouts: Int
    let targetWorkouts: Int
    let workingSets: Int
    let volume: Double
    let activeMinutes: Int
    let previousVolume: Double
    let volumeChangePercent: Double?
    let buckets: [TrainingProgressBucket]

    var completionProgress: Double {
        guard targetWorkouts > 0 else { return 0 }
        return min(Double(completedSessions) / Double(targetWorkouts), 1)
    }
}

enum TrainingGoalMode: String, CaseIterable, Identifiable {
    case cuttingVolume
    case balancedProgression

    static let storageKey = "training.goal.mode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cuttingVolume:
            return "减脂 · 容量优先"
        case .balancedProgression:
            return "均衡 · 渐进超负荷"
        }
    }

    var detail: String {
        switch self {
        case .cuttingVolume:
            return "优先保留有效组数和训练容量；恢复与 RIR 允许时才微加重。"
        case .balancedProgression:
            return "达到次数上限且余力充足时，逐步增加重量。"
        }
    }
}

enum ProgressionRecommendation: Equatable {
    case increase(percent: Double)
    case maintain
    case reduce

    func title(for goalMode: TrainingGoalMode) -> String {
        switch (goalMode, self) {
        case (.cuttingVolume, .increase):
            return "可选微加重 · 组数不减"
        case (.cuttingVolume, .maintain):
            return "维持重量与组数"
        case (.cuttingVolume, .reduce):
            return "减重保组数"
        case (.balancedProgression, .increase):
            return "建议小幅加重"
        case (.balancedProgression, .maintain):
            return "建议保持重量"
        case (.balancedProgression, .reduce):
            return "建议降低重量"
        }
    }
}

struct ProgressionAssessment: Equatable {
    let recommendation: ProgressionRecommendation
    let title: String
    let detail: String
    let currentVolume: Double
    let previousVolume: Double?
    let hasCompleteRIR: Bool
}

struct TrainingVolumeTrendPoint: Identifiable, Equatable {
    let date: Date
    let volume: Double
    let completedSets: Int
    let sessionCount: Int

    var id: Date { date }
}

struct ExerciseVolumeTrend: Identifiable, Equatable {
    let key: String
    let name: String
    let unit: ExerciseVolumeUnit
    let points: [TrainingVolumeTrendPoint]
    let totalVolume: Double
    let completedSets: Int
    let sessionCount: Int

    var id: String { key }
}

struct TrainingVolumeTrends: Equatable {
    let overall: [TrainingVolumeTrendPoint]
    let exercises: [ExerciseVolumeTrend]
}

private struct TrainingVolumeAccumulator {
    var volume = 0.0
    var completedSets = 0
    var sessionIDs: Set<UUID> = []

    mutating func add(_ log: SetLog, unit: ExerciseVolumeUnit, sessionID: UUID) {
        let nextVolume = volume + unit.volume(weight: log.actualWeight, reps: log.actualReps)
        if nextVolume.isFinite {
            volume = nextVolume
        }
        completedSets += 1
        sessionIDs.insert(sessionID)
    }
}

enum TrainingMetrics {
    static func volumeSummary(
        sessionExercises: [SessionExercise],
        setLogs: [SetLog]
    ) -> [ExerciseVolumeUnit: Double] {
        let snapshotsByID = Dictionary(uniqueKeysWithValues: sessionExercises.map { ($0.id, $0) })
        return setLogs
            .filter { $0.isCompleted && !$0.isWarmup }
            .reduce(into: [:]) { result, log in
                guard let snapshot = snapshotsByID[log.sessionExerciseID] else { return }
                let weight = snapshot.volumeUnit == .bodyweight
                    ? snapshot.bodyWeightKgSnapshot
                    : log.actualWeight
                guard let volume = snapshot.volumeUnit.volume(weight: weight, reps: log.actualReps) else { return }
                result[snapshot.volumeUnit, default: 0] += volume
            }
    }

    static func volume(
        for logs: [SetLog],
        unit: ExerciseVolumeUnit = .kilogram
    ) -> Double {
        logs
            .filter { $0.isCompleted && !$0.isWarmup }
            .reduce(0) { total, log in
                let nextTotal = total + unit.volume(
                    weight: log.actualWeight,
                    reps: log.actualReps
                )
                return nextTotal.isFinite ? nextTotal : total
            }
    }

    static func volume(
        for logs: [SetLog],
        sessionExercises: [SessionExercise],
        unit: ExerciseVolumeUnit = .kilogram
    ) -> Double {
        let matchingSnapshotIDs = Set(
            sessionExercises
                .filter { $0.volumeUnit == unit }
                .map(\.id)
        )
        return volume(
            for: logs.filter { matchingSnapshotIDs.contains($0.sessionExerciseID) },
            unit: unit
        )
    }

    static func volumeTotals(
        for logs: [SetLog],
        sessionExercises: [SessionExercise]
    ) -> [ExerciseVolumeUnit: Double] {
        Dictionary(uniqueKeysWithValues: ExerciseVolumeUnit.allCases.map { unit in
            (
                unit,
                volume(for: logs, sessionExercises: sessionExercises, unit: unit)
            )
        })
    }

    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return weight * (1 + Double(reps) / 30)
    }

    static func volumeTrends(
        calendar: Calendar = .current,
        sessions: [WorkoutSession],
        sessionExercises: [SessionExercise],
        exercises: [Exercise],
        setLogs: [SetLog]
    ) -> TrainingVolumeTrends {
        let completedSessions = sessions.filter { $0.status == .completed }
        var sessionByID: [UUID: WorkoutSession] = [:]
        for session in completedSessions where sessionByID[session.id] == nil {
            sessionByID[session.id] = session
        }

        var snapshotNameByID: [UUID: String] = [:]
        var snapshotUnitByID: [UUID: ExerciseVolumeUnit] = [:]
        for snapshot in sessionExercises where snapshotNameByID[snapshot.id] == nil {
            let name = snapshot.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                snapshotNameByID[snapshot.id] = name
            }
            snapshotUnitByID[snapshot.id] = snapshot.volumeUnit
        }

        var exerciseNameByID: [UUID: String] = [:]
        var exerciseUnitByID: [UUID: ExerciseVolumeUnit] = [:]
        var approvedCanonicalByExerciseID: [UUID: String] = [:]
        var approvedDisplayNameByExerciseID: [UUID: String] = [:]
        for exercise in exercises where exerciseNameByID[exercise.id] == nil {
            let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                exerciseNameByID[exercise.id] = name
            }
            exerciseUnitByID[exercise.id] = exercise.volumeUnit
            if let canonicalID = exercise.approvedCanonicalID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !canonicalID.isEmpty {
                approvedCanonicalByExerciseID[exercise.id] = canonicalID
                approvedDisplayNameByExerciseID[exercise.id] = exercise.approvedStandardNameZH
                    ?? exercise.name
            }
        }

        var overallByDay: [Date: TrainingVolumeAccumulator] = [:]
        var exerciseByDay: [String: [Date: TrainingVolumeAccumulator]] = [:]
        var displayNameByKey: [String: String] = [:]
        var unitByKey: [String: ExerciseVolumeUnit] = [:]

        for log in setLogs where log.isCompleted && !log.isWarmup {
            guard let session = sessionByID[log.sessionID] else { continue }
            let day = calendar.startOfDay(for: session.startedAt)

            let unit = snapshotUnitByID[log.sessionExerciseID]
                ?? exerciseUnitByID[log.exerciseID]
                ?? .kilogram
            if unit == .kilogram {
                var overall = overallByDay[day] ?? TrainingVolumeAccumulator()
                overall.add(log, unit: unit, sessionID: session.id)
                overallByDay[day] = overall
            }

            guard let exerciseName = snapshotNameByID[log.sessionExerciseID]
                    ?? exerciseNameByID[log.exerciseID] else {
                continue
            }
            let approvedCanonical = approvedCanonicalByExerciseID[log.exerciseID]
            let nameKey = approvedCanonical.map { "canonical:\($0)" }
                ?? exerciseHistoryKey(for: exerciseName)
            guard !nameKey.isEmpty else { continue }
            let key = "\(nameKey)|\(unit.rawValue)"
            let displayName = approvedDisplayNameByExerciseID[log.exerciseID]
                ?? historicalDisplayName(for: exerciseName)
            displayNameByKey[key] = displayNameByKey[key] ?? displayName
            unitByKey[key] = unit

            var dayBuckets = exerciseByDay[key] ?? [:]
            var exerciseAccumulator = dayBuckets[day] ?? TrainingVolumeAccumulator()
            exerciseAccumulator.add(log, unit: unit, sessionID: session.id)
            dayBuckets[day] = exerciseAccumulator
            exerciseByDay[key] = dayBuckets
        }

        let exerciseTrends = exerciseByDay.compactMap { key, buckets -> ExerciseVolumeTrend? in
            guard let name = displayNameByKey[key], let unit = unitByKey[key] else { return nil }
            let points = volumeTrendPoints(from: buckets)
            return ExerciseVolumeTrend(
                key: key,
                name: name,
                unit: unit,
                points: points,
                totalVolume: points.reduce(0) { $0 + $1.volume },
                completedSets: points.reduce(0) { $0 + $1.completedSets },
                sessionCount: points.reduce(0) { $0 + $1.sessionCount }
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return TrainingVolumeTrends(
            overall: volumeTrendPoints(from: overallByDay),
            exercises: exerciseTrends
        )
    }

    static func recentOverallVolumePoints(
        through date: Date = .now,
        limit: Int = 6,
        calendar: Calendar = .current,
        sessions: [WorkoutSession],
        sessionExercises: [SessionExercise],
        exercises: [Exercise],
        setLogs: [SetLog]
    ) -> [TrainingVolumeTrendPoint] {
        guard limit > 0,
              let endOfDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: date)
              ) else {
            return []
        }
        let points = volumeTrends(
            calendar: calendar,
            sessions: sessions,
            sessionExercises: sessionExercises,
            exercises: exercises,
            setLogs: setLogs
        ).overall.filter { $0.date < endOfDay }
        return Array(points.suffix(limit))
    }

    static func exerciseHistoryKey(for name: String) -> String {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "zh_Hans_CN")
            )
            .lowercased()
        return normalized == "严格深蹲" ? "深蹲" : normalized
    }

    private static func historicalDisplayName(for name: String) -> String {
        exerciseHistoryKey(for: name) == exerciseHistoryKey(for: "深蹲") ? "深蹲" : name
    }

    static func progression(
        completedReps: [Int],
        minimumReps: Int,
        maximumReps: Int,
        rirValues: [Int]
    ) -> ProgressionRecommendation {
        guard !completedReps.isEmpty else { return .maintain }

        if completedReps.contains(where: { $0 < minimumReps }) || rirValues.contains(0) {
            return .reduce
        }

        let allAtTop = completedReps.allSatisfy { $0 >= maximumReps }
        let effortControlled = rirValues.count == completedReps.count
            && rirValues.allSatisfy { $0 >= 2 }
        return allAtTop && effortControlled ? .increase(percent: 0.025) : .maintain
    }

    static func progressionAssessment(
        weights: [Double],
        completedReps: [Int],
        minimumReps: Int,
        maximumReps: Int,
        rirValues: [Int?],
        previousVolume: Double? = nil,
        goalMode: TrainingGoalMode
    ) -> ProgressionAssessment {
        let pairedCount = min(weights.count, completedReps.count)
        let currentVolume = (0..<pairedCount).reduce(0.0) {
            $0 + max(0, weights[$1]) * Double(max(0, completedReps[$1]))
        }
        let hasCompleteRIR = !completedReps.isEmpty
            && rirValues.count == completedReps.count
            && rirValues.allSatisfy { $0 != nil }
        let knownRIR = rirValues.compactMap { $0 }
        let missedMinimum = completedReps.contains { $0 < minimumReps }
        let reachedFailure = knownRIR.contains(0)

        let recommendation: ProgressionRecommendation
        if missedMinimum || reachedFailure {
            recommendation = .reduce
        } else if goalMode == .cuttingVolume {
            let meaningfulVolumeDrop = previousVolume.map {
                $0 > 0 && currentVolume < $0 * 0.9
            } ?? false
            let allAtTop = !completedReps.isEmpty
                && completedReps.allSatisfy { $0 >= maximumReps }
            let ampleReserve = hasCompleteRIR
                && knownRIR.allSatisfy { $0 >= 3 }
            let volumeMaintained = previousVolume.map {
                $0 <= 0 || currentVolume >= $0 * 0.98
            } ?? false

            if meaningfulVolumeDrop {
                recommendation = .reduce
            } else if allAtTop && ampleReserve && volumeMaintained {
                recommendation = .increase(percent: 0.025)
            } else {
                recommendation = .maintain
            }
        } else {
            recommendation = progression(
                completedReps: completedReps,
                minimumReps: minimumReps,
                maximumReps: maximumReps,
                rirValues: knownRIR
            )
        }

        let title: String
        let detail: String
        if completedReps.isEmpty {
            title = "建立训练量基线"
            detail = goalMode == .cuttingVolume
                ? "从 4 个工作组和适中重量开始，记录每组 RIR 后再调整重量。"
                : "先完成一次真实训练，再根据次数和 RIR 生成进阶建议。"
        } else if case .reduce = recommendation {
            title = recommendation.title(for: goalMode)
            detail = goalMode == .cuttingVolume
                ? "次数低于目标、出现 0 RIR，或容量明显下降；建议减轻约 5–10%，优先完成原定组数。"
                : "有组未达到最低次数或已经力竭，建议降低重量并恢复动作质量。"
        } else if !hasCompleteRIR {
            title = recommendation.title(for: goalMode)
            detail = "RIR 没有完整记录，本次不据此加重；下次先保持组数与工作重量并补记 RIR。"
        } else {
            title = recommendation.title(for: goalMode)
            switch (goalMode, recommendation) {
            case (.cuttingVolume, .increase(let percent)):
                detail = "训练容量没有下降且每组至少保留 3 RIR；可微加重 \(Int(percent * 1000) / 10)%，但不要减少组数。"
            case (.cuttingVolume, .maintain):
                if let previousVolume, previousVolume > 0 {
                    let ratio = Int((currentVolume / previousVolume * 100).rounded())
                    detail = "本次容量约为上次的 \(ratio)%；继续保留组数和适中重量，以稳定输出为先。"
                } else {
                    detail = "先以本次组数和容量建立基线；减脂期不因单次完成次数达标就自动加重。"
                }
            case (.cuttingVolume, .reduce):
                detail = "建议减重并保留原定组数。"
            case (.balancedProgression, .increase(let percent)):
                detail = "所有完成组达到次数上限且至少保留 2 RIR，可尝试增加约 \(Int(percent * 1000) / 10)% 重量。"
            case (.balancedProgression, .maintain):
                detail = "当前表现适合维持重量，先让各组稳定达到次数上限。"
            case (.balancedProgression, .reduce):
                detail = "建议降低重量并恢复动作质量。"
            }
        }

        return ProgressionAssessment(
            recommendation: recommendation,
            title: title,
            detail: detail,
            currentVolume: currentVolume,
            previousVolume: previousVolume,
            hasCompleteRIR: hasCompleteRIR
        )
    }

    static func workingWeight(weights: [Double], reps: [Int]) -> Double {
        let pairedCount = min(weights.count, reps.count)
        let totalReps = (0..<pairedCount).reduce(0) { $0 + max(0, reps[$1]) }
        guard totalReps > 0 else { return weights.last ?? 0 }
        let volume = (0..<pairedCount).reduce(0.0) {
            $0 + max(0, weights[$1]) * Double(max(0, reps[$1]))
        }
        return (volume / Double(totalReps) * 2).rounded() / 2
    }

    static func progressSummary(
        period: TrainingProgressPeriod,
        now: Date = .now,
        calendar sourceCalendar: Calendar = .current,
        schedules: [ScheduledWorkout],
        sessions: [WorkoutSession],
        sessionExercises: [SessionExercise] = [],
        setLogs: [SetLog]
    ) -> TrainingProgressSummary {
        var calendar = sourceCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        let interval = progressInterval(for: period, containing: now, calendar: calendar)
        let previousInterval = previousProgressInterval(
            for: period,
            currentInterval: interval,
            calendar: calendar
        )
        let elapsed = max(0, min(now, interval.end).timeIntervalSince(interval.start))
        let previousComparisonInterval = DateInterval(
            start: previousInterval.start,
            end: min(previousInterval.end, previousInterval.start.addingTimeInterval(elapsed))
        )
        let completedSessions = sessions.filter {
            $0.status == .completed && interval.contains($0.startedAt)
        }
        let completedSessionIDs = Set(completedSessions.map(\.id))
        let workingLogs = setLogs.filter {
            $0.isCompleted && !$0.isWarmup && completedSessionIDs.contains($0.sessionID)
        }
        let eligibleSchedules = schedules.filter {
            interval.contains($0.plannedDate) && $0.status != .skipped
        }
        let targetWorkouts = eligibleSchedules.count

        let previousSessionIDs = Set(sessions.filter {
            $0.status == .completed && previousComparisonInterval.contains($0.startedAt)
        }.map(\.id))
        let previousLogs = setLogs.filter {
            $0.isCompleted && !$0.isWarmup && previousSessionIDs.contains($0.sessionID)
        }
        let kilogramSnapshotIDs = Set(
            sessionExercises.filter { $0.volumeUnit == .kilogram }.map(\.id)
        )
        let kilogramLogs: ([SetLog]) -> [SetLog] = { logs in
            guard !sessionExercises.isEmpty else { return logs }
            return logs.filter { kilogramSnapshotIDs.contains($0.sessionExerciseID) }
        }
        let previousVolume = volume(for: kilogramLogs(previousLogs))
        let currentVolume = volume(for: kilogramLogs(workingLogs))
        let volumeChangePercent = previousVolume > 0
            ? (currentVolume - previousVolume) / previousVolume * 100
            : nil

        let bucketStarts = progressBucketStarts(
            for: period,
            interval: interval,
            calendar: calendar
        )
        let buckets = bucketStarts.map { bucketStart in
            let bucketInterval = progressBucketInterval(
                startingAt: bucketStart,
                period: period,
                currentInterval: interval,
                calendar: calendar
            )
            let bucketSessions = completedSessions.filter { bucketInterval.contains($0.startedAt) }
            let bucketSessionIDs = Set(bucketSessions.map(\.id))
            let bucketLogs = workingLogs.filter { bucketSessionIDs.contains($0.sessionID) }

            return TrainingProgressBucket(
                startDate: bucketStart,
                label: progressBucketLabel(for: bucketStart, period: period, calendar: calendar),
                completedSessions: bucketSessions.count,
                workingSets: bucketLogs.count,
                volume: volume(for: kilogramLogs(bucketLogs)),
                activeMinutes: activeMinutes(for: bucketSessions)
            )
        }

        return TrainingProgressSummary(
            period: period,
            interval: interval,
            completedSessions: completedSessions.count,
            plannedWorkouts: eligibleSchedules.count,
            targetWorkouts: targetWorkouts,
            workingSets: workingLogs.count,
            volume: currentVolume,
            activeMinutes: activeMinutes(for: completedSessions),
            previousVolume: previousVolume,
            volumeChangePercent: volumeChangePercent,
            buckets: buckets
        )
    }

    private static func progressInterval(
        for period: TrainingProgressPeriod,
        containing date: Date,
        calendar: Calendar
    ) -> DateInterval {
        let component: Calendar.Component = period == .week ? .weekOfYear : .month
        return calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    private static func previousProgressInterval(
        for period: TrainingProgressPeriod,
        currentInterval: DateInterval,
        calendar: Calendar
    ) -> DateInterval {
        let component: Calendar.Component = period == .week ? .weekOfYear : .month
        let previousDate = calendar.date(byAdding: component, value: -1, to: currentInterval.start)
            ?? currentInterval.start.addingTimeInterval(-currentInterval.duration)
        return progressInterval(for: period, containing: previousDate, calendar: calendar)
    }

    private static func progressBucketStarts(
        for period: TrainingProgressPeriod,
        interval: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        switch period {
        case .week:
            return (0..<7).compactMap {
                calendar.date(byAdding: .day, value: $0, to: interval.start)
            }
        case .month:
            let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start
                ?? interval.start
            var starts: [Date] = []
            var cursor = firstWeekStart
            while cursor < interval.end {
                starts.append(cursor)
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor),
                      next > cursor else { break }
                cursor = next
            }
            return starts
        }
    }

    private static func progressBucketInterval(
        startingAt bucketStart: Date,
        period: TrainingProgressPeriod,
        currentInterval: DateInterval,
        calendar: Calendar
    ) -> DateInterval {
        let component: Calendar.Component = period == .week ? .day : .weekOfYear
        let nextStart = calendar.date(byAdding: component, value: 1, to: bucketStart)
            ?? currentInterval.end
        let start = max(bucketStart, currentInterval.start)
        let end = min(nextStart, currentInterval.end)
        return DateInterval(start: start, end: max(start, end))
    }

    private static func progressBucketLabel(
        for date: Date,
        period: TrainingProgressPeriod,
        calendar: Calendar
    ) -> String {
        if period == .month {
            return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
        }

        switch calendar.component(.weekday, from: date) {
        case 1: return "日"
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        default: return "六"
        }
    }

    private static func activeMinutes(for sessions: [WorkoutSession]) -> Int {
        sessions.reduce(0) { total, session in
            guard let completedAt = session.completedAt, completedAt >= session.startedAt else {
                return total
            }
            return total + max(1, Int(completedAt.timeIntervalSince(session.startedAt) / 60))
        }
    }

    private static func volumeTrendPoints(
        from buckets: [Date: TrainingVolumeAccumulator]
    ) -> [TrainingVolumeTrendPoint] {
        buckets.map { date, accumulator in
            TrainingVolumeTrendPoint(
                date: date,
                volume: accumulator.volume,
                completedSets: accumulator.completedSets,
                sessionCount: accumulator.sessionIDs.count
            )
        }
        .sorted { $0.date < $1.date }
    }
}
