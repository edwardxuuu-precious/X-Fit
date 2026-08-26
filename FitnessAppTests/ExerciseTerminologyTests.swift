import Foundation
import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class ExerciseTerminologyTests: XCTestCase {
    func testCatalogCoversAuditedRawNamesWithoutCollisions() {
        let rawNames = ExerciseTerminologyService.catalog.flatMap(\.rawNames)
        XCTAssertEqual(rawNames.count, 55)
        XCTAssertEqual(Set(rawNames).count, 55)
        XCTAssertEqual(Set(ExerciseTerminologyService.catalog.map(\.canonicalID)).count, 49)
        XCTAssertEqual(
            ExerciseTerminologyService.candidate(for: "坐姿肩推")?.canonicalID,
            "seated_dumbbell_shoulder_press"
        )
    }

    func testCatalogEntriesHaveStableCanonicalAndCompleteBilingualFields() throws {
        let canonicalPattern = try NSRegularExpression(pattern: "^[a-z0-9]+(?:_[a-z0-9]+)*$")
        let mergeGroups = Dictionary(
            grouping: ExerciseTerminologyService.catalog.compactMap { candidate in
                candidate.mergeGroup.map { ($0, candidate) }
            },
            by: { $0.0 }
        )

        for candidate in ExerciseTerminologyService.catalog {
            let range = NSRange(candidate.canonicalID.startIndex..., in: candidate.canonicalID)
            XCTAssertNotNil(
                canonicalPattern.firstMatch(in: candidate.canonicalID, range: range),
                "canonical ID 必须稳定且机器可读：\(candidate.canonicalID)"
            )
            XCTAssertFalse(candidate.standardNameZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(candidate.standardNameEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(candidate.rawNames.isEmpty)
            XCTAssertTrue(candidate.rawNames.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        }

        XCTAssertEqual(mergeGroups.count, 5)
        for (group, members) in mergeGroups {
            XCTAssertEqual(members.count, 1, "一个 merge group 应由单个多别名候选定义：\(group)")
            XCTAssertEqual(members[0].1.rawNames.count, 2)
            XCTAssertEqual(members[0].1.reviewStatus, .mergeReview)
        }
    }

    func testCandidateLookupNormalizesWhitespaceWidthAndEnglishCase() {
        XCTAssertEqual(
            ExerciseTerminologyService.candidate(for: "  杠铃卧推  ")?.canonicalID,
            "barbell_bench_press"
        )
        XCTAssertEqual(
            ExerciseTerminologyService.candidate(for: "cAbLe TrIcEpS PuShDoWn")?.canonicalID,
            "cable_triceps_pushdown"
        )
        XCTAssertEqual(
            ExerciseTerminologyService.candidate(for: "ＭＴＳ 下斜卧推")?.canonicalID,
            "hammer_strength_mts_iso_lateral_decline_press"
        )
    }

    func testStagingIsIdempotentAndDoesNotRenameRawExercise() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        context.insert(exercise)
        try context.save()

        try ExerciseTerminologyService.stageCatalogCandidates(in: context)
        let firstCanonical = exercise.terminologyCanonicalID
        let firstVersion = exercise.terminologyCatalogVersion
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)

        XCTAssertEqual(exercise.name, "杠铃卧推")
        XCTAssertEqual(firstCanonical, "barbell_bench_press")
        XCTAssertEqual(exercise.terminologyCanonicalID, firstCanonical)
        XCTAssertEqual(exercise.terminologyCatalogVersion, firstVersion)
        XCTAssertEqual(exercise.terminologyDecision, .pending)
        XCTAssertNil(exercise.approvedCanonicalID)
    }

    func testAcceptingMergeCandidateReviewsBothWithoutChangingIDsOrNames() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldName = Exercise(name: "三头下压", muscleGroup: "手臂", equipment: "龙门架", isBuiltIn: false)
        let seedName = Exercise(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架")
        context.insert(oldName)
        context.insert(seedName)
        try context.save()
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)

        let originalIDs = Set([oldName.id, seedName.id])
        try ExerciseTerminologyService.accept(oldName, among: [oldName, seedName], in: context)

        XCTAssertEqual(Set([oldName.id, seedName.id]), originalIDs)
        XCTAssertEqual(oldName.name, "三头下压")
        XCTAssertEqual(seedName.name, "绳索下压")
        XCTAssertEqual(oldName.terminologyDecision, .accepted)
        XCTAssertEqual(seedName.terminologyDecision, .accepted)
        XCTAssertEqual(oldName.approvedCanonicalID, "cable_triceps_pushdown")
        XCTAssertEqual(seedName.approvedCanonicalID, "cable_triceps_pushdown")
    }

    func testRejectAndResetApplyToMergeGroupWithoutTouchingUnrelatedExercise() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = Exercise(name: "三头下压", muscleGroup: "手臂", equipment: "龙门架")
        let second = Exercise(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架")
        let unrelated = Exercise(
            name: "自定义下压",
            muscleGroup: "手臂",
            equipment: "龙门架",
            terminologyCanonicalID: "cable_triceps_pushdown",
            terminologyStandardNameZH: "自定义下压",
            terminologyStandardNameEN: "Custom Pushdown",
            terminologyReviewStatus: .approvalReady,
            terminologyDecision: .accepted,
            terminologyConfidence: .high
        )
        [first, second, unrelated].forEach(context.insert)
        try context.save()
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)

        try ExerciseTerminologyService.reject(first, among: [first, second, unrelated], in: context)
        XCTAssertEqual(first.terminologyDecision, .rejected)
        XCTAssertEqual(second.terminologyDecision, .rejected)
        XCTAssertEqual(unrelated.terminologyDecision, .accepted)
        XCTAssertNotNil(first.terminologyReviewedAt)
        XCTAssertNotNil(second.terminologyReviewedAt)

        try ExerciseTerminologyService.reset(second, among: [first, second, unrelated], in: context)
        XCTAssertEqual(first.terminologyDecision, .pending)
        XCTAssertEqual(second.terminologyDecision, .pending)
        XCTAssertNil(first.terminologyReviewedAt)
        XCTAssertNil(second.terminologyReviewedAt)
        XCTAssertEqual(unrelated.terminologyDecision, .accepted)
    }

    func testInvalidMergeCandidateFailsAtomically() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = Exercise(name: "三头下压", muscleGroup: "手臂", equipment: "龙门架")
        let second = Exercise(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架")
        context.insert(first)
        context.insert(second)
        try context.save()
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)
        second.terminologyStandardNameEN = nil

        XCTAssertThrowsError(
            try ExerciseTerminologyService.accept(first, among: [first, second], in: context)
        ) { error in
            XCTAssertEqual(error as? ExerciseTerminologyAPIError, .invalidCandidate)
        }
        XCTAssertEqual(first.terminologyDecision, .pending)
        XCTAssertEqual(second.terminologyDecision, .pending)
        XCTAssertNil(first.terminologyReviewedAt)
        XCTAssertNil(second.terminologyReviewedAt)
    }

    func testInconsistentMergeGroupIsRejectedBeforeAnyDecisionChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = Exercise(name: "三头下压", muscleGroup: "手臂", equipment: "龙门架")
        let second = Exercise(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架")
        context.insert(first)
        context.insert(second)
        try context.save()
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)

        second.terminologyCanonicalID = "different_canonical_identity"
        second.equipment = "固定器械"

        XCTAssertThrowsError(
            try ExerciseTerminologyService.accept(first, among: [first, second], in: context)
        ) { error in
            XCTAssertEqual(error as? ExerciseTerminologyAPIError, .inconsistentMergeGroup)
        }
        XCTAssertEqual(first.terminologyDecision, .pending)
        XCTAssertEqual(second.terminologyDecision, .pending)
        XCTAssertNil(first.terminologyReviewedAt)
        XCTAssertNil(second.terminologyReviewedAt)
    }

    func testDecisionSaveFailureRollsBackEveryMergePeer() throws {
        enum SimulatedFailure: Error { case save }

        let container = try makeContainer()
        let context = container.mainContext
        let first = Exercise(name: "三头下压", muscleGroup: "手臂", equipment: "龙门架")
        let second = Exercise(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架")
        context.insert(first)
        context.insert(second)
        try context.save()
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)

        XCTAssertThrowsError(
            try ExerciseTerminologyService.accept(
                first,
                among: [first, second],
                in: context,
                save: { _ in throw SimulatedFailure.save }
            )
        ) { error in
            XCTAssertTrue(error is SimulatedFailure)
        }

        let persisted = try context.fetch(FetchDescriptor<Exercise>())
            .filter { ["三头下压", "绳索下压"].contains($0.name) }
        XCTAssertEqual(persisted.count, 2)
        XCTAssertTrue(persisted.allSatisfy { $0.terminologyDecision == .pending })
        XCTAssertTrue(persisted.allSatisfy { $0.terminologyReviewedAt == nil })
    }

    func testUnresolvedCandidateCannotBeAcceptedAndDoesNotMutateRawIdentity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "传统硬拉", muscleGroup: "腿部", equipment: "自重")
        context.insert(exercise)
        try context.save()
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)

        XCTAssertEqual(exercise.terminologyReviewStatus, .unresolved)
        XCTAssertEqual(exercise.terminologyConfidence, .low)
        XCTAssertNil(exercise.terminologyCanonicalID)
        XCTAssertEqual(exercise.terminologyStandardNameZH, "传统硬拉")
        XCTAssertEqual(exercise.terminologyStandardNameEN, "")
        XCTAssertThrowsError(
            try ExerciseTerminologyService.accept(exercise, among: [exercise], in: context)
        ) { error in
            XCTAssertEqual(error as? ExerciseTerminologyAPIError, .invalidCandidate)
        }
        XCTAssertEqual(exercise.name, "传统硬拉")
        XCTAssertEqual(exercise.terminologyDecision, .pending)
        XCTAssertNil(exercise.terminologyReviewedAt)
    }

    func testReviewedDecisionIsStickyAcrossCatalogRestaging() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let accepted = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        let rejected = Exercise(name: "高位下拉", muscleGroup: "背部", equipment: "器械")
        context.insert(accepted)
        context.insert(rejected)
        try context.save()
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)
        try ExerciseTerminologyService.accept(accepted, among: [accepted, rejected], in: context)
        try ExerciseTerminologyService.reject(rejected, among: [accepted, rejected], in: context)
        let acceptedDate = accepted.terminologyReviewedAt
        let rejectedDate = rejected.terminologyReviewedAt

        try ExerciseTerminologyService.stageCatalogCandidates(in: context)

        XCTAssertEqual(accepted.terminologyDecision, .accepted)
        XCTAssertEqual(rejected.terminologyDecision, .rejected)
        XCTAssertEqual(accepted.terminologyReviewedAt, acceptedDate)
        XCTAssertEqual(rejected.terminologyReviewedAt, rejectedDate)
        XCTAssertEqual(accepted.approvedCanonicalID, "barbell_bench_press")
        XCTAssertNil(rejected.approvedCanonicalID)
    }

    func testApprovedCanonicalIdentityCombinesTrendsButPreservesSnapshotNames() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let firstExercise = Exercise(
            name: "三头下压",
            muscleGroup: "手臂",
            equipment: "龙门架",
            terminologyCanonicalID: "cable_triceps_pushdown",
            terminologyStandardNameZH: "绳索三头肌下压",
            terminologyStandardNameEN: "Cable Triceps Pushdown",
            terminologyReviewStatus: .mergeReview,
            terminologyDecision: .accepted,
            terminologyConfidence: .high
        )
        let secondExercise = Exercise(
            name: "绳索下压",
            muscleGroup: "手臂",
            equipment: "龙门架",
            terminologyCanonicalID: "cable_triceps_pushdown",
            terminologyStandardNameZH: "绳索三头肌下压",
            terminologyStandardNameEN: "Cable Triceps Pushdown",
            terminologyReviewStatus: .mergeReview,
            terminologyDecision: .accepted,
            terminologyConfidence: .high
        )
        let firstSession = WorkoutSession(templateName: "推", plannedDate: date, startedAt: date, status: .completed)
        let secondSession = WorkoutSession(templateName: "推", plannedDate: date.addingTimeInterval(86_400), startedAt: date.addingTimeInterval(86_400), status: .completed)
        let firstSnapshot = SessionExercise(sessionID: firstSession.id, exerciseID: firstExercise.id, exerciseName: "三头下压", order: 0, targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 20, restSeconds: 60)
        let secondSnapshot = SessionExercise(sessionID: secondSession.id, exerciseID: secondExercise.id, exerciseName: "绳索下压", order: 0, targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 20, restSeconds: 60)
        let logs = [
            completedLog(session: firstSession, snapshot: firstSnapshot, exercise: firstExercise),
            completedLog(session: secondSession, snapshot: secondSnapshot, exercise: secondExercise)
        ]

        let result = TrainingMetrics.volumeTrends(
            sessions: [firstSession, secondSession],
            sessionExercises: [firstSnapshot, secondSnapshot],
            exercises: [firstExercise, secondExercise],
            setLogs: logs
        )

        XCTAssertEqual(firstSnapshot.exerciseName, "三头下压")
        XCTAssertEqual(secondSnapshot.exerciseName, "绳索下压")
        XCTAssertEqual(result.exercises.count, 1)
        XCTAssertEqual(result.exercises.first?.name, "绳索三头肌下压")
        XCTAssertEqual(result.exercises.first?.completedSets, 2)
    }

    func testConfirmedStrictSquatAliasUsesOneHistoricalTrend() {
        XCTAssertEqual(
            TrainingMetrics.exerciseHistoryKey(for: "严格深蹲"),
            TrainingMetrics.exerciseHistoryKey(for: "深蹲")
        )
    }

    func testPendingAndRejectedCanonicalCandidatesDoNotMergeTrends() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let pending = Exercise(
            name: "三头下压",
            muscleGroup: "手臂",
            equipment: "龙门架",
            terminologyCanonicalID: "cable_triceps_pushdown",
            terminologyStandardNameZH: "绳索三头肌下压",
            terminologyStandardNameEN: "Cable Triceps Pushdown",
            terminologyReviewStatus: .mergeReview,
            terminologyDecision: .pending,
            terminologyConfidence: .high
        )
        let rejected = Exercise(
            name: "绳索下压",
            muscleGroup: "手臂",
            equipment: "龙门架",
            terminologyCanonicalID: "cable_triceps_pushdown",
            terminologyStandardNameZH: "绳索三头肌下压",
            terminologyStandardNameEN: "Cable Triceps Pushdown",
            terminologyReviewStatus: .mergeReview,
            terminologyDecision: .rejected,
            terminologyConfidence: .high
        )
        let firstSession = WorkoutSession(templateName: "推", plannedDate: date, startedAt: date, status: .completed)
        let secondSession = WorkoutSession(templateName: "推", plannedDate: date.addingDays(1), startedAt: date.addingDays(1), status: .completed)
        let firstSnapshot = SessionExercise(sessionID: firstSession.id, exerciseID: pending.id, exerciseName: pending.name, order: 0, targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 20, restSeconds: 60)
        let secondSnapshot = SessionExercise(sessionID: secondSession.id, exerciseID: rejected.id, exerciseName: rejected.name, order: 0, targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 20, restSeconds: 60)

        let result = TrainingMetrics.volumeTrends(
            sessions: [firstSession, secondSession],
            sessionExercises: [firstSnapshot, secondSnapshot],
            exercises: [pending, rejected],
            setLogs: [
                completedLog(session: firstSession, snapshot: firstSnapshot, exercise: pending),
                completedLog(session: secondSession, snapshot: secondSnapshot, exercise: rejected)
            ]
        )

        XCTAssertEqual(result.exercises.count, 2)
        XCTAssertEqual(Set(result.exercises.map(\.name)), Set(["三头下压", "绳索下压"]))
    }

    func testApprovedCanonicalTrendStillSeparatesIncompatibleVolumeUnits() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let kilogram = Exercise(
            name: "三头下压",
            muscleGroup: "手臂",
            equipment: "龙门架",
            volumeUnit: .kilogram,
            terminologyCanonicalID: "cable_triceps_pushdown",
            terminologyStandardNameZH: "绳索三头肌下压",
            terminologyStandardNameEN: "Cable Triceps Pushdown",
            terminologyReviewStatus: .mergeReview,
            terminologyDecision: .accepted,
            terminologyConfidence: .high
        )
        let count = Exercise(
            name: "绳索下压",
            muscleGroup: "手臂",
            equipment: "龙门架",
            volumeUnit: .count,
            terminologyCanonicalID: "cable_triceps_pushdown",
            terminologyStandardNameZH: "绳索三头肌下压",
            terminologyStandardNameEN: "Cable Triceps Pushdown",
            terminologyReviewStatus: .mergeReview,
            terminologyDecision: .accepted,
            terminologyConfidence: .high
        )
        let firstSession = WorkoutSession(templateName: "推", plannedDate: date, startedAt: date, status: .completed)
        let secondSession = WorkoutSession(templateName: "推", plannedDate: date.addingDays(1), startedAt: date.addingDays(1), status: .completed)
        let firstSnapshot = SessionExercise(sessionID: firstSession.id, exerciseID: kilogram.id, exerciseName: kilogram.name, order: 0, targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 20, restSeconds: 60, volumeUnit: .kilogram)
        let secondSnapshot = SessionExercise(sessionID: secondSession.id, exerciseID: count.id, exerciseName: count.name, order: 0, targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 0, restSeconds: 60, volumeUnit: .count)

        let result = TrainingMetrics.volumeTrends(
            sessions: [firstSession, secondSession],
            sessionExercises: [firstSnapshot, secondSnapshot],
            exercises: [kilogram, count],
            setLogs: [
                completedLog(session: firstSession, snapshot: firstSnapshot, exercise: kilogram),
                completedLog(session: secondSession, snapshot: secondSnapshot, exercise: count)
            ]
        )

        XCTAssertEqual(result.exercises.count, 2)
        XCTAssertEqual(Set(result.exercises.map(\.unit)), Set([.kilogram, .count]))
    }

    func testCatalogRejectsSameNameWithDifferentEquipment() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = Exercise(name: "坐姿推举", muscleGroup: "肩部", equipment: "哑铃")
        context.insert(existing)
        try context.save()

        XCTAssertThrowsError(
            try ExerciseCatalogService.save(
                exercise: nil,
                name: "坐姿推举",
                muscleGroup: "肩部",
                equipment: "杠铃",
                defaultRestSeconds: 90,
                notes: "",
                referenceURL: "",
                allExercises: [existing],
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? ExerciseCatalogError, .conflictingIdentity)
        }
    }

    func testRemoteAPIContractRequiresHTTPSAndNeverAddsProviderKey() throws {
        let input = ExerciseTerminologyCheckInput(
            rawName: "火箭推",
            muscleGroup: "肩部",
            equipment: "杠铃",
            locale: "zh-Hans"
        )
        XCTAssertThrowsError(
            try ExerciseTerminologyAPIClient.makeRequest(
                endpoint: URL(string: "http://example.com/check")!,
                input: input
            )
        ) { error in
            XCTAssertEqual(error as? ExerciseTerminologyAPIError, .insecureEndpoint)
        }

        let request = try ExerciseTerminologyAPIClient.makeRequest(
            endpoint: URL(string: "https://example.com/xfit/check")!,
            input: input
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-XFit-Contract"), "x-fit-exercise-terminology-v1")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["providerPreference"] as? String, "deepseek")
        XCTAssertNil(object["apiKey"])
    }

    func testRemoteAPIResponseValidationRejectsSchemaEnumAndIncompleteCandidates() throws {
        let valid = ExerciseTerminologyCheckResponse(
            schemaVersion: 1,
            canonicalID: "barbell_bench_press",
            standardNameZH: "杠铃平板卧推",
            standardNameEN: "Barbell Bench Press",
            reviewStatusRaw: ExerciseTerminologyReviewStatus.approvalReady.rawValue,
            confidenceRaw: ExerciseTerminologyConfidence.high.rawValue,
            ambiguity: "",
            evidenceLabels: ["local-catalog"]
        )
        XCTAssertNoThrow(try ExerciseTerminologyAPIClient.validate(valid))

        let unresolved = ExerciseTerminologyCheckResponse(
            schemaVersion: 1,
            canonicalID: nil,
            standardNameZH: nil,
            standardNameEN: nil,
            reviewStatusRaw: ExerciseTerminologyReviewStatus.unresolved.rawValue,
            confidenceRaw: ExerciseTerminologyConfidence.low.rawValue,
            ambiguity: "需要器械照片",
            evidenceLabels: []
        )
        XCTAssertNoThrow(try ExerciseTerminologyAPIClient.validate(unresolved))

        let wrongSchema = ExerciseTerminologyCheckResponse(
            schemaVersion: 2,
            canonicalID: valid.canonicalID,
            standardNameZH: valid.standardNameZH,
            standardNameEN: valid.standardNameEN,
            reviewStatusRaw: valid.reviewStatusRaw,
            confidenceRaw: valid.confidenceRaw,
            ambiguity: valid.ambiguity,
            evidenceLabels: valid.evidenceLabels
        )
        XCTAssertThrowsError(try ExerciseTerminologyAPIClient.validate(wrongSchema)) { error in
            XCTAssertEqual(error as? ExerciseTerminologyAPIError, .unsupportedSchema)
        }

        let invalidEnum = ExerciseTerminologyCheckResponse(
            schemaVersion: 1,
            canonicalID: valid.canonicalID,
            standardNameZH: valid.standardNameZH,
            standardNameEN: valid.standardNameEN,
            reviewStatusRaw: "autoApproved",
            confidenceRaw: valid.confidenceRaw,
            ambiguity: "",
            evidenceLabels: []
        )
        XCTAssertThrowsError(try ExerciseTerminologyAPIClient.validate(invalidEnum)) { error in
            XCTAssertEqual(error as? ExerciseTerminologyAPIError, .invalidCandidate)
        }

        let missingEnglish = ExerciseTerminologyCheckResponse(
            schemaVersion: 1,
            canonicalID: valid.canonicalID,
            standardNameZH: valid.standardNameZH,
            standardNameEN: "  ",
            reviewStatusRaw: valid.reviewStatusRaw,
            confidenceRaw: valid.confidenceRaw,
            ambiguity: "",
            evidenceLabels: []
        )
        XCTAssertThrowsError(try ExerciseTerminologyAPIClient.validate(missingEnglish)) { error in
            XCTAssertEqual(error as? ExerciseTerminologyAPIError, .invalidCandidate)
        }
    }

    func testCatalogConflictGuardCoversMuscleEquipmentAndUnitButAllowsFormattingDifferences() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = Exercise(
            name: "杠铃卧推",
            muscleGroup: "胸部",
            equipment: "杠铃",
            volumeUnit: .kilogram
        )
        context.insert(existing)
        try context.save()

        let conflicts: [(String, String, ExerciseVolumeUnit)] = [
            ("肩部", "杠铃", .kilogram),
            ("胸部", "史密斯机", .kilogram),
            ("胸部", "杠铃", .count)
        ]
        for (muscleGroup, equipment, unit) in conflicts {
            XCTAssertThrowsError(
                try ExerciseCatalogService.save(
                    exercise: nil,
                    name: "杠铃卧推",
                    muscleGroup: muscleGroup,
                    equipment: equipment,
                    volumeUnit: unit,
                    defaultRestSeconds: 90,
                    notes: "",
                    referenceURL: "",
                    allExercises: [existing],
                    in: context
                )
            ) { error in
                XCTAssertEqual(error as? ExerciseCatalogError, .conflictingIdentity)
            }
        }

        let reused = try ExerciseCatalogService.save(
            exercise: nil,
            name: "  杠铃卧推  ",
            muscleGroup: " 胸部 ",
            equipment: " 杠铃 ",
            volumeUnit: .kilogram,
            defaultRestSeconds: 90,
            notes: "",
            referenceURL: "",
            allExercises: [existing],
            in: context
        )
        XCTAssertEqual(reused.kind, .reused)
        XCTAssertEqual(reused.exercise.id, existing.id)
    }

    func testCatalogSearchUsesChineseEnglishAndCanonicalCandidateFields() throws {
        let exercise = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        XCTAssertTrue(ExerciseTerminologyService.stageCandidate(for: exercise))

        for query in ["杠铃平板卧推", "Barbell Bench Press", "barbell_bench_press"] {
            XCTAssertEqual(ExerciseCatalogService.search([exercise], query: query).first?.id, exercise.id)
        }
    }

    func testBackupRoundTripPreservesTerminologyDecision() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let exercise = Exercise(
            name: "杠铃卧推",
            muscleGroup: "胸部",
            equipment: "杠铃",
            terminologyCanonicalID: "barbell_bench_press",
            terminologyStandardNameZH: "杠铃平板卧推",
            terminologyStandardNameEN: "Barbell Bench Press",
            terminologyReviewStatus: .approvalReady,
            terminologyDecision: .accepted,
            terminologyConfidence: .high,
            terminologyMergeGroup: "review_group",
            terminologyReviewNote: "人工核对器械铭牌",
            terminologyCatalogVersion: ExerciseTerminologyService.catalogVersion,
            terminologyReviewedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        sourceContext.insert(exercise)
        try sourceContext.save()
        let url = try DataExportService.createBackup(in: sourceContext)
        let data = try Data(contentsOf: url)

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let imported = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<Exercise>()).first)

        XCTAssertEqual(imported.name, "杠铃卧推")
        XCTAssertEqual(imported.terminologyDecision, .accepted)
        XCTAssertEqual(imported.approvedCanonicalID, "barbell_bench_press")
        XCTAssertEqual(imported.approvedStandardNameZH, "杠铃平板卧推")
        XCTAssertEqual(imported.terminologyStandardNameEN, "Barbell Bench Press")
        XCTAssertEqual(imported.terminologyReviewStatus, .approvalReady)
        XCTAssertEqual(imported.terminologyConfidence, .high)
        XCTAssertEqual(imported.terminologyMergeGroup, "review_group")
        XCTAssertEqual(imported.terminologyReviewNote, "人工核对器械铭牌")
        XCTAssertEqual(imported.terminologyCatalogVersion, ExerciseTerminologyService.catalogVersion)
        XCTAssertEqual(
            try XCTUnwrap(imported.terminologyReviewedAt).timeIntervalSince1970,
            1_800_000_000,
            accuracy: 0.001
        )
    }

    func testLegacyBackupWithoutTerminologyFieldsImportsAsPending() throws {
        let source = try makeContainer()
        let exercise = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        source.mainContext.insert(exercise)
        try source.mainContext.save()
        let url = try DataExportService.createBackup(in: source.mainContext)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        object["schemaVersion"] = 8
        var exercises = try XCTUnwrap(object["exercises"] as? [[String: Any]])
        let terminologyKeys = [
            "terminologyCanonicalID",
            "terminologyStandardNameZH",
            "terminologyStandardNameEN",
            "terminologyReviewStatusRaw",
            "terminologyDecisionRaw",
            "terminologyConfidenceRaw",
            "terminologyMergeGroup",
            "terminologyReviewNote",
            "terminologyCatalogVersion",
            "terminologyReviewedAt"
        ]
        for key in terminologyKeys {
            exercises[0].removeValue(forKey: key)
        }
        object["exercises"] = exercises
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(legacyData, into: destination.mainContext)
        let imported = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<Exercise>()).first)

        XCTAssertEqual(imported.name, "杠铃卧推")
        XCTAssertEqual(imported.terminologyDecision, .pending)
        XCTAssertNil(imported.terminologyCanonicalID)
        XCTAssertNil(imported.terminologyReviewedAt)
    }

    func testHistoricalCSVIdentityConflictFailsBeforeAnyPartialImport() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let csv = """
        session_id,date,workout,exercise,muscle_group,equipment,set,weight_kg,volume_unit,reps
        a-valid,2026-08-01T10:00:00Z,测试一,新动作,胸部,哑铃,1,10,kilogram,10
        b-conflict,2026-08-02T10:00:00Z,测试二,新动作,背部,龙门架,1,10,kilogram,10
        """

        XCTAssertThrowsError(
            try HistoricalWorkoutCSVService.importCSV(Data(csv.utf8), into: context)
        ) { error in
            guard case let HistoricalWorkoutCSVError.invalidValue(_, field) = error else {
                return XCTFail("应返回动作身份冲突，实际错误：\(error)")
            }
            XCTAssertTrue(field.contains("文件内同名动作"))
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    }

    func testDeviceMergeExactUUIDCannotBypassSemanticIdentityGuard() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = Exercise(
            name: "杠铃卧推",
            muscleGroup: "胸部",
            equipment: "杠铃",
            volumeUnit: .kilogram
        )
        context.insert(existing)
        try context.save()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let package = DeviceHistoryMergePackage(
            schemaVersion: 1,
            source: "robustness-test",
            sessions: [
                DeviceHistoryMergeSession(
                    id: UUID(),
                    templateName: "冲突训练",
                    plannedDate: date,
                    startedAt: date,
                    completedAt: date.addingTimeInterval(600),
                    statusRaw: WorkoutSessionStatus.completed.rawValue,
                    notes: "",
                    restEndDate: nil,
                    importIdentifier: "",
                    exercises: [
                        DeviceHistoryMergeExercise(
                            id: UUID(),
                            sourceExerciseID: existing.id,
                            exerciseName: existing.name,
                            order: 0,
                            targetSets: 1,
                            minReps: 8,
                            maxReps: 8,
                            targetWeight: 50,
                            restSeconds: 90,
                            muscleGroup: existing.muscleGroup,
                            equipment: "史密斯机",
                            exerciseNotes: "",
                            volumeUnitRaw: ExerciseVolumeUnit.kilogram.rawValue,
                            performanceNotes: "",
                            sets: []
                        )
                    ]
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)

        XCTAssertThrowsError(
            try DeviceHistoryMergeService.importPackage(data, into: context)
        ) { error in
            XCTAssertEqual(
                error as? DeviceHistoryMergeError,
                .incompatibleExercise(existing.name)
            )
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    }

    private func completedLog(
        session: WorkoutSession,
        snapshot: SessionExercise,
        exercise: Exercise
    ) -> SetLog {
        SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 20,
            targetReps: 10,
            actualWeight: 20,
            actualReps: 10,
            rir: 2,
            isCompleted: true,
            completedAt: session.startedAt
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            ScheduledWorkout.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetLog.self,
            NutritionTarget.self,
            MealEntry.self,
            DailyBodyCheckIn.self,
            BodyMeasurement.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
