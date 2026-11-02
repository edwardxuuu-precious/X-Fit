import Foundation
import SwiftData

enum ScheduleStatus: String, Codable {
    case planned
    case inProgress
    case completed
    case skipped
}

enum WorkoutSessionStatus: String, Codable {
    case inProgress
    case completed
    case discarded
}

enum WorkoutRestMode: String, Codable, CaseIterable, Identifiable {
    case countdown
    case freestyle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countdown: return "固定倒计时"
        case .freestyle: return "自由记录"
        }
    }
}

enum RestDurationInputValidation: Equatable {
    case empty
    case valid(Int)
    case invalid(String)

    var seconds: Int? {
        guard case let .valid(value) = self else { return nil }
        return value
    }

    var errorMessage: String? {
        guard case let .invalid(message) = self else { return nil }
        return message
    }

    var isValid: Bool {
        if case .invalid = self { return false }
        return true
    }
}

enum RestDurationInput {
    /// A rest longer than 24 hours is almost certainly an input error.
    static let maximumSeconds = 86_400

    static func validate(_ rawValue: String) -> RestDurationInputValidation {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .empty }
        guard value.unicodeScalars.allSatisfy({ (48...57).contains(Int($0.value)) }) else {
            return .invalid("休息秒数只能输入 0–9，不能包含负号、小数或其他字符。")
        }
        guard let seconds = Int(value), seconds <= maximumSeconds else {
            return .invalid("休息秒数不能超过 \(maximumSeconds) 秒。")
        }
        return .valid(seconds)
    }
}

enum ExerciseVolumeUnit: String, Codable, CaseIterable, Identifiable {
    case count
    case second
    case meter
    case kilogram
    case bodyweight

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .count: return "个"
        case .second: return "秒"
        case .meter: return "米"
        case .kilogram: return "kg"
        case .bodyweight: return "kg·次"
        }
    }

    var title: String {
        switch self {
        case .count: return "个（次数）"
        case .second: return "秒（时长）"
        case .meter: return "米（距离）"
        case .kilogram: return "kg（重量 × 次数）"
        case .bodyweight: return "自重（体重 × 次数）"
        }
    }

    var inputTitle: String {
        switch self {
        case .count: return "数量"
        case .second: return "秒数"
        case .meter: return "距离"
        case .kilogram: return "重量"
        case .bodyweight: return "自重"
        }
    }

    var repetitionTitle: String {
        switch self {
        case .count, .second: return ""
        case .meter: return "趟数"
        case .kilogram: return "次数"
        case .bodyweight: return "次数"
        }
    }

    func volume(weight: Double, reps: Int) -> Double {
        switch self {
        case .count, .second:
            return Double(max(0, reps))
        case .meter, .kilogram, .bodyweight:
            guard weight.isFinite else { return 0 }
            let result = max(0, weight) * Double(max(0, reps))
            return result.isFinite ? result : 0
        }
    }

    func volume(weight: Double?, reps: Int) -> Double? {
        switch self {
        case .count, .second:
            return Double(max(0, reps))
        case .meter, .kilogram, .bodyweight:
            guard let weight, weight > 0 else { return nil }
            guard weight.isFinite else { return nil }
            let result = weight * Double(max(0, reps))
            return result.isFinite ? result : nil
        }
    }

    var recordsNumericLoad: Bool {
        self == .meter || self == .kilogram
    }

    var recordsSingleAmount: Bool {
        self == .count || self == .second
    }

    var usesMeasurementSide: Bool {
        self == .kilogram
    }
}

enum ExerciseTerminologyReviewStatus: String, Codable, CaseIterable, Identifiable {
    case approvalReady
    case mergeReview
    case variantReview
    case unresolved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approvalReady: return "候选名可审批"
        case .mergeReview: return "待确认是否同一动作"
        case .variantReview: return "待补具体变式"
        case .unresolved: return "名称未唯一解析"
        }
    }
}

enum ExerciseTerminologyDecision: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待审核"
        case .accepted: return "已接受候选"
        case .rejected: return "保留当前名称"
        }
    }
}

enum ExerciseTerminologyConfidence: String, Codable, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }
}

enum SetPlanPattern: String, Codable, CaseIterable, Identifiable {
    case fixed
    case pyramidUp
    case pyramidDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed: return "固定重量"
        case .pyramidUp: return "金字塔递增"
        case .pyramidDown: return "金字塔递减"
        }
    }
}

enum PlanPatternSource: String, Codable, CaseIterable, Identifiable {
    case dayDefault
    case exerciseOverride

    var id: String { rawValue }
}

enum MeasurementSide: String, Codable, CaseIterable, Identifiable {
    case single
    case bilateral
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return "单边"
        case .bilateral: return "双边"
        case .unknown: return "未注明"
        }
    }
}

enum WorkoutFeeling: String, Codable, CaseIterable, Identifiable {
    case painful
    case exhausted
    case hard
    case good
    case strong

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .painful: return "😣"
        case .exhausted: return "😥"
        case .hard: return "😮"
        case .good: return "🙂"
        case .strong: return "😄"
        }
    }

    var title: String {
        switch self {
        case .painful: return "不适 / 疼痛"
        case .exhausted: return "太难"
        case .hard: return "有挑战"
        case .good: return "正合适"
        case .strong: return "轻松顺畅"
        }
    }
}

enum WorkoutActualDefaultPolicy: String, Codable { case history, plan, blank }
enum WorkoutActualEntrySource: String, Codable { case plan, history, manual, blank, legacy }

/// Optional prescription metadata belongs to the plan, never to the actual log.
struct WorkoutSetPrescription: Codable, Hashable {
    var label: String
    var repsLower: Int
    var repsUpper: Int
    var rirLower: Int? = nil
    var rirUpper: Int? = nil
    var restLowerSeconds: Int
    var restUpperSeconds: Int
    var effortCue: String? = nil

    var isValid: Bool {
        guard !label.isEmpty, (1...86400).contains(repsLower), (repsLower...86400).contains(repsUpper),
              (0...3600).contains(restLowerSeconds), (restLowerSeconds...3600).contains(restUpperSeconds) else { return false }
        if rirLower == nil && rirUpper == nil { return true }
        guard let lower = rirLower, let upper = rirUpper else { return false }
        return (0...10).contains(lower) && (lower...10).contains(upper)
    }

    var summary: String {
        var parts = [label, repsLower == repsUpper ? "\(repsLower)" : "\(repsLower)–\(repsUpper)"]
        if let lower = rirLower, let upper = rirUpper {
            parts.append(lower == upper ? "RIR \(lower)" : "RIR \(lower)–\(upper)")
        }
        if let effortCue, !effortCue.isEmpty { parts.append(effortCue) }
        parts.append(restLowerSeconds == restUpperSeconds ? "休息 \(restLowerSeconds) 秒" : "休息 \(restLowerSeconds)–\(restUpperSeconds) 秒")
        return parts.joined(separator: " · ")
    }
}

struct WorkoutSetPlan: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var weight: Double
    var reps: Int
    var weightSide: MeasurementSide
    var repsSide: MeasurementSide
    /// Optional so earlier per-set JSON remains readable. This is an entry policy, not a load recommendation.
    var actualDefaultPolicyRaw: String?
    var prescription: WorkoutSetPrescription? = nil

    var actualDefaultPolicy: WorkoutActualDefaultPolicy {
        guard let actualDefaultPolicyRaw else { return .history }
        return WorkoutActualDefaultPolicy(rawValue: actualDefaultPolicyRaw) ?? .plan
    }

    init(
        id: UUID = UUID(),
        weight: Double,
        reps: Int,
        weightSide: MeasurementSide = .bilateral,
        repsSide: MeasurementSide = .bilateral,
        actualDefaultPolicy: WorkoutActualDefaultPolicy? = nil,
        prescription: WorkoutSetPrescription? = nil
    ) {
        self.id = id
        self.weight = max(0, weight)
        self.reps = max(1, reps)
        self.weightSide = weightSide
        self.repsSide = repsSide
        self.actualDefaultPolicyRaw = actualDefaultPolicy?.rawValue
        self.prescription = prescription
    }

    static func preset(
        _ pattern: SetPlanPattern,
        count: Int,
        baseWeight: Double,
        baseReps: Int,
        weightSide: MeasurementSide = .bilateral,
        repsSide: MeasurementSide = .bilateral
    ) -> [WorkoutSetPlan] {
        let safeCount = min(max(1, count), 12)
        let weightStep = baseWeight > 0 ? 2.5 : 0
        let repStep = 2

        return (0..<safeCount).map { index in
            let progressionIndex: Int
            switch pattern {
            case .fixed:
                progressionIndex = 0
            case .pyramidUp:
                progressionIndex = index
            case .pyramidDown:
                progressionIndex = safeCount - 1 - index
            }
            return WorkoutSetPlan(
                weight: max(0, baseWeight + Double(progressionIndex) * weightStep),
                reps: max(1, baseReps - progressionIndex * repStep),
                weightSide: weightSide,
                repsSide: repsSide
            )
        }
    }
}

private enum WorkoutSetPlanCoding {
    static func decode(_ rawValue: String?) -> [WorkoutSetPlan]? {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let plans = try? JSONDecoder().decode([WorkoutSetPlan].self, from: data),
              !plans.isEmpty else {
            return nil
        }
        return plans
    }

    static func encode(_ plans: [WorkoutSetPlan]) -> String? {
        guard !plans.isEmpty,
              let data = try? JSONEncoder().encode(plans) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var muscleGroup: String = ""
    var equipment: String = ""
    var defaultRestSeconds: Int = 90
    var createdAt: Date = Date.now
    var isBuiltIn: Bool = true
    var isArchived: Bool = false
    var notes: String = ""
    /// Optional source used to learn or review a custom exercise.
    var referenceURL: String = ""
    /// Optional so stores created before configurable units migrate as kilograms.
    var volumeUnitRaw: String?
    /// Candidate terminology is kept separate from the historical/raw name.
    /// All fields are optional so existing SwiftData stores can migrate without
    /// inventing an approval decision.
    var terminologyCanonicalID: String?
    var terminologyStandardNameZH: String?
    var terminologyStandardNameEN: String?
    var terminologyReviewStatusRaw: String?
    var terminologyDecisionRaw: String?
    var terminologyConfidenceRaw: String?
    var terminologyMergeGroup: String?
    var terminologyReviewNote: String?
    var terminologyCatalogVersion: String?
    var terminologyReviewedAt: Date?
    var updatedAt: Date = Date.now

    var volumeUnit: ExerciseVolumeUnit {
        get { volumeUnitRaw.flatMap(ExerciseVolumeUnit.init(rawValue:)) ?? .kilogram }
        set { volumeUnitRaw = newValue.rawValue }
    }

    var terminologyReviewStatus: ExerciseTerminologyReviewStatus? {
        get { terminologyReviewStatusRaw.flatMap(ExerciseTerminologyReviewStatus.init(rawValue:)) }
        set { terminologyReviewStatusRaw = newValue?.rawValue }
    }

    var terminologyDecision: ExerciseTerminologyDecision {
        get { terminologyDecisionRaw.flatMap(ExerciseTerminologyDecision.init(rawValue:)) ?? .pending }
        set { terminologyDecisionRaw = newValue.rawValue }
    }

    var terminologyConfidence: ExerciseTerminologyConfidence? {
        get { terminologyConfidenceRaw.flatMap(ExerciseTerminologyConfidence.init(rawValue:)) }
        set { terminologyConfidenceRaw = newValue?.rawValue }
    }

    /// Approved terminology can drive future identity resolution, while the
    /// existing name remains the immutable catalog/history-facing raw label.
    var approvedCanonicalID: String? {
        terminologyDecision == .accepted ? terminologyCanonicalID : nil
    }

    var approvedStandardNameZH: String? {
        terminologyDecision == .accepted ? terminologyStandardNameZH : nil
    }

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: String,
        equipment: String,
        defaultRestSeconds: Int = 90,
        createdAt: Date = .now,
        isBuiltIn: Bool = true,
        isArchived: Bool = false,
        notes: String = "",
        referenceURL: String = "",
        volumeUnit: ExerciseVolumeUnit = .kilogram,
        terminologyCanonicalID: String? = nil,
        terminologyStandardNameZH: String? = nil,
        terminologyStandardNameEN: String? = nil,
        terminologyReviewStatus: ExerciseTerminologyReviewStatus? = nil,
        terminologyDecision: ExerciseTerminologyDecision = .pending,
        terminologyConfidence: ExerciseTerminologyConfidence? = nil,
        terminologyMergeGroup: String? = nil,
        terminologyReviewNote: String? = nil,
        terminologyCatalogVersion: String? = nil,
        terminologyReviewedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.defaultRestSeconds = defaultRestSeconds
        self.createdAt = createdAt
        self.isBuiltIn = isBuiltIn
        self.isArchived = isArchived
        self.notes = notes
        self.referenceURL = referenceURL
        self.volumeUnitRaw = volumeUnit.rawValue
        self.terminologyCanonicalID = terminologyCanonicalID
        self.terminologyStandardNameZH = terminologyStandardNameZH
        self.terminologyStandardNameEN = terminologyStandardNameEN
        self.terminologyReviewStatusRaw = terminologyReviewStatus?.rawValue
        self.terminologyDecisionRaw = terminologyDecision.rawValue
        self.terminologyConfidenceRaw = terminologyConfidence?.rawValue
        self.terminologyMergeGroup = terminologyMergeGroup
        self.terminologyReviewNote = terminologyReviewNote
        self.terminologyCatalogVersion = terminologyCatalogVersion
        self.terminologyReviewedAt = terminologyReviewedAt
        self.updatedAt = createdAt
    }
}

@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var name: String = ""
    /// Calendar weekday: Sunday = 1, Monday = 2, ... Saturday = 7.
    var weekday: Int = 2
    var isActive: Bool = true
    var createdAt: Date = Date.now
    var isOneOff: Bool = false
    var plannedForDate: Date?
    var focusMuscleGroupsRaw: String = ""
    /// Optional so stores created before day-level patterns remain lightweight-migratable.
    var defaultPlanPatternRaw: String?
    var trainingPreferenceSnapshotJSON: String?

    var defaultPlanPattern: SetPlanPattern {
        get { defaultPlanPatternRaw.flatMap(SetPlanPattern.init(rawValue:)) ?? .fixed }
        set { defaultPlanPatternRaw = newValue.rawValue }
    }

    var focusMuscleGroups: [String] {
        get {
            focusMuscleGroupsRaw
                .split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        set {
            focusMuscleGroupsRaw = newValue.joined(separator: ",")
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        weekday: Int,
        isActive: Bool = true,
        createdAt: Date = .now,
        isOneOff: Bool = false,
        plannedForDate: Date? = nil,
        focusMuscleGroups: [String] = [],
        defaultPlanPattern: SetPlanPattern? = nil,
        trainingPreferenceSnapshotJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.weekday = weekday
        self.isActive = isActive
        self.createdAt = createdAt
        self.isOneOff = isOneOff
        self.plannedForDate = plannedForDate?.startOfDay
        self.focusMuscleGroupsRaw = focusMuscleGroups.joined(separator: ",")
        self.defaultPlanPatternRaw = defaultPlanPattern?.rawValue
        self.trainingPreferenceSnapshotJSON = trainingPreferenceSnapshotJSON
    }
}

@Model
final class TemplateExercise {
    var id: UUID = UUID()
    var templateID: UUID = UUID()
    var exerciseID: UUID = UUID()
    var order: Int = 0
    var targetSets: Int = 0
    var minReps: Int = 1
    var maxReps: Int = 1
    var targetWeight: Double = 0
    var restSeconds: Int = 90
    /// Optional JSON keeps stores from older versions lightweight-migratable.
    var plannedSetsJSON: String?
    var planPatternRaw: String?
    /// Nil means a legacy per-exercise value that must not be silently changed.
    var patternSourceRaw: String?

    var planPattern: SetPlanPattern {
        get { planPatternRaw.flatMap(SetPlanPattern.init(rawValue:)) ?? .fixed }
        set { planPatternRaw = newValue.rawValue }
    }

    var patternSource: PlanPatternSource {
        get { patternSourceRaw.flatMap(PlanPatternSource.init(rawValue:)) ?? .exerciseOverride }
        set { patternSourceRaw = newValue.rawValue }
    }

    var plannedSets: [WorkoutSetPlan] {
        get {
            WorkoutSetPlanCoding.decode(plannedSetsJSON)
                ?? WorkoutSetPlan.preset(
                    .fixed,
                    count: targetSets,
                    baseWeight: targetWeight,
                    baseReps: minReps
                )
        }
        set {
            let normalized = newValue.isEmpty
                ? [WorkoutSetPlan(weight: targetWeight, reps: minReps)]
                : newValue
            plannedSetsJSON = WorkoutSetPlanCoding.encode(normalized)
            targetSets = normalized.count
            minReps = normalized.map(\.reps).min() ?? 1
            maxReps = normalized.map(\.reps).max() ?? minReps
            targetWeight = normalized.first?.weight ?? 0
        }
    }

    init(
        id: UUID = UUID(),
        templateID: UUID,
        exerciseID: UUID,
        order: Int,
        targetSets: Int,
        minReps: Int,
        maxReps: Int,
        targetWeight: Double,
        restSeconds: Int,
        plannedSets: [WorkoutSetPlan]? = nil,
        planPattern: SetPlanPattern = .fixed,
        patternSource: PlanPatternSource = .exerciseOverride
    ) {
        self.id = id
        self.templateID = templateID
        self.exerciseID = exerciseID
        self.order = order
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.targetWeight = targetWeight
        self.restSeconds = restSeconds
        self.planPatternRaw = planPattern.rawValue
        self.patternSourceRaw = patternSource.rawValue
        self.plannedSetsJSON = WorkoutSetPlanCoding.encode(
            plannedSets ?? WorkoutSetPlan.preset(
                planPattern,
                count: targetSets,
                baseWeight: targetWeight,
                baseReps: minReps
            )
        )
    }
}

struct ScheduledWorkoutExerciseSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var exerciseID: UUID
    var exerciseName: String
    var muscleGroup: String
    var equipment: String
    var exerciseNotes: String
    var referenceURL: String
    var volumeUnit: ExerciseVolumeUnit
    var order: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var targetWeight: Double
    var restSeconds: Int
    var plannedSets: [WorkoutSetPlan]
    var planPattern: SetPlanPattern
    var patternSource: PlanPatternSource

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        exerciseName: String,
        muscleGroup: String,
        equipment: String,
        exerciseNotes: String,
        referenceURL: String,
        volumeUnit: ExerciseVolumeUnit,
        order: Int,
        targetSets: Int,
        minReps: Int,
        maxReps: Int,
        targetWeight: Double,
        restSeconds: Int,
        plannedSets: [WorkoutSetPlan],
        planPattern: SetPlanPattern,
        patternSource: PlanPatternSource
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.exerciseNotes = exerciseNotes
        self.referenceURL = referenceURL
        self.volumeUnit = volumeUnit
        self.order = order
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.targetWeight = targetWeight
        self.restSeconds = restSeconds
        self.plannedSets = plannedSets
        self.planPattern = planPattern
        self.patternSource = patternSource
    }
}

@Model
final class ScheduledWorkout {
    var id: UUID = UUID()
    var templateID: UUID = UUID()
    var templateName: String = ""
    var plannedDate: Date = Date.now
    var statusRaw: String = ScheduleStatus.planned.rawValue
    var createdAt: Date = Date.now
    var originalPlannedDate: Date?
    var isManuallyScheduled: Bool = false
    var skipReason: String = ""
    var reminderDate: Date?
    var updatedAt: Date = Date.now
    /// Immutable exercise plan captured when the schedule is created.
    var planSnapshotJSON: String?
    /// Civil date is frozen when a new schedule is authored; nil preserves legacy ambiguity.
    var plannedLocalDay: String?
    var plannedTimeZoneIdentifier: String?
    /// Optional provenance for an explicitly confirmed single-day import; legacy schedules remain unchanged.
    var confirmedDailyImportJSON: String?
    /// Optional typed target for manually scheduled jump rope. Existing plans stay unchanged.
    var jumpRopePlanJSON: String?

    var jumpRopePlan: JumpRopeMenuPlan? {
        get {
            guard let data = jumpRopePlanJSON?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(JumpRopeMenuPlan.self, from: data)
        }
        set {
            jumpRopePlanJSON = newValue.flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var status: ScheduleStatus {
        get { ScheduleStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var planSnapshot: [ScheduledWorkoutExerciseSnapshot] {
        get {
            guard let planSnapshotJSON,
                  let data = planSnapshotJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(
                    [ScheduledWorkoutExerciseSnapshot].self,
                    from: data
                  ) else { return [] }
            return decoded.sorted { $0.order < $1.order }
        }
        set {
            guard !newValue.isEmpty,
                  let data = try? JSONEncoder().encode(newValue.sorted(by: { $0.order < $1.order }))
            else {
                planSnapshotJSON = nil
                return
            }
            planSnapshotJSON = String(data: data, encoding: .utf8)
        }
    }

    init(
        id: UUID = UUID(),
        templateID: UUID,
        templateName: String,
        plannedDate: Date,
        status: ScheduleStatus = .planned,
        createdAt: Date = .now,
        originalPlannedDate: Date? = nil,
        isManuallyScheduled: Bool = false,
        skipReason: String = "",
        reminderDate: Date? = nil,
        planSnapshot: [ScheduledWorkoutExerciseSnapshot] = []
    ) {
        self.id = id
        self.templateID = templateID
        self.templateName = templateName
        self.plannedDate = plannedDate.startOfDay
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.originalPlannedDate = originalPlannedDate
        self.isManuallyScheduled = isManuallyScheduled
        self.skipReason = skipReason
        self.reminderDate = reminderDate
        self.updatedAt = createdAt
        self.planSnapshot = planSnapshot
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        self.plannedLocalDay = formatter.string(from: plannedDate)
        self.plannedTimeZoneIdentifier = TimeZone.current.identifier
    }
}

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var scheduledWorkoutID: UUID?
    var templateID: UUID?
    var templateName: String = ""
    var plannedDate: Date = Date.now
    /// Frozen civil ownership for newly authored sessions; nil never guesses a legacy source timezone.
    var trainingLocalDay: String?
    var trainingTimeZoneIdentifier: String?
    var startedAt: Date = Date.now
    /// Nil means a legacy record whose stored start time remains authoritative.
    var startTimeKnownRaw: Bool?
    var completedAt: Date?
    var statusRaw: String = WorkoutSessionStatus.inProgress.rawValue
    var notes: String = ""
    var restEndDate: Date?
    /// Optional for lightweight migration from stores created before rest modes existed.
    var restModeRaw: String?
    var importIdentifier: String = ""
    /// Snapshot of the day-level pattern used when this workout began.
    var defaultPlanPatternRaw: String?
    /// Machine-specific cardio level. Nil preserves older records; never a kg load or an effort score.
    var cardioResistanceLevel: Double?

    var defaultPlanPattern: SetPlanPattern {
        get { defaultPlanPatternRaw.flatMap(SetPlanPattern.init(rawValue:)) ?? .fixed }
        set { defaultPlanPatternRaw = newValue.rawValue }
    }

    var status: WorkoutSessionStatus {
        get { WorkoutSessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    var isStartTimeKnown: Bool {
        get { startTimeKnownRaw ?? true }
        set { startTimeKnownRaw = newValue }
    }

    var restMode: WorkoutRestMode {
        get { restModeRaw.flatMap(WorkoutRestMode.init(rawValue:)) ?? .countdown }
        set { restModeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        scheduledWorkoutID: UUID? = nil,
        templateID: UUID? = nil,
        templateName: String,
        plannedDate: Date,
        startedAt: Date = .now,
        isStartTimeKnown: Bool = true,
        completedAt: Date? = nil,
        status: WorkoutSessionStatus = .inProgress,
        notes: String = "",
        restEndDate: Date? = nil,
        restMode: WorkoutRestMode = .countdown,
        importIdentifier: String = "",
        defaultPlanPattern: SetPlanPattern? = nil
    ) {
        self.id = id
        self.scheduledWorkoutID = scheduledWorkoutID
        self.templateID = templateID
        self.templateName = templateName
        self.plannedDate = plannedDate.startOfDay
        self.startedAt = startedAt
        self.startTimeKnownRaw = isStartTimeKnown
        self.completedAt = completedAt
        self.statusRaw = status.rawValue
        self.notes = notes
        self.restEndDate = restEndDate
        self.restModeRaw = restMode.rawValue
        self.importIdentifier = importIdentifier
        self.defaultPlanPatternRaw = defaultPlanPattern?.rawValue
    }
}

@Model
final class SessionExercise {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var exerciseID: UUID = UUID()
    /// Snapshot fields protect history from later exercise/template edits.
    var exerciseName: String = ""
    var order: Int = 0
    var targetSets: Int = 0
    var minReps: Int = 1
    var maxReps: Int = 1
    var targetWeight: Double = 0
    var restSeconds: Int = 90
    var muscleGroup: String = ""
    var exerciseNotes: String = ""
    /// Snapshot protects historical sessions when the exercise source changes later.
    var referenceURL: String = ""
    /// Historical snapshot; legacy sessions default to kilograms.
    var volumeUnitRaw: String?
    var performanceNotes: String = ""
    /// Per-set plan snapshot; later template edits must not change this session.
    var plannedSetsJSON: String?
    var hasManuallyReducedSets: Bool?
    var planPatternRaw: String?
    var patternSourceRaw: String?
    var feelingRaw: String?
    /// Exercise-level timing survives app restarts and may overlap with other exercises.
    var exerciseStartedAt: Date?
    var exerciseCompletedAt: Date?
    /// Frozen at session start/first interaction so later body measurements cannot rewrite history.
    var bodyWeightKgSnapshot: Double?
    /// Local body-measurement date that supplied the frozen weight; nil means unknown/Health fallback.
    var bodyWeightSnapshotSourceDate: Date?
    /// Never inferred from today's catalog for an old record. Older sessions may resolve from their frozen schedule.
    var equipmentSnapshot: String?

    var planPattern: SetPlanPattern {
        get { planPatternRaw.flatMap(SetPlanPattern.init(rawValue:)) ?? .fixed }
        set { planPatternRaw = newValue.rawValue }
    }

    var patternSource: PlanPatternSource {
        get { patternSourceRaw.flatMap(PlanPatternSource.init(rawValue:)) ?? .exerciseOverride }
        set { patternSourceRaw = newValue.rawValue }
    }

    var plannedSets: [WorkoutSetPlan] {
        get {
            WorkoutSetPlanCoding.decode(plannedSetsJSON)
                ?? WorkoutSetPlan.preset(
                    .fixed,
                    count: targetSets,
                    baseWeight: targetWeight,
                    baseReps: minReps
                )
        }
        set { plannedSetsJSON = WorkoutSetPlanCoding.encode(newValue) }
    }

    var feeling: WorkoutFeeling? {
        get { feelingRaw.flatMap(WorkoutFeeling.init(rawValue:)) }
        set { feelingRaw = newValue?.rawValue }
    }

    var volumeUnit: ExerciseVolumeUnit {
        get { volumeUnitRaw.flatMap(ExerciseVolumeUnit.init(rawValue:)) ?? .kilogram }
        set { volumeUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        exerciseID: UUID,
        exerciseName: String,
        order: Int,
        targetSets: Int,
        minReps: Int,
        maxReps: Int,
        targetWeight: Double,
        restSeconds: Int,
        muscleGroup: String = "",
        exerciseNotes: String = "",
        referenceURL: String = "",
        volumeUnit: ExerciseVolumeUnit = .kilogram,
        performanceNotes: String = "",
        plannedSets: [WorkoutSetPlan]? = nil,
        planPattern: SetPlanPattern = .fixed,
        feeling: WorkoutFeeling? = nil,
        patternSource: PlanPatternSource = .exerciseOverride,
        exerciseStartedAt: Date? = nil,
        exerciseCompletedAt: Date? = nil,
        bodyWeightKgSnapshot: Double? = nil,
        bodyWeightSnapshotSourceDate: Date? = nil,
        equipmentSnapshot: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        self.targetSets = targetSets
        self.minReps = minReps
        self.maxReps = maxReps
        self.targetWeight = targetWeight
        self.restSeconds = restSeconds
        self.muscleGroup = muscleGroup
        self.exerciseNotes = exerciseNotes
        self.referenceURL = referenceURL
        self.volumeUnitRaw = volumeUnit.rawValue
        self.performanceNotes = performanceNotes
        self.planPatternRaw = planPattern.rawValue
        self.patternSourceRaw = patternSource.rawValue
        self.plannedSetsJSON = WorkoutSetPlanCoding.encode(
            plannedSets ?? WorkoutSetPlan.preset(
                planPattern,
                count: targetSets,
                baseWeight: targetWeight,
                baseReps: minReps
            )
        )
        self.feelingRaw = feeling?.rawValue
        self.exerciseStartedAt = exerciseStartedAt
        self.exerciseCompletedAt = exerciseCompletedAt
        self.bodyWeightKgSnapshot = bodyWeightKgSnapshot
        self.bodyWeightSnapshotSourceDate = bodyWeightSnapshotSourceDate
        self.equipmentSnapshot = equipmentSnapshot
    }


    var durationSeconds: Int? {
        guard let exerciseStartedAt, let exerciseCompletedAt else { return nil }
        return max(0, Int(exerciseCompletedAt.timeIntervalSince(exerciseStartedAt).rounded()))
    }
}

@Model
final class SetLog {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var sessionExerciseID: UUID = UUID()
    var exerciseID: UUID = UUID()
    var setNumber: Int = 1
    var reductionOrder: Int?
    var targetWeight: Double = 0
    var targetReps: Int = 1
    var actualWeight: Double = 0
    var actualReps: Int = 0
    var rir: Int?
    var isWarmup: Bool = false
    var isCompleted: Bool = false
    /// Optional because fixed-timer and legacy records may not have an explicit set start.
    var startedAt: Date?
    var completedAt: Date?
    /// A completed set owns the rest interval that follows it.
    var restStartedAt: Date?
    var restEndedAt: Date?
    /// Authoritative value for history, manual correction, backup, and export.
    var restDurationSeconds: Int?
    var targetWeightSideRaw: String?
    var targetRepsSideRaw: String?
    var actualWeightSideRaw: String?
    var actualRepsSideRaw: String?
    var actualEntrySourceRaw: String?
    var sourceHistorySetID: UUID?
    /// Optional for migration; a blank load must stay blank when only reps/side are edited.
    var actualWeightIsBlank: Bool?
    var isActualWeightBlank: Bool { actualWeightIsBlank ?? (actualEntrySource == .blank) }

    var actualEntrySource: WorkoutActualEntrySource {
        get { actualEntrySourceRaw.flatMap(WorkoutActualEntrySource.init(rawValue:)) ?? .legacy }
        set { actualEntrySourceRaw = newValue.rawValue }
    }

    func markActualEntryEdited() {
        if actualWeightIsBlank == nil { actualWeightIsBlank = actualEntrySource == .blank }
        actualEntrySource = .manual
    }

    var targetWeightSide: MeasurementSide {
        get { targetWeightSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? .bilateral }
        set { targetWeightSideRaw = newValue.rawValue }
    }

    var targetRepsSide: MeasurementSide {
        get { targetRepsSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? .bilateral }
        set { targetRepsSideRaw = newValue.rawValue }
    }

    var actualWeightSide: MeasurementSide {
        get { actualWeightSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? targetWeightSide }
        set { actualWeightSideRaw = newValue.rawValue }
    }

    var actualRepsSide: MeasurementSide {
        get { actualRepsSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? targetRepsSide }
        set { actualRepsSideRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        sessionExerciseID: UUID,
        exerciseID: UUID,
        setNumber: Int,
        targetWeight: Double,
        targetReps: Int,
        actualWeight: Double,
        actualReps: Int,
        rir: Int? = nil,
        isWarmup: Bool = false,
        isCompleted: Bool = false,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        restStartedAt: Date? = nil,
        restEndedAt: Date? = nil,
        restDurationSeconds: Int? = nil,
        targetWeightSide: MeasurementSide = .bilateral,
        targetRepsSide: MeasurementSide = .bilateral,
        actualWeightSide: MeasurementSide? = nil,
        actualRepsSide: MeasurementSide? = nil,
        actualEntrySource: WorkoutActualEntrySource? = nil,
        sourceHistorySetID: UUID? = nil,
        actualWeightIsBlank: Bool? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sessionExerciseID = sessionExerciseID
        self.exerciseID = exerciseID
        self.setNumber = setNumber
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.actualWeight = actualWeight
        self.actualReps = actualReps
        self.rir = rir
        self.isWarmup = isWarmup
        self.isCompleted = isCompleted
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.restStartedAt = restStartedAt
        self.restEndedAt = restEndedAt
        self.restDurationSeconds = restDurationSeconds
        self.targetWeightSideRaw = targetWeightSide.rawValue
        self.targetRepsSideRaw = targetRepsSide.rawValue
        self.actualWeightSideRaw = (actualWeightSide ?? targetWeightSide).rawValue
        self.actualRepsSideRaw = (actualRepsSide ?? targetRepsSide).rawValue
        self.actualEntrySourceRaw = actualEntrySource?.rawValue
        self.sourceHistorySetID = sourceHistorySetID
        self.actualWeightIsBlank = actualWeightIsBlank ?? actualEntrySource.map { $0 == .blank }
    }
}
