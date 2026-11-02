import SwiftUI

/// Read-only context shared by planning and review. Display history is deliberately
/// broader than the existing automatic load-recommendation qualification contract.
struct TrainingPlanHistory: Equatable {
    struct Row: Equatable {
        var id: UUID
        var weight: Double?
        var reps: Int
        var rir: Int?
        var weightSide: MeasurementSide
        var repsSide: MeasurementSide
    }
    var sourceSessionID: UUID?
    var date: Date?
    var rows: [Row] = []
    var equipmentVerified = false
    var classificationUnknown = false
    var eligibleSetIDs: Set<UUID> = []
    var limitation = "暂无同动作完成记录"

    private static func specificEquipment(_ value: String) -> Bool {
        !["", "器械", "机器", "其他", "未知", "未记录"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func resolve(exercise: Exercise, before: Date, excludingSessionID: UUID? = nil,
                        sessions: [WorkoutSession], snapshots: [SessionExercise], logs: [SetLog],
                        schedules: [ScheduledWorkout]) -> Self {
        guard let reference = WorkoutHistoryResolver.latest(exerciseID: exercise.id, unit: exercise.volumeUnit,
            equipment: exercise.equipment, before: before, excludingSessionID: excludingSessionID,
            sessions: sessions, snapshots: snapshots, logs: logs, schedules: schedules) else {
            let other = snapshots.contains { $0.exerciseID == exercise.id }
            return Self(limitation: other ? "已有记录的单位、器械或完成状态不兼容，仅保留原记录" : "暂无同动作完成记录")
        }
        let source = sessions.first { $0.id == reference.sessionID }
        let verified = reference.equipmentVerified && specificEquipment(exercise.equipment)
        let unknown = source.map { $0.importIdentifier.lowercased().contains("notes") || $0.notes.contains("Notes") } ?? false
        let rows = reference.sets.map { value -> Row in
            let log = logs.first { $0.id == value.id }
            return Row(id: value.id, weight: log?.isActualWeightBlank == true ? nil : value.weight,
                reps: value.reps, rir: log?.rir, weightSide: value.weightSide, repsSide: value.repsSide)
        }
        let recent = before.timeIntervalSince(reference.date) >= 0 && before.timeIntervalSince(reference.date) <= 42 * 86_400
        let eligible = rows.filter {
            exercise.volumeUnit == .kilogram && verified && recent && !unknown
                && $0.weight.map { $0.isFinite && $0 > 0 } == true && $0.reps > 0
                && $0.weightSide != .unknown && $0.repsSide != .unknown && ($0.rir ?? -1) >= 2
        }
        let limitation = unknown ? "Notes原始记录行，热身／工作性质待核；不自动建议重量"
            : (!verified ? "历史器械未核对，仅供参考"
            : (!recent ? "超过42天，仅供参考" : (eligible.count == rows.count ? "同动作、同器械及已记录口径" : "余力或口径缺项，不据此自动加重")))
        return Self(sourceSessionID: reference.sessionID, date: reference.date, rows: rows,
            equipmentVerified: verified, classificationUnknown: unknown,
            eligibleSetIDs: Set(eligible.map(\.id)), limitation: limitation)
    }

    static func observed(_ observation: CoachObservation, date: Date?) -> Self {
        Self(date: date, rows: observation.working.map {
            Row(id: $0.id, weight: $0.weight, reps: $0.reps, rir: $0.rir,
                weightSide: $0.weightSide, repsSide: $0.repsSide)
        }, equipmentVerified: specificEquipment(observation.equipment),
        classificationUnknown: observation.historicalClassificationUnknown ?? observation.notes.contains("Notes"),
        limitation: "本次已完成记录；自动建议仍需同机、口径及真实余力核对")
    }

    func volumeComparison(plans: [WorkoutSetPlan], unit: ExerciseVolumeUnit) -> String {
        guard !rows.isEmpty else { return limitation }
        guard unit == .kilogram, equipmentVerified, !classificationUnknown,
              let side = rows.first, side.weightSide != .unknown, side.repsSide != .unknown,
              rows.allSatisfy({ $0.weight != nil && $0.weight! > 0 && $0.reps > 0 && $0.weightSide == side.weightSide && $0.repsSide == side.repsSide }),
              !plans.isEmpty, plans.allSatisfy({ $0.weight > 0 && $0.weightSide == side.weightSide && $0.repsSide == side.repsSide }) else {
            return "容量暂不可比 · 单位、器械、口径或组别性质待核"
        }
        let previous = rows.reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps) }
        let planned = plans.reduce(0) { $0 + $1.weight * Double($1.reps) }
        guard previous > 0, previous.isFinite, planned.isFinite else { return "容量暂不可比" }
        let delta = (planned - previous) / previous * 100
        return "记录容量 \(previous.formatted(.number.precision(.fractionLength(0...1)) )) → 计划 \(planned.formatted(.number.precision(.fractionLength(0...1)))) kg×次 · \(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    /// Only an already-observed qualifying staircase supplies automatic per-set
    /// values. No machine increment or missing RIR is inferred from a pattern name.
    func initialPlans(pattern: SetPlanPattern, count: Int, weight: Double, reps: Int) -> [WorkoutSetPlan] {
        let source = Array(rows.prefix(count))
        let increasing = zip(source, source.dropFirst()).allSatisfy { pair in
            (pair.0.weight ?? 0) <= (pair.1.weight ?? 0) && pair.0.reps >= pair.1.reps
        }
        if pattern == .pyramidUp, source.count == count, source.count > 1, increasing,
           source.allSatisfy({ eligibleSetIDs.contains($0.id) }),
           Set(source.compactMap(\.weight)).count > 1 {
            return source.map { WorkoutSetPlan(weight: $0.weight!, reps: $0.reps,
                weightSide: $0.weightSide, repsSide: $0.repsSide) }
        }
        return (0..<max(1, count)).map { _ in WorkoutSetPlan(weight: weight, reps: reps) }
    }
}

struct TrainingPlanHistoryComparison: View {
    let history: TrainingPlanHistory
    let plans: [WorkoutSetPlan]
    let unit: ExerciseVolumeUnit
    let exerciseName: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("上次实际 → 本次计划").font(.subheadline.bold())
            if let date = history.date { Text(date, format: .dateTime.year().month().day()).font(.caption) }
            if history.rows.isEmpty { Text(history.limitation).font(.caption) }
            else {
                Text("上次\(history.rows.count)\(history.classificationUnknown ? "条记录" : "组") · 本次\(plans.count)计划组")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                ForEach(0..<max(history.rows.count, plans.count), id: \.self) { index in
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("第\(index + 1)组").bold()
                            Text("上次：" + actual(index))
                            Text("计划：" + planned(index))
                        }.font(.caption).padding(.vertical, 4)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)").frame(width: 18)
                            Text(actual(index)).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right").accessibilityHidden(true)
                            Text(planned(index)).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.caption.monospacedDigit()).padding(.vertical, 3)
                    }
                }
                Text(history.volumeComparison(plans: plans, unit: unit)).font(.caption)
                Text(history.limitation).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("历史计划对比-\(exerciseName)")
    }

    private func actual(_ index: Int) -> String {
        guard history.rows.indices.contains(index) else { return "新增计划组" }
        let row = history.rows[index]
        let base = unit == .bodyweight ? "自重 × \(row.reps)" : (unit.recordsSingleAmount ? "\(row.reps) \(unit.symbol)" : "\(row.weight.map(TrainingFormatters.weight) ?? "未知") × \(row.reps)")
        return base + (row.rir.map { " · RIR\($0)" } ?? " · 余力未知")
    }
    private func planned(_ index: Int) -> String {
        guard plans.indices.contains(index) else { return "本次未安排" }
        return TrainingWorkoutPresentation.planValue(plans[index], unit: unit)
    }
}
