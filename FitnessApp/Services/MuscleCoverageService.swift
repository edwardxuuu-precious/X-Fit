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
        for log in pending {
            log.actualWeightSide = side
            log.actualRepsSide = side
            log.markActualEntryEdited()
        }
    }
}

struct WorkoutActualReference: Equatable {
    let date: Date
    let rows: [String]
}

struct WorkoutHistorySet: Equatable {
    let id: UUID
    let weight: Double
    let reps: Int
    let weightSide: MeasurementSide
    let repsSide: MeasurementSide
    let weightIsBlank: Bool

    init(id: UUID, weight: Double, reps: Int, weightSide: MeasurementSide,
         repsSide: MeasurementSide, weightIsBlank: Bool = false) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.weightSide = weightSide
        self.repsSide = repsSide
        self.weightIsBlank = weightIsBlank
    }

    func canPrefill(unit: ExerciseVolumeUnit) -> Bool {
        weight.isFinite && weight >= 0 && reps > 0
            && (!unit.recordsNumericLoad || !weightIsBlank)
            && (!unit.usesMeasurementSide || (weightSide != .unknown && repsSide != .unknown))
    }
}

struct WorkoutHistoryReference: Equatable {
    let sessionID: UUID
    let date: Date
    let sets: [WorkoutHistorySet]
    let equipmentVerified: Bool
    let restSeconds: Int

    func prefillableSet(at index: Int, unit: ExerciseVolumeUnit) -> WorkoutHistorySet? {
        guard equipmentVerified, sets.indices.contains(index), sets[index].canPrefill(unit: unit) else { return nil }
        return sets[index]
    }
}

struct WorkoutInitialActual: Equatable {
    let weight: Double
    let reps: Int
    let weightSide: MeasurementSide
    let repsSide: MeasurementSide
    let source: WorkoutActualEntrySource
    let sourceHistorySetID: UUID?
    let weightIsBlank: Bool

    enum Selection {
        case automatic(reference: WorkoutHistoryReference?, setIndex: Int)
        case confirmedSetup
    }

    static func resolve(fallback: Self, unit: ExerciseVolumeUnit, selection: Selection) -> Self {
        switch selection {
        case .confirmedSetup:
            return Self(weight: fallback.weight, reps: fallback.reps, weightSide: fallback.weightSide,
                repsSide: fallback.repsSide, source: .manual, sourceHistorySetID: nil,
                weightIsBlank: fallback.weightIsBlank)
        case let .automatic(reference, index):
            guard let previous = reference?.prefillableSet(at: index, unit: unit) else { return fallback }
            return Self(weight: unit.recordsNumericLoad ? previous.weight : fallback.weight,
                reps: previous.reps, weightSide: previous.weightSide, repsSide: previous.repsSide,
                source: .history, sourceHistorySetID: previous.id, weightIsBlank: false)
        }
    }
}

/// One structured source for both historical display and entry defaults. No RIR/age filter:
/// copying a user's record is not a recommendation to increase training load.
enum WorkoutHistoryResolver {
    static func equipment(for snapshot: SessionExercise, sessions: [WorkoutSession], schedules: [ScheduledWorkout]) -> String? {
        if let stored = snapshot.equipmentSnapshot, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return stored }
        guard let scheduleID = sessions.first(where: { $0.id == snapshot.sessionID })?.scheduledWorkoutID else { return nil }
        return schedules.first(where: { $0.id == scheduleID })?.planSnapshot
            .first(where: { $0.exerciseID == snapshot.exerciseID && $0.volumeUnit == snapshot.volumeUnit })?.equipment
    }

    static func latest(exerciseID: UUID, unit: ExerciseVolumeUnit, equipment: String?, before: Date,
                       excludingSessionID: UUID? = nil, sessions: [WorkoutSession], snapshots: [SessionExercise],
                       logs: [SetLog], schedules: [ScheduledWorkout] = []) -> WorkoutHistoryReference? {
        func normalized(_ value: String?) -> String? {
            guard let value else { return nil }
            let result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return result.isEmpty ? nil : result
        }
        let expectedEquipment = normalized(equipment)
        let candidates = sessions.filter {
            $0.id != excludingSessionID && $0.status == .completed && ($0.completedAt ?? $0.startedAt) <= before
        }.sorted {
            let left = $0.completedAt ?? $0.startedAt, right = $1.completedAt ?? $1.startedAt
            return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
        }
        var unverified: WorkoutHistoryReference?
        for session in candidates {
            for snapshot in snapshots.filter({ $0.sessionID == session.id && $0.exerciseID == exerciseID && $0.volumeUnit == unit }).sorted(by: { $0.order < $1.order }) {
                let actualEquipment = normalized(Self.equipment(for: snapshot, sessions: sessions, schedules: schedules))
                if let expectedEquipment, let actualEquipment, expectedEquipment != actualEquipment { continue }
                let verified = expectedEquipment != nil && actualEquipment == expectedEquipment
                let rows = logs.filter { $0.sessionID == session.id && $0.sessionExerciseID == snapshot.id
                    && $0.exerciseID == exerciseID && $0.isCompleted && !$0.isWarmup }
                    .sorted { $0.setNumber == $1.setNumber ? $0.id.uuidString < $1.id.uuidString : $0.setNumber < $1.setNumber }
                guard !rows.isEmpty else { continue }
                let reference = WorkoutHistoryReference(sessionID: session.id, date: session.startedAt,
                    sets: rows.map { WorkoutHistorySet(id: $0.id, weight: $0.actualWeight, reps: $0.actualReps,
                        weightSide: $0.actualWeightSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? .unknown,
                        repsSide: $0.actualRepsSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? .unknown,
                        weightIsBlank: $0.isActualWeightBlank) },
                    equipmentVerified: verified, restSeconds: snapshot.restSeconds)
                if verified { return reference }
                if unverified == nil { unverified = reference }
            }
        }
        return unverified
    }

    static func display(_ reference: WorkoutHistoryReference, unit: ExerciseVolumeUnit) -> WorkoutActualReference {
        let rows = reference.sets.map { row in
            if unit.recordsSingleAmount { return "\(row.reps) \(unit.symbol)" }
            if unit == .bodyweight { return "自重 × \(row.reps)" }
            let load = unit.recordsNumericLoad && row.weightIsBlank ? "重量未记录" : "\(TrainingFormatters.weight(row.weight)) \(unit.symbol)"
            return "\(load) × \(row.reps) · 重量\(row.weightSide.title)／次数\(row.repsSide.title)"
        }
        return WorkoutActualReference(date: reference.date, rows: rows)
    }
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
    static func lastReference(for exercise: SessionExercise, sessions: [WorkoutSession], snapshots: [SessionExercise], logs: [SetLog], schedules: [ScheduledWorkout] = []) -> WorkoutActualReference? {
        let currentStart = sessions.first { $0.id == exercise.sessionID }?.startedAt ?? .now
        guard let reference = WorkoutHistoryResolver.latest(exerciseID: exercise.exerciseID, unit: exercise.volumeUnit,
            equipment: WorkoutHistoryResolver.equipment(for: exercise, sessions: sessions, schedules: schedules),
            before: currentStart, excludingSessionID: exercise.sessionID, sessions: sessions, snapshots: snapshots, logs: logs, schedules: schedules) else { return nil }
        return WorkoutHistoryResolver.display(reference, unit: exercise.volumeUnit)
    }
}
