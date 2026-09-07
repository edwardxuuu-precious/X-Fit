import Foundation

struct ExerciseSetSnapshot: Identifiable {
    let setNumber: Int
    let weight: Double
    let reps: Int
    let rir: Int?

    var id: Int { setNumber }
}

struct ExerciseLastPerformance {
    let date: Date
    let workoutName: String
    let sets: [ExerciseSetSnapshot]
    let workoutNotes: String
    let performanceNotes: String
    let volumeUnit: ExerciseVolumeUnit
    let bodyWeightKgSnapshot: Double?

    var bestSet: ExerciseSetSnapshot? {
        sets.max {
            if $0.weight == $1.weight {
                return $0.reps < $1.reps
            }
            return $0.weight < $1.weight
        }
    }

    var averageRIR: Double? {
        let values = sets.compactMap(\.rir)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    var volume: Double {
        sets.reduce(0) { total, set in
            let weight = volumeUnit == .bodyweight ? bodyWeightKgSnapshot : set.weight
            return total + (volumeUnit.volume(weight: weight, reps: set.reps) ?? 0)
        }
    }

    var workingWeight: Double {
        TrainingMetrics.workingWeight(
            weights: sets.map(\.weight),
            reps: sets.map(\.reps)
        )
    }
}

struct ExerciseRecommendation: Identifiable {
    let exerciseID: UUID
    let name: String
    let muscleGroup: String
    let equipment: String
    let score: Double
    let reason: String
    let suggestedSets: Int
    let minReps: Int
    let maxReps: Int
    let suggestedWeight: Double
    let restSeconds: Int
    let progressionTitle: String
    let progressionDetail: String
    let suggestedVolume: Double
    let attentionText: String
    let lastPerformance: ExerciseLastPerformance?
    let appearedInLastMenu: Bool

    var id: UUID { exerciseID }
}

struct MuscleGroupAdvice: Identifiable {
    enum Readiness: Equatable {
        case ready
        case moderate
        case recover
        case noHistory
    }

    let muscleGroup: String
    let readiness: Readiness
    let title: String
    let detail: String
    let lastTrainedAt: Date?
    let completedSetsLast7Days: Int
    let lastWorkoutName: String?
    let lastVolumeSummaries: [String]

    var id: String { muscleGroup }
}

@MainActor
enum WorkoutRecommendationService {
    static func recommendations(
        selectedMuscleGroups: Set<String>,
        exercises: [Exercise],
        sessions: [WorkoutSession],
        sessionExercises: [SessionExercise],
        setLogs: [SetLog],
        templateExercises: [TemplateExercise],
        variant: Int = 0,
        goalMode: TrainingGoalMode = .balancedProgression,
        now: Date = .now
    ) -> [ExerciseRecommendation] {
        guard !selectedMuscleGroups.isEmpty else { return [] }

        let eligibleExercises = exercises.filter {
            !$0.isArchived && selectedMuscleGroups.contains($0.muscleGroup)
        }
        let approvedCanonicalByExerciseID = Dictionary(
            uniqueKeysWithValues: exercises.compactMap { exercise in
                exercise.approvedCanonicalID.map { (exercise.id, $0) }
            }
        )
        let exerciseIDsByCanonical = Dictionary(
            grouping: approvedCanonicalByExerciseID,
            by: \.value
        ).mapValues { Set($0.map(\.key)) }
        let confirmedPrimaryNameByCanonical = Dictionary(
            uniqueKeysWithValues: ExerciseCatalogService.confirmedAliasGroups.map {
                ($0.canonicalID, $0.primaryName)
            }
        )
        let activeExercises: [Exercise] = Dictionary(
            grouping: eligibleExercises,
            by: { exercise in
                exercise.approvedCanonicalID.map { "canonical:\($0)" }
                    ?? "exercise:\(exercise.id.uuidString)"
            }
        ).values.compactMap { matches in
            guard let first = matches.first else { return nil }
            guard let canonicalID = first.approvedCanonicalID,
                  let primaryName = confirmedPrimaryNameByCanonical[canonicalID] else {
                return matches.min { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.createdAt < rhs.createdAt
                }
            }
            return matches.first { $0.name == primaryName }
                ?? matches.min { $0.createdAt < $1.createdAt }
        }
        let completedSessions = sessions.filter { $0.status == .completed }
        let sessionByID = Dictionary(uniqueKeysWithValues: completedSessions.map { ($0.id, $0) })
        let currentExerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        let lastMatchingSession = completedSessions
            .sorted { $0.startedAt > $1.startedAt }
            .first { session in
                sessionExercises.contains { snapshot in
                    guard snapshot.sessionID == session.id else { return false }
                    let group = snapshot.muscleGroup.isEmpty
                        ? currentExerciseByID[snapshot.exerciseID]?.muscleGroup ?? ""
                        : snapshot.muscleGroup
                    return selectedMuscleGroups.contains(group)
                }
            }
        let lastMenuExerciseIDs = Set(
            sessionExercises
                .filter { $0.sessionID == lastMatchingSession?.id }
                .map(\.exerciseID)
        )

        return activeExercises.map { exercise in
            let identityExerciseIDs = exercise.approvedCanonicalID
                .flatMap { exerciseIDsByCanonical[$0] }
                ?? [exercise.id]
            let history = sessionExercises
                .filter {
                    identityExerciseIDs.contains($0.exerciseID)
                        && sessionByID[$0.sessionID] != nil
                }
                .compactMap { snapshot -> (WorkoutSession, SessionExercise)? in
                    guard let session = sessionByID[snapshot.sessionID] else { return nil }
                    return (session, snapshot)
                }
                .sorted { $0.0.startedAt > $1.0.startedAt }

            let last = history.first.flatMap { pair in
                lastPerformance(
                    session: pair.0,
                    snapshot: pair.1,
                    setLogs: setLogs
                )
            }
            let previous = history.dropFirst().first.flatMap { pair in
                lastPerformance(
                    session: pair.0,
                    snapshot: pair.1,
                    setLogs: setLogs
                )
            }
            let daysSince = last.map { max(0, Calendar.current.dateComponents([.day], from: $0.date.startOfDay, to: now.startOfDay).day ?? 0) }
            let recentCount = history.filter { $0.0.startedAt >= now.addingDays(-28) }.count
            let appearedInLastMenu = !lastMenuExerciseIDs.isDisjoint(with: identityExerciseIDs)
            let baseline = templateExercises.first { $0.exerciseID == exercise.id }
                ?? templateExercises.first { identityExerciseIDs.contains($0.exerciseID) }
            let target = recommendedTarget(
                exercise: exercise,
                lastHistory: history.first,
                lastPerformance: last,
                previousPerformance: previous,
                baseline: baseline,
                setLogs: setLogs,
                goalMode: goalMode
            )

            var score = 50.0
            if let daysSince {
                switch daysSince {
                case 0...1: score -= 34
                case 2...3: score -= 16
                case 4...7: score += 4
                case 8...14: score += 13
                default: score += 20
                }
            } else {
                score += 28
            }
            score -= Double(min(recentCount, 5) * 4)
            score += appearedInLastMenu ? -28 : 16
            score += stableVariantBias(for: exercise.id, variant: variant)

            let reason: String
            if last == nil {
                reason = "近期没有记录，适合作为本次的新刺激"
            } else if appearedInLastMenu {
                reason = "上次同肌群菜单练过，已降低优先级供你备选"
            } else if let daysSince, daysSince <= 2 {
                reason = "距上次仅 \(daysSince) 天，建议轻量或换动作模式"
            } else if let daysSince {
                reason = "距上次 \(daysSince) 天，适合轮换回来"
            } else {
                reason = "适合加入今天的动作组合"
            }

            let attentionParts = [
                exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                last?.performanceNotes.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                last?.workoutNotes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            ].filter { !$0.isEmpty }

            return ExerciseRecommendation(
                exerciseID: exercise.id,
                name: exercise.name,
                muscleGroup: exercise.muscleGroup,
                equipment: exercise.equipment,
                score: score,
                reason: reason,
                suggestedSets: target.sets,
                minReps: target.minReps,
                maxReps: target.maxReps,
                suggestedWeight: target.weight,
                restSeconds: target.restSeconds,
                progressionTitle: target.assessment.title,
                progressionDetail: target.assessment.detail,
                suggestedVolume: target.weight
                    * Double(target.sets)
                    * Double((target.minReps + target.maxReps) / 2),
                attentionText: attentionParts.isEmpty
                    ? "保持动作控制；出现明显疼痛时停止并调整。"
                    : attentionParts.joined(separator: "；"),
                lastPerformance: last,
                appearedInLastMenu: appearedInLastMenu
            )
        }
        .sorted {
            if $0.score == $1.score {
                return $0.name.localizedCompare($1.name) == .orderedAscending
            }
            return $0.score > $1.score
        }
    }

    static func muscleGroupAdvice(
        selectedMuscleGroups: Set<String>,
        exercises: [Exercise],
        sessions: [WorkoutSession],
        sessionExercises: [SessionExercise],
        setLogs: [SetLog],
        now: Date = .now
    ) -> [MuscleGroupAdvice] {
        let completedSessions = sessions.filter { $0.status == .completed }
        let sessionByID = Dictionary(uniqueKeysWithValues: completedSessions.map { ($0.id, $0) })
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        return selectedMuscleGroups.sorted().map { group in
            let matchingSnapshots = sessionExercises.compactMap { snapshot -> (SessionExercise, WorkoutSession)? in
                guard let session = sessionByID[snapshot.sessionID] else { return nil }
                let snapshotGroup = snapshot.muscleGroup.isEmpty
                    ? exerciseByID[snapshot.exerciseID]?.muscleGroup ?? ""
                    : snapshot.muscleGroup
                guard snapshotGroup == group else { return nil }
                return (snapshot, session)
            }
            let lastDate = matchingSnapshots.map { $0.1.startedAt }.max()
            let recentSnapshotIDs = Set(
                matchingSnapshots
                    .filter { $0.1.startedAt >= now.addingDays(-7) }
                    .map { $0.0.id }
            )
            let recentSets = setLogs.filter {
                $0.isCompleted && recentSnapshotIDs.contains($0.sessionExerciseID)
            }.count

            guard let lastDate else {
                return MuscleGroupAdvice(
                    muscleGroup: group,
                    readiness: .noHistory,
                    title: "没有近期记录",
                    detail: "可以从中等训练量开始，完成后用真实 RIR 调整下一次建议。",
                    lastTrainedAt: nil,
                    completedSetsLast7Days: recentSets,
                    lastWorkoutName: nil,
                    lastVolumeSummaries: []
                )
            }

            let lastSession = matchingSnapshots
                .map(\.1)
                .max { $0.startedAt < $1.startedAt }
            let lastSessionSnapshots = matchingSnapshots
                .filter { $0.1.id == lastSession?.id }
                .map(\.0)
            let volumeByUnit = Dictionary(grouping: lastSessionSnapshots, by: \.volumeUnit)
                .mapValues { snapshots in
                    snapshots.reduce(0.0) { total, snapshot in
                        let snapshotLogs = setLogs.filter {
                            $0.sessionExerciseID == snapshot.id && $0.isCompleted && !$0.isWarmup
                        }
                        return total + snapshotLogs.reduce(0.0) { subtotal, log in
                            let weight = snapshot.volumeUnit == .bodyweight
                                ? snapshot.bodyWeightKgSnapshot
                                : log.actualWeight
                            return subtotal + (snapshot.volumeUnit.volume(weight: weight, reps: log.actualReps) ?? 0)
                        }
                    }
                }
            let volumeSummaries = volumeByUnit
                .map { "\(Int($0.value)) \($0.key.symbol)" }
                .sorted()
            let days = max(0, Calendar.current.dateComponents([.day], from: lastDate.startOfDay, to: now.startOfDay).day ?? 0)
            if days <= 1 {
                return MuscleGroupAdvice(
                    muscleGroup: group,
                    readiness: .recover,
                    title: "优先恢复或换肌群",
                    detail: "上次训练距今 \(days) 天，近 7 天已完成 \(recentSets) 组；若仍酸痛，今天降低训练量。",
                    lastTrainedAt: lastDate,
                    completedSetsLast7Days: recentSets,
                    lastWorkoutName: lastSession?.templateName,
                    lastVolumeSummaries: volumeSummaries
                )
            } else if days <= 3 || recentSets >= 16 {
                return MuscleGroupAdvice(
                    muscleGroup: group,
                    readiness: .moderate,
                    title: "适合中等训练量",
                    detail: "距上次 \(days) 天，近 7 天 \(recentSets) 组；建议保留 1–3 RIR。",
                    lastTrainedAt: lastDate,
                    completedSetsLast7Days: recentSets,
                    lastWorkoutName: lastSession?.templateName,
                    lastVolumeSummaries: volumeSummaries
                )
            } else {
                return MuscleGroupAdvice(
                    muscleGroup: group,
                    readiness: .ready,
                    title: "恢复较充分",
                    detail: "距上次 \(days) 天，近 7 天 \(recentSets) 组；可安排主项加不同模式的辅助动作。",
                    lastTrainedAt: lastDate,
                    completedSetsLast7Days: recentSets,
                    lastWorkoutName: lastSession?.templateName,
                    lastVolumeSummaries: volumeSummaries
                )
            }
        }
    }

    private static func lastPerformance(
        session: WorkoutSession,
        snapshot: SessionExercise,
        setLogs: [SetLog]
    ) -> ExerciseLastPerformance? {
        let sets = setLogs
            .filter { $0.sessionExerciseID == snapshot.id && $0.isCompleted }
            .sorted { $0.setNumber < $1.setNumber }
            .map {
                ExerciseSetSnapshot(
                    setNumber: $0.setNumber,
                    weight: $0.actualWeight,
                    reps: $0.actualReps,
                    rir: $0.rir
                )
            }
        guard !sets.isEmpty else { return nil }
        return ExerciseLastPerformance(
            date: session.startedAt,
            workoutName: session.templateName,
            sets: sets,
            workoutNotes: session.notes,
            performanceNotes: snapshot.performanceNotes,
            volumeUnit: snapshot.volumeUnit,
            bodyWeightKgSnapshot: snapshot.bodyWeightKgSnapshot
        )
    }

    private static func recommendedTarget(
        exercise: Exercise,
        lastHistory: (WorkoutSession, SessionExercise)?,
        lastPerformance: ExerciseLastPerformance?,
        previousPerformance: ExerciseLastPerformance?,
        baseline: TemplateExercise?,
        setLogs: [SetLog],
        goalMode: TrainingGoalMode
    ) -> (
        sets: Int,
        minReps: Int,
        maxReps: Int,
        weight: Double,
        restSeconds: Int,
        assessment: ProgressionAssessment
    ) {
        guard let lastHistory, let lastPerformance else {
            let sets = baseline?.targetSets ?? (goalMode == .cuttingVolume ? 4 : 3)
            let minReps = baseline?.minReps ?? (goalMode == .cuttingVolume ? 10 : 8)
            let maxReps = baseline?.maxReps ?? (goalMode == .cuttingVolume ? 15 : 12)
            let weight = baseline?.targetWeight ?? 0
            return (
                sets,
                minReps,
                maxReps,
                weight,
                baseline?.restSeconds ?? exercise.defaultRestSeconds,
                TrainingMetrics.progressionAssessment(
                    weights: [],
                    completedReps: [],
                    minimumReps: minReps,
                    maximumReps: maxReps,
                    rirValues: [],
                    goalMode: goalMode
                )
            )
        }

        let snapshot = lastHistory.1
        let logs = setLogs
            .filter { $0.sessionExerciseID == snapshot.id && $0.isCompleted }
            .sorted { $0.setNumber < $1.setNumber }
        let repRange = suggestedRepRange(
            reps: logs.map(\.actualReps),
            fallbackMinimum: snapshot.minReps,
            fallbackMaximum: snapshot.maxReps,
            goalMode: goalMode
        )
        let assessment = TrainingMetrics.progressionAssessment(
            weights: logs.map(\.actualWeight),
            completedReps: logs.map(\.actualReps),
            minimumReps: repRange.minimum,
            maximumReps: repRange.maximum,
            rirValues: logs.map(\.rir),
            previousVolume: previousPerformance?.volume,
            goalMode: goalMode
        )
        let lastWeight = goalMode == .cuttingVolume
            ? lastPerformance.workingWeight
            : lastPerformance.bestSet?.weight ?? snapshot.targetWeight
        let increment = (exercise.muscleGroup == "腿部" && exercise.equipment == "杠铃") ? 5.0 : 2.5
        let weight: Double
        switch assessment.recommendation {
        case .increase(let percent):
            weight = goalMode == .cuttingVolume
                ? roundedToHalf(lastWeight * (1 + percent))
                : lastWeight + increment
        case .maintain:
            weight = lastWeight
        case .reduce:
            weight = roundedToHalf(max(0, lastWeight * (goalMode == .cuttingVolume ? 0.95 : 0.9)))
        }
        return (
            max(1, logs.count),
            repRange.minimum,
            repRange.maximum,
            weight,
            snapshot.restSeconds,
            assessment
        )
    }

    private static func suggestedRepRange(
        reps: [Int],
        fallbackMinimum: Int,
        fallbackMaximum: Int,
        goalMode: TrainingGoalMode
    ) -> (minimum: Int, maximum: Int) {
        guard goalMode == .cuttingVolume, !reps.isEmpty else {
            return (fallbackMinimum, fallbackMaximum)
        }
        let average = Int(
            (Double(reps.reduce(0, +)) / Double(reps.count)).rounded()
        )
        if average >= 12 {
            return (max(8, average - 2), min(20, max(15, average + 2)))
        }
        if average <= 7 {
            return (max(5, average - 1), max(8, average + 2))
        }
        return (max(6, average - 2), min(15, average + 2))
    }

    private static func roundedToHalf(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    private static func stableVariantBias(for id: UUID, variant: Int) -> Double {
        let scalar = id.uuidString.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 19 }
        return Double((scalar + variant * 7) % 19) / 10
    }
}
