import Foundation
import SwiftData

/// Append-only sidecar records. No relationship or delete rule owns a workout or its sets.
@Model
final class TrainingCoachRecord {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var kind: String = ""
    var payloadJSON: String = ""
    var createdAt: Date = Date.now
    var sequence: Int64 = 0

    init(id: UUID = UUID(), sessionID: UUID, kind: String, payloadJSON: String, createdAt: Date = .now, sequence: Int64 = 0) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.sequence = sequence
    }
}

struct CoachFeedback: Codable, Equatable {
    var stage: String = "after"
    var pain: String = "unknown"
    var function: String = "unknown"
    var recovery: String = "unknown"
    var sleep: String = "unknown"
    var omission: String = "unknown"
    var note: String = ""
    /// Estimates explicitly reported later, never written back to SetLog.rir.
    var lastRIR: [String: Int] = [:]
    var quality: [String: String] = [:]
    var loadConventions: [String: String] = [:]
    var repsSides: [String: MeasurementSide] = [:]

    var supportsNormalDose: Bool {
        stage == "morning" && pain == "none" && function == "normal"
            && ["good", "ordinary"].contains(recovery)
    }
}

struct CoachActualSet: Codable, Equatable, Identifiable {
    var id: UUID
    var weight: Double?
    var reps: Int
    var rir: Int?
    var weightSide: MeasurementSide
    var repsSide: MeasurementSide
    var completed: Bool
    var warmup: Bool
}

struct CoachHistoricalPerformance: Codable, Equatable, Identifiable {
    var id: UUID
    var localDay: String
    var plannedSets: [WorkoutSetPlan]
    var actual: [CoachActualSet]
    var supplementaryLastRIR: Int?
}

struct CoachObservation: Codable, Equatable, Identifiable {
    var id: UUID
    var exerciseID: UUID
    var name: String
    var muscleGroup: String
    var equipment: String
    var unit: ExerciseVolumeUnit
    var notes: String
    var plannedSets: [WorkoutSetPlan]
    var actual: [CoachActualSet]
    var loadGuidance: String
    var isTechnical: Bool
    var previous: [CoachHistoricalPerformance] = []
    var performanceNotes: String = ""
    var feelingRaw: String? = nil
    var historicalClassificationUnknown: Bool? = nil
    var working: [CoachActualSet] { actual.filter { $0.completed && !$0.warmup } }
}

struct CoachPlanItem: Codable, Equatable, Identifiable {
    var id: UUID { exercise.catalogExerciseID }
    var exercise: ConfirmedDailyPlanExercise
    var reason: String
    var warmup: String
    var adjustment: String
    var unitVerified: Bool
    var technical: Bool
    var minimumSets: Int = 3
    var exceptionReason: String = ""
}

struct CoachDraft: Codable, Equatable, Identifiable {
    var id: UUID
    var sessionID: UUID
    var revision: Int
    var sourceFingerprint: String
    var preferenceCode: String
    var localDay: String?
    var title: String
    var items: [CoachPlanItem]
    var coverage: [String]
    var method: String = "APP-COACH-1"
    var changeReason: String = ""
}

struct CoachConfirmation: Codable, Equatable, Identifiable {
    var id: UUID
    var draft: CoachDraft
    var preview: ConfirmedDailyTrainingPlanPreview
}

struct CoachSavedReceipt: Codable, Equatable {
    var confirmationID: UUID
    var scheduleID: UUID
    var packetSHA256: String
}

struct CoachReview {
    var sessionID: UUID
    var name: String
    var localDay: String
    var observations: [CoachObservation]
    var records: [TrainingCoachRecord]
    var after: CoachFeedback
    var morning: CoachFeedback
    var preferenceCode: String
    var sourceFingerprint: String
    var coverage: [String]
    var existingRecovery: [String] = []
    var completed: Int { observations.reduce(0) { $0 + $1.working.count } }
    var total: Int { observations.reduce(0) { $0 + $1.actual.filter { !$0.warmup }.count } }
    var technicalCount: Int { observations.filter(\.isTechnical).reduce(0) { $0 + $1.working.count } }
}

enum TrainingCoachError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
