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

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var muscleGroup: String
    var equipment: String
    var defaultRestSeconds: Int
    var createdAt: Date
    var isBuiltIn: Bool = true
    var isArchived: Bool = false
    var notes: String = ""
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: String,
        equipment: String,
        defaultRestSeconds: Int = 90,
        createdAt: Date = .now,
        isBuiltIn: Bool = true,
        isArchived: Bool = false,
        notes: String = ""
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
        self.updatedAt = createdAt
    }
}

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Calendar weekday: Sunday = 1, Monday = 2, ... Saturday = 7.
    var weekday: Int
    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        weekday: Int,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.weekday = weekday
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

@Model
final class TemplateExercise {
    @Attribute(.unique) var id: UUID
    var templateID: UUID
    var exerciseID: UUID
    var order: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var targetWeight: Double
    var restSeconds: Int

    init(
        id: UUID = UUID(),
        templateID: UUID,
        exerciseID: UUID,
        order: Int,
        targetSets: Int,
        minReps: Int,
        maxReps: Int,
        targetWeight: Double,
        restSeconds: Int
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
    }
}

@Model
final class ScheduledWorkout {
    @Attribute(.unique) var id: UUID
    var templateID: UUID
    var templateName: String
    var plannedDate: Date
    var statusRaw: String
    var createdAt: Date
    var originalPlannedDate: Date?
    var isManuallyScheduled: Bool = false
    var skipReason: String = ""
    var reminderDate: Date?
    var updatedAt: Date = Date.now

    var status: ScheduleStatus {
        get { ScheduleStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
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
        reminderDate: Date? = nil
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
    }
}

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var scheduledWorkoutID: UUID?
    var templateID: UUID?
    var templateName: String
    var plannedDate: Date
    var startedAt: Date
    var completedAt: Date?
    var statusRaw: String
    var notes: String
    var restEndDate: Date?

    var status: WorkoutSessionStatus {
        get { WorkoutSessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        scheduledWorkoutID: UUID? = nil,
        templateID: UUID? = nil,
        templateName: String,
        plannedDate: Date,
        startedAt: Date = .now,
        completedAt: Date? = nil,
        status: WorkoutSessionStatus = .inProgress,
        notes: String = "",
        restEndDate: Date? = nil
    ) {
        self.id = id
        self.scheduledWorkoutID = scheduledWorkoutID
        self.templateID = templateID
        self.templateName = templateName
        self.plannedDate = plannedDate.startOfDay
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.statusRaw = status.rawValue
        self.notes = notes
        self.restEndDate = restEndDate
    }
}

@Model
final class SessionExercise {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var exerciseID: UUID
    /// Snapshot fields protect history from later exercise/template edits.
    var exerciseName: String
    var order: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var targetWeight: Double
    var restSeconds: Int

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
        restSeconds: Int
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
    }
}

@Model
final class SetLog {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var sessionExerciseID: UUID
    var exerciseID: UUID
    var setNumber: Int
    var targetWeight: Double
    var targetReps: Int
    var actualWeight: Double
    var actualReps: Int
    var rir: Int?
    var isWarmup: Bool
    var isCompleted: Bool
    var completedAt: Date?

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
        completedAt: Date? = nil
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
        self.completedAt = completedAt
    }
}
