import Foundation

struct MuscleCoverageValue: Identifiable, Equatable {
    let group: String
    let completedSets: Int
    var id: String { group }
}

enum WorkoutMeasurementSideEditing {
    static func selected(in logs: [SetLog]) -> MeasurementSide {
        let ordered = logs.sorted { $0.setNumber < $1.setNumber }
        return (ordered.first { !$0.isCompleted } ?? ordered.first)?.actualWeightSide ?? .bilateral
    }

    static func apply(_ side: MeasurementSide, to exercise: SessionExercise, logs: [SetLog]) {
        let matching = logs.filter { $0.sessionExerciseID == exercise.id && $0.sessionID == exercise.sessionID }
        let pending = matching.filter { !$0.isCompleted }
        guard !pending.isEmpty else { return }
        let completedNumbers = Set(matching.filter(\.isCompleted).map(\.setNumber))
        exercise.plannedSets = exercise.plannedSets.enumerated().map { index, plan in
            guard !completedNumbers.contains(index + 1) else { return plan }
            return WorkoutSetPlan(id: plan.id, weight: plan.weight, reps: plan.reps,
                weightSide: side, repsSide: side)
        }
        for log in pending {
            log.targetWeightSide = side
            log.targetRepsSide = side
            log.actualWeightSide = side
            log.actualRepsSide = side
        }
    }
}

struct WorkoutActualReference: Equatable {
    let date: Date
    let rows: [String]
}

enum MuscleCoverageService {
    /// Training diagrams use anatomical left/right; the legacy pain catalog stays unchanged.
    static func horizontalPosition(for region: BodyRegionDefinition) -> Double {
        region.side == .front ? 1 - region.x : region.x
    }
    static let groups = ["胸部", "背部", "肩部", "手臂", "腿部", "臀部", "小腿", "核心"]
    private static let aliases: [String: [String]] = [
        "胸部": ["胸", "chest", "pectoral"], "背部": ["背", "斜方", "back", "latissimus", "lats"],
        "肩部": ["肩", "三角", "shoulder", "delt"], "手臂": ["手臂", "二头", "三头", "前臂", "bicep", "tricep", "arm"],
        "腿部": ["腿部", "大腿", "股四", "腘绳", "leg", "quad", "hamstring"],
        "臀部": ["臀", "glute"], "小腿": ["小腿", "calf", "calves"], "核心": ["核心", "腹", "core", "abs"]
    ]
    static func groups(in text: String) -> Set<String> {
        let value = text.lowercased()
        if value == "腿" { return ["腿部"] }
        return Set(groups.filter { group in aliases[group, default: []].contains { value.contains($0) } })
    }
    static func group(for regionID: String) -> String? {
        if regionID.contains("knee") || regionID.contains("hip") || regionID.contains("neck") { return nil }
        if regionID.contains("shoulder") { return "肩部" }
        if regionID.contains("chest") { return "胸部" }
        if regionID.contains("biceps") || regionID.contains("triceps") || regionID.contains("forearm") { return "手臂" }
        if regionID.contains("abdomen") { return "核心" }
        if regionID.contains("quadriceps") || regionID.contains("hamstring") { return "腿部" }
        if regionID.contains("glute") { return "臀部" }
        if regionID.contains("calf") || regionID.contains("shin") { return "小腿" }
        if ["back-upper", "back-lower", "back-left-lat", "back-right-lat"].contains(regionID) { return "背部" }
        return nil
    }
    static func coverage(from start: Date, through end: Date, sessions: [WorkoutSession], snapshots: [SessionExercise], logs: [SetLog]) -> [MuscleCoverageValue] {
        let sessionsByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshotsByID = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var counts: [String: Int] = [:]
        var seen: Set<UUID> = []
        for log in logs where log.isCompleted && !log.isWarmup && seen.insert(log.id).inserted {
            guard let snapshot = snapshotsByID[log.sessionExerciseID], snapshot.sessionID == log.sessionID,
                  let session = sessionsByID[log.sessionID], session.status != .discarded else { continue }
            let date = log.completedAt ?? session.completedAt ?? session.startedAt
            guard date >= start && date <= end else { continue }
            let mapped = groups(in: snapshot.muscleGroup)
            if mapped.isEmpty {
                let original = snapshot.muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                counts[original.isEmpty ? "未标注肌群" : original, default: 0] += 1
            } else {
                for group in mapped { counts[group, default: 0] += 1 }
            }
        }
        let ordered = groups + counts.keys.filter { !groups.contains($0) }.sorted()
        return ordered.map { MuscleCoverageValue(group: $0, completedSets: counts[$0, default: 0]) }
    }
    static func stableOrder(_ snapshots: [SessionExercise], sessionID: UUID) -> [SessionExercise] {
        snapshots.filter { $0.sessionID == sessionID }.sorted {
            $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
        }
    }
    static func initialExpandedID(_ snapshots: [SessionExercise], logs: [SetLog]) -> UUID? {
        snapshots.first { snapshot in
            let rows = logs.filter { $0.sessionExerciseID == snapshot.id && $0.sessionID == snapshot.sessionID }
            return rows.isEmpty || rows.contains { !$0.isCompleted }
        }?.id ?? snapshots.first?.id
    }
    static func lastReference(for exercise: SessionExercise, sessions: [WorkoutSession], snapshots: [SessionExercise], logs: [SetLog]) -> WorkoutActualReference? {
        let currentStart = sessions.first { $0.id == exercise.sessionID }?.startedAt ?? .now
        let candidates = sessions.filter { $0.id != exercise.sessionID && $0.status == .completed && ($0.completedAt ?? $0.startedAt) <= currentStart }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
        for session in candidates {
            let previous = snapshots.filter { $0.sessionID == session.id && $0.exerciseID == exercise.exerciseID && $0.volumeUnit == exercise.volumeUnit }
            let ids = Set(previous.map(\.id))
            let rows = logs.filter { $0.sessionID == session.id && ids.contains($0.sessionExerciseID) && $0.isCompleted && !$0.isWarmup }
                .sorted { $0.setNumber < $1.setNumber }
            guard !rows.isEmpty else { continue }
            let text = rows.map { row in
                if exercise.volumeUnit.recordsSingleAmount { return "\(row.actualReps) \(exercise.volumeUnit.symbol)" }
                if exercise.volumeUnit == .bodyweight { return "自重 × \(row.actualReps)" }
                return "\(TrainingFormatters.weight(row.actualWeight)) \(exercise.volumeUnit.symbol) × \(row.actualReps) · \(row.actualWeightSide.title)"
            }
            return WorkoutActualReference(date: session.startedAt, rows: text)
        }
        return nil
    }
}
