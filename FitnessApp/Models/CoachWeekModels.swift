import Foundation

enum CoachWeekDayKind: String, Codable, CaseIterable {
    case strength, cardio, rest, preserved, missing
    var title: String {
        switch self {
        case .strength: return "力量"
        case .cardio: return "有氧"
        case .rest: return "休息"
        case .preserved: return "保留已有安排"
        case .missing: return "待补"
        }
    }
}

struct CoachWeekGoal: Codable, Equatable, Identifiable {
    var id: String { localDay }
    var localDay: String
    var kind: CoachWeekDayKind
    var focus: String
    var reason: String
}

struct CoachWeekException: Codable, Equatable, Identifiable {
    let id: UUID
    let startDay: String
    let endDay: String
    let reason: String
    let goals: [CoachWeekGoal]
    let confirmation: String
}

struct CoachWeekCoreException: Codable, Equatable {
    let startDay: String
    let endDay: String
    let reason: String
    let confirmation: String
    let goals: [CoachWeekGoal]
}

struct CoachWeekCatalogItem: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let muscle: String
    let equipment: String
    let unit: ExerciseVolumeUnit
    let approvedCanonicalID: String?
    let approvedName: String?
    let archived: Bool
    let roles: [String]
    let roleSource: String
    var machineIdentity: String? = nil
    var machineSettings: String? = nil
}

struct CoachWeekActual: Codable, Equatable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let localDay: String
    let exerciseID: UUID
    let name: String
    let equipment: String?
    let unit: ExerciseVolumeUnit
    let plannedSets: [WorkoutSetPlan]
    let actual: [CoachActualSet]
    let feedback: String
    var loadConvention: String? = nil
    var feelingRaw: String? = nil
    var supplementaryLastRIR: Int? = nil
    var classificationKnown: Bool? = nil
    var scheduledWorkoutID: UUID? = nil
    var machineIdentity: String? = nil
    var machineSettings: String? = nil
    var supplementaryLastSetID: UUID? = nil
    var actualSetNumbers: [Int]? = nil
}

struct CoachWeekExisting: Codable, Equatable, Identifiable {
    let id: UUID
    let localDay: String
    let title: String
    let status: String
    let source: String
    var contentDigest: String? = nil
    var confirmedPacketDigest: String? = nil
    var actualBaselineJSON: String? = nil
    var exerciseIDs: [UUID]? = nil
    var knownCardio: Bool? = nil
    var cardioMode: String? = nil
    var frozenExercises: [CoachWeekFrozenExercise]? = nil
}

struct CoachWeekPreference: Codable, Equatable, Identifiable {
    var id: String { localDay }
    let localDay: String
    let revisionID: UUID?
    let code: String?
    let snapshot: TrainingPreferenceSnapshot?
}

struct CoachWeekInput: Codable, Equatable {
    let startDay: String
    let timeZone: String
    let methodVersion: String
    let personalRuleVersion: String
    let preferences: [CoachWeekPreference]
    let exception: CoachWeekException?
    let catalog: [CoachWeekCatalogItem]
    let history: [CoachWeekActual]
    let existing: [CoachWeekExisting]
    let recovery: [String]
    let unknowns: [String]
    var sourceRuleVersions: [String]? = nil
    var supportedFromDay: String? = nil
    var recoverySignals: [CoachWeekRecoverySignal]? = nil
    var bodyReports: [CoachWeekBodyReport]? = nil
    var retainedReviews: [CoachWeekRetainedReview]? = nil
    var coreException: CoachWeekCoreException? = nil
    // Local day of input capture; nil in historical inputs. Used to distinguish future plans from stale plans.
    var capturedLocalDay: String? = nil
}

struct CoachWeekDropSegment: Codable, Equatable {
    var fourthSetID: UUID
    var instruction: String
    var estimatedSeconds: Int
}

struct CoachWeekMovement: Codable, Equatable, Identifiable {
    var id: UUID { exercise.catalogExerciseID }
    var exercise: ConfirmedDailyPlanExercise
    var roles: [String]
    var roleSource: String
    var reason: String
    var evidence: [String]
    var unknowns: [String]
    var unilateral: Bool
    var loadRole: String? = nil
    var plannedDrop: CoachWeekDropSegment? = nil
    var specialPrescriptionReviewed: Bool? = nil
}

struct CoachZone2Plan: Codable, Equatable {
    var mode: String
    var durationSeconds: Int
    var guidance: String
    var exerciseID: UUID? = nil
}

struct CoachWeekDay: Codable, Equatable, Identifiable {
    var id: String { localDay }
    var localDay: String
    var kind: CoachWeekDayKind
    var title: String
    var focus: String
    var movements: [CoachWeekMovement]
    var cardio: JumpRopeMenuPlan?
    var estimatedSeconds: Int?
    var rationale: [String]
    var blockers: [String]
    var existing: [CoachWeekExisting]
    var zone2: CoachZone2Plan? = nil
    var pastRestReview: CoachWeekPastRestReview? = nil
}

struct CoachWeekPastRestReview: Codable, Equatable {
    let localDay: String
    let reason: String
    let confirmation: String
}

struct CoachWeekEdit: Codable, Equatable, Identifiable {
    let id: UUID
    let day: String
    let field: String
    let before: String
    let after: String
    let reason: String
}

struct CoachWeekRuleCandidate: Codable, Equatable, Identifiable {
    let id: UUID
    let originalRule: String
    let proposedChange: String
    let evidence: [String]
    let unknowns: [String]
    let replayResult: String
    let status: String
    var executableVersion: String? = nil
    var replayFingerprint: String? = nil
    var replaySourceDraftID: UUID? = nil
    var replayEditIDs: [UUID]? = nil
    var outcome: CoachWeekOutcome? = nil
}

struct CoachWeekDraft: Codable, Equatable, Identifiable {
    let id: UUID
    let rootID: UUID
    let revision: Int
    let createdAt: Date
    let sourceFingerprint: String
    let input: CoachWeekInput
    let days: [CoachWeekDay]
    let edits: [CoachWeekEdit]
    let ruleCandidates: [CoachWeekRuleCandidate]
    var weeklyShortfall: [String]? = nil
    var parentDraftID: UUID? = nil
}

struct CoachWeekRopeMember: Codable, Equatable {
    var id: UUID
    var localDay: String
    var plan: JumpRopeMenuPlan
}

struct CoachWeekConfirmation: Codable, Equatable, Identifiable {
    var id: UUID
    var draft: CoachWeekDraft
    var confirmedAt: Date
    var members: [ConfirmedDailyTrainingPlanPreview]
    var ropes: [CoachWeekRopeMember]
    var dayDigests: [String: String]
    var requestDigest: String
}

struct CoachWeekFrozenExercise: Codable, Equatable {
    let exerciseID: UUID
    let name: String
    let muscle: String
    let equipment: String
    let roles: [String]
    let plannedSets: [WorkoutSetPlan]
}

struct CoachWeekRopeActual: Codable, Equatable {
    let id: UUID
    let scheduleID: UUID
    let date: Date
    let count: Int?
    let activeSeconds: Int?
    let elapsedSeconds: Int?
    let legacySeconds: Int?
}

struct CoachWeekOutcome: Codable, Equatable {
    let draftID: UUID
    let capturedAt: Date
    let sessionIDs: [UUID]
    let actual: [CoachWeekActual]
    let recovery: [String]
    let unknowns: [String]
    var ropeActual: [CoachWeekRopeActual] = []
    var scheduleIDs: [UUID] = []
    var rootID: UUID? = nil
    var sourceFingerprint: String? = nil
    var provenance: [String] = []
}

struct CoachWeekRuleActivation: Codable, Equatable {
    let id: UUID
    let version: String
    let previousVersion: String
    let candidateID: UUID?
    let sourceDraftID: UUID?
    let replayFingerprint: String?
    let createdAt: Date
    var rollbackOfActivationID: UUID? = nil
}

struct CoachWeekRecoverySignal: Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let trainingDay: String
    let capturedAt: Date
    let feedback: CoachFeedback
    var sequence: Int64? = nil
}

struct CoachWeekBodyReport: Codable, Equatable {
    let id: UUID
    let localDay: String
    let capturedAt: Date
    let note: String
    let hasBodyMarkers: Bool
}

struct CoachWeekRetainedReview: Codable, Equatable, Identifiable {
    let id: UUID
    let existingID: UUID
    let localDay: String
    let sourceDigest: String
    let kind: CoachWeekDayKind
    let focus: String
    let reason: String
    let confirmedAt: Date
}
