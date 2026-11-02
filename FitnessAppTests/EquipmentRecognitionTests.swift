import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class EquipmentRecognitionTests: XCTestCase {
    func testGenericEquipmentDoesNotBecomeShoulderPressOrPolluteSearch() {
        for generic in ["器械", "固定器械", "machine", "press", "未知器械"] {
            XCTAssertNil(EquipmentCatalogService.englishName(for: generic), generic)
        }
        XCTAssertEqual(EquipmentCatalogService.englishName(for: "器械肩推机"), "Shoulder Press Machine")
        XCTAssertEqual(EquipmentCatalogService.englishName(for: "SHOULDER-PRESS"), "Shoulder Press Machine")
        let dip = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械")
        XCTAssertTrue(ExerciseCatalogService.search([dip], query: "shoulder press").isEmpty)
    }

    func testOCRUsesSeparateCandidatesAndDoesNotResolveAmbiguousEvidence() {
        XCTAssertNil(EquipmentCatalogService.definition(for: "Life Fitness Shoulder Press serial 123"))
        XCTAssertEqual(EquipmentCatalogService.recognitionCandidates(in: "Life Fitness Shoulder Press serial 123").map(\.id), ["shoulder_press_machine"])
        XCTAssertTrue(EquipmentCatalogService.recognitionCandidates(in: "器械 machine press").isEmpty)
        XCTAssertEqual(Set(EquipmentCatalogService.recognitionCandidates(in: "Chest Press and Shoulder Press").map(\.id)), ["chest_press_machine", "shoulder_press_machine"])
        XCTAssertTrue(EquipmentCatalogService.recognitionCandidates(in: "address serial billboard").isEmpty)
    }

    func testConfirmedSeatedDipUsesExistingMainIdentityAndConsistentTerminologyWithoutChangingHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械",
            terminologyCanonicalID: "machine_triceps_press", terminologyStandardNameEN: "Machine Triceps Press (Unverified)",
            terminologyReviewStatus: .unresolved, terminologyDecision: .accepted)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyReviewStatus: .unresolved, terminologyDecision: .accepted)
        let historical = SessionExercise(sessionID: UUID(), exerciseID: alias.id, exerciseName: "seated dip", order: 0,
            targetSets: 3, minReps: 12, maxReps: 12, targetWeight: 25, restSeconds: 90, muscleGroup: "手臂")
        context.insert(main); context.insert(alias); context.insert(historical)
        try context.save()
        let mainID = main.id

        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)

        XCTAssertEqual(main.id, mainID)
        XCTAssertEqual(main.name, "坐姿器械臂屈伸")
        XCTAssertFalse(main.isArchived)
        XCTAssertTrue(alias.isArchived)
        for exercise in [main, alias] {
            XCTAssertEqual(exercise.approvedCanonicalID, "machine_triceps_press")
            XCTAssertEqual(exercise.terminologyStandardNameZH, "坐姿器械臂屈伸")
            XCTAssertEqual(exercise.terminologyStandardNameEN, "Seated Dip")
            XCTAssertEqual(exercise.terminologyReviewStatus, .approvalReady)
            XCTAssertEqual(exercise.muscleGroup, "手臂")
        }
        XCTAssertEqual(historical.exerciseName, "seated dip")
        XCTAssertEqual(historical.exerciseID, alias.id)
        XCTAssertEqual(historical.targetWeight, 25)
        let firstUpdated = main.updatedAt
        let aliasUpdated = alias.updatedAt
        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)
        XCTAssertEqual(main.updatedAt, firstUpdated)
        XCTAssertEqual(alias.updatedAt, aliasUpdated)
        for query in ["seated dip", "三头下压机", "坐姿器械臂屈伸"] {
            XCTAssertEqual(ExerciseCatalogService.search([main], query: query).map(\.id), [mainID])
        }
    }

    func testSeatedDipEnglishAndChineseNamesHaveSamePrimaryMuscleCategory() {
        for name in ["seated dip", "Seated Dip", "三头下压机", "坐姿器械臂屈伸"] {
            XCTAssertEqual(ExerciseMuscleTaxonomy.category(name: name, muscleGroup: "手臂"),
                .init(majorGroup: "手臂", minorGroup: "肱三头肌"), name)
        }
    }

    func testConfirmedMainIdentityExcludesUnreviewedIncompatibleArchivedNamesake() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械",
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let namesake = Exercise(name: "坐姿器械臂屈伸", muscleGroup: "手臂", equipment: "绳索",
            defaultRestSeconds: 135, isArchived: true, notes: "人工归档，尚未审核", volumeUnit: .count)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let mainPlan = TemplateExercise(templateID: UUID(), exerciseID: main.id, order: 0,
            targetSets: 3, minReps: 8, maxReps: 12, targetWeight: 25, restSeconds: 90)
        let namesakePlan = TemplateExercise(templateID: UUID(), exerciseID: namesake.id, order: 0,
            targetSets: 2, minReps: 12, maxReps: 12, targetWeight: 0, restSeconds: 135)
        context.insert(namesake); context.insert(alias); context.insert(main)
        context.insert(mainPlan); context.insert(namesakePlan)
        try context.save()
        let namesakeUpdatedAt = namesake.updatedAt

        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)

        XCTAssertFalse(main.isArchived)
        XCTAssertEqual(main.name, "坐姿器械臂屈伸")
        XCTAssertEqual(mainPlan.exerciseID, main.id)
        XCTAssertEqual(namesakePlan.exerciseID, namesake.id)
        XCTAssertTrue(namesake.isArchived)
        XCTAssertEqual(namesake.terminologyDecision, .pending)
        XCTAssertNil(namesake.terminologyCanonicalID)
        XCTAssertNil(namesake.terminologyStandardNameEN)
        XCTAssertEqual(namesake.equipment, "绳索")
        XCTAssertEqual(namesake.volumeUnit, .count)
        XCTAssertEqual(namesake.notes, "人工归档，尚未审核")
        XCTAssertEqual(namesake.defaultRestSeconds, 135)
        XCTAssertEqual(namesake.updatedAt, namesakeUpdatedAt)
        XCTAssertTrue(alias.isArchived)
        XCTAssertEqual(ExerciseCatalogService.mergedPrimary(for: alias, among: [namesake, alias, main])?.id, main.id)
        XCTAssertNil(ExerciseCatalogService.mergedPrimary(for: namesake, among: [namesake, alias, main]))
        XCTAssertEqual(ExerciseCatalogService.exactNameMatch(named: "Seated Dip", in: [namesake, alias, main])?.id, main.id)
        let timestamps = [main.updatedAt, namesake.updatedAt, alias.updatedAt]

        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)

        XCTAssertEqual([main.updatedAt, namesake.updatedAt, alias.updatedAt], timestamps)
        XCTAssertEqual(mainPlan.exerciseID, main.id)
        XCTAssertEqual(namesakePlan.exerciseID, namesake.id)
        XCTAssertEqual(try ExerciseCatalogService.restore(alias, in: context).id, main.id)
        XCTAssertTrue(namesake.isArchived)
        XCTAssertNil(namesake.approvedCanonicalID)
    }

    func testSelectingMergedArchiveReturnsMainActionWithoutRestoringDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械",
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        context.insert(main); context.insert(alias)
        try context.save()
        let selection = try ExerciseCatalogService.restore(alias, in: context)
        XCTAssertEqual(selection.id, main.id)
        XCTAssertTrue(alias.isArchived)
        XCTAssertTrue(ExerciseCatalogService.search([main, alias], query: "dip", excludedExerciseIDs: [main.id]).isEmpty)
        XCTAssertEqual(ExerciseCatalogService.search([main], query: "肱三头肌").map(\.id), [main.id])
        XCTAssertEqual(ExerciseCatalogService.search([main], query: "胸部").map(\.id), [main.id])
        XCTAssertEqual(main.muscleGroup, "手臂", "辅助胸部只参与说明/搜索，不写入多肌群计组字符串")
    }

    func testCreatingSeatedDipByOldAliasReusesMainRatherThanRestoringDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "坐姿器械臂屈伸", muscleGroup: "手臂", equipment: "器械",
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        context.insert(main); context.insert(alias)
        try context.save()
        for name in ["Seated Dip", "三头下压机"] {
            let saved = try ExerciseCatalogService.save(exercise: nil, name: name, muscleGroup: "手臂", equipment: "器械",
                defaultRestSeconds: 90, notes: "", referenceURL: "", allExercises: [main, alias], in: context)
            XCTAssertEqual(saved.kind, .reused)
            XCTAssertEqual(saved.exercise.id, main.id)
        }
        XCTAssertTrue(alias.isArchived)
    }

    func testSeatedDipMigrationPreservesEntireGroupsManualArchiveAndOriginalMainUUID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let historical = SessionExercise(sessionID: UUID(), exerciseID: alias.id, exerciseName: "seated dip", order: 0,
            targetSets: 3, minReps: 12, maxReps: 12, targetWeight: 25, restSeconds: 90, muscleGroup: "手臂")
        context.insert(alias); context.insert(main); context.insert(historical)
        try context.save()
        let mainID = main.id
        let aliasID = alias.id

        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)

        XCTAssertEqual(main.id, mainID)
        XCTAssertEqual(main.name, "坐姿器械臂屈伸")
        XCTAssertEqual(alias.id, aliasID)
        XCTAssertEqual(alias.name, "seated dip")
        XCTAssertTrue(main.isArchived, "后台规范化不能撤销用户对整组的归档")
        XCTAssertTrue(alias.isArchived)
        XCTAssertTrue(ExerciseCatalogService.search([main, alias], query: "").isEmpty)
        XCTAssertEqual(ExerciseCatalogService.mergedPrimary(for: alias, among: [alias, main])?.id, mainID)
        XCTAssertEqual(historical.exerciseID, aliasID)
        XCTAssertEqual(historical.exerciseName, "seated dip")
        XCTAssertEqual(historical.targetWeight, 25)
        let timestamps = [main.updatedAt, alias.updatedAt]
        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)
        XCTAssertEqual([main.updatedAt, alias.updatedAt], timestamps)
        XCTAssertTrue(main.isArchived)
        XCTAssertTrue(alias.isArchived)
    }

    func testSelectingAliasFromEntirelyArchivedGroupRestoresOriginalMainOnly() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        context.insert(alias); context.insert(main)
        try context.save()
        let selection = try ExerciseCatalogService.restore(alias, in: context)
        XCTAssertEqual(selection.id, main.id)
        XCTAssertFalse(main.isArchived)
        XCTAssertTrue(alias.isArchived)
        XCTAssertEqual(ExerciseCatalogService.search([main, alias], query: "").map(\.id), [main.id])
        let timestamp = main.updatedAt
        XCTAssertEqual(try ExerciseCatalogService.restore(alias, in: context).id, main.id)
        XCTAssertEqual(main.updatedAt, timestamp)
        XCTAssertTrue(alias.isArchived)
    }

    func testSavingArchivedSeatedDipAliasRestoresMainAndAllowsMainEdits() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "坐姿器械臂屈伸", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        context.insert(alias); context.insert(main)
        try context.save()
        let saved = try ExerciseCatalogService.save(exercise: nil, name: "Seated Dip", muscleGroup: "手臂", equipment: "器械",
            defaultRestSeconds: 90, notes: "稳定动作", referenceURL: "", allExercises: [alias, main], in: context)
        XCTAssertEqual(saved.kind, .restored)
        XCTAssertEqual(saved.exercise.id, main.id)
        XCTAssertEqual(main.name, "坐姿器械臂屈伸")
        XCTAssertFalse(main.isArchived)
        XCTAssertTrue(alias.isArchived)
        let edited = try ExerciseCatalogService.save(exercise: main, name: main.name, muscleGroup: "手臂", equipment: "器械",
            defaultRestSeconds: 90, notes: "保持稳定", referenceURL: "", allExercises: [alias, main], in: context)
        XCTAssertEqual(edited.kind, .updated)
        XCTAssertEqual(edited.exercise.id, main.id)
        XCTAssertTrue(alias.isArchived)
    }

    func testCreatingOldAliasRestoresMainWithoutOverwritingExistingMetadata() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "坐姿器械臂屈伸", muscleGroup: "手臂", equipment: "器械",
            defaultRestSeconds: 135, isArchived: true, notes: "主动作已确认提示", referenceURL: "https://example.com/seated-dip",
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        context.insert(alias); context.insert(main)
        try context.save()
        let saved = try ExerciseCatalogService.save(exercise: nil, name: "Seated Dip", muscleGroup: "手臂", equipment: "器械",
            defaultRestSeconds: 90, notes: "", referenceURL: "", allExercises: [alias, main], in: context)
        XCTAssertEqual(saved.kind, .restored)
        XCTAssertEqual(saved.exercise.id, main.id)
        XCTAssertFalse(main.isArchived)
        XCTAssertTrue(alias.isArchived)
        XCTAssertEqual(main.defaultRestSeconds, 135)
        XCTAssertEqual(main.notes, "主动作已确认提示")
        XCTAssertEqual(main.referenceURL, "https://example.com/seated-dip")

        let edited = try ExerciseCatalogService.save(exercise: main, name: main.name, muscleGroup: "手臂", equipment: "器械",
            defaultRestSeconds: 120, notes: "明确编辑后的提示", referenceURL: "https://example.com/updated", allExercises: [alias, main], in: context)
        XCTAssertEqual(edited.kind, .updated)
        XCTAssertEqual(main.defaultRestSeconds, 120)
        XCTAssertEqual(main.notes, "明确编辑后的提示")
        XCTAssertEqual(main.referenceURL, "https://example.com/updated")
    }

    func testSeatedDipSecondaryChestIsFilterableWithoutChangingPrimaryVolumeGroup() {
        for name in ["坐姿器械臂屈伸", "三头下压机", "Seated Dip"] {
            let categories = ExerciseMuscleTaxonomy.filterCategories(name: name, muscleGroup: "手臂")
            XCTAssertEqual(categories, [
                .init(majorGroup: "手臂", minorGroup: "肱三头肌"),
                .init(majorGroup: "胸部", minorGroup: "辅助参与")
            ])
            XCTAssertEqual(ExerciseMuscleTaxonomy.category(name: name, muscleGroup: "手臂"),
                .init(majorGroup: "手臂", minorGroup: "肱三头肌"))
        }
        XCTAssertEqual(ExerciseMuscleTaxonomy.filterCategories(name: "绳索下压", muscleGroup: "手臂"),
            [.init(majorGroup: "手臂", minorGroup: "肱三头肌")])
    }

    func testSeatedDipMigrationWaitsForActiveTraining() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械")
        let active = WorkoutSession(templateName: "进行中", plannedDate: .now)
        context.insert(exercise); context.insert(active)
        try context.save()
        let updatedAt = exercise.updatedAt
        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)
        XCTAssertEqual(exercise.name, "三头下压机")
        XCTAssertNil(exercise.terminologyCanonicalID)
        XCTAssertEqual(exercise.updatedAt, updatedAt)
    }

    func testApprovedSeatedDipLabelsRefreshDuringActiveTrainingWithoutRewiringItsRecords() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let main = Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械",
            terminologyCanonicalID: "machine_triceps_press",
            terminologyStandardNameZH: "器械三头肌下压（待确认）",
            terminologyStandardNameEN: "Machine Triceps Press (Unverified)",
            terminologyReviewStatus: .unresolved, terminologyDecision: .accepted)
        let alias = Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isArchived: true,
            terminologyCanonicalID: "machine_triceps_press", terminologyDecision: .accepted)
        let unreviewed = Exercise(name: "坐姿器械臂屈伸", muscleGroup: "手臂", equipment: "绳索",
            isArchived: true, notes: "人工归档，尚未审核", volumeUnit: .count)
        let active = WorkoutSession(templateName: "进行中", plannedDate: .now)
        let snapshot = SessionExercise(sessionID: active.id, exerciseID: alias.id,
            exerciseName: "seated dip", order: 0, targetSets: 3, minReps: 8, maxReps: 12,
            targetWeight: 25, restSeconds: 90, muscleGroup: "手臂")
        let log = SetLog(sessionID: active.id, sessionExerciseID: snapshot.id, exerciseID: alias.id,
            setNumber: 1, targetWeight: 25, targetReps: 12, actualWeight: 24, actualReps: 11)
        let plan = TemplateExercise(templateID: UUID(), exerciseID: alias.id, order: 0,
            targetSets: 3, minReps: 8, maxReps: 12, targetWeight: 25, restSeconds: 90)
        context.insert(main); context.insert(alias); context.insert(unreviewed)
        context.insert(active); context.insert(snapshot); context.insert(log); context.insert(plan)
        try context.save()
        let originalMainID = main.id
        let unreviewedUpdatedAt = unreviewed.updatedAt

        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)

        XCTAssertEqual(main.id, originalMainID)
        XCTAssertEqual(main.name, "坐姿器械臂屈伸")
        for exercise in [main, alias] {
            XCTAssertEqual(exercise.approvedCanonicalID, "machine_triceps_press")
            XCTAssertEqual(exercise.terminologyStandardNameZH, "坐姿器械臂屈伸")
            XCTAssertEqual(exercise.terminologyStandardNameEN, "Seated Dip")
            XCTAssertEqual(exercise.terminologyReviewStatus, .approvalReady)
        }
        XCTAssertFalse(main.isArchived)
        XCTAssertTrue(alias.isArchived)
        XCTAssertEqual(alias.name, "seated dip")
        XCTAssertEqual(plan.exerciseID, alias.id, "进行中仍禁止整批计划合并")
        XCTAssertEqual(snapshot.exerciseID, alias.id)
        XCTAssertEqual(snapshot.exerciseName, "seated dip")
        XCTAssertEqual(snapshot.targetWeight, 25)
        XCTAssertEqual(log.exerciseID, alias.id)
        XCTAssertEqual(log.actualWeight, 24)
        XCTAssertEqual(log.actualReps, 11)
        XCTAssertFalse(log.isCompleted)
        XCTAssertEqual(active.status, .inProgress)
        XCTAssertEqual(unreviewed.updatedAt, unreviewedUpdatedAt)
        XCTAssertNil(unreviewed.approvedCanonicalID)
        XCTAssertTrue(unreviewed.isArchived)
        let timestamps = [main.updatedAt, alias.updatedAt]
        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)
        XCTAssertEqual([main.updatedAt, alias.updatedAt], timestamps)
    }

    func testBodyweightIsExplicitAndCountsRepetitions() {
        XCTAssertEqual(ExerciseVolumeUnit.bodyweight.symbol, "kg·次")
        XCTAssertFalse(ExerciseVolumeUnit.bodyweight.recordsNumericLoad)
        XCTAssertEqual(ExerciseVolumeUnit.bodyweight.volume(weight: 92, reps: 12), 1_104)
    }

    func testEquipmentEnglishNameAndAliasParticipateInExerciseSearch() {
        let exercise = Exercise(
            name: "史密斯机上斜卧推",
            muscleGroup: "胸部",
            equipment: "史密斯机"
        )

        XCTAssertEqual(
            ExerciseCatalogService.search([exercise], query: "smith machine").map(\.id),
            [exercise.id]
        )
        XCTAssertEqual(EquipmentCatalogService.englishName(for: "史密斯"), "Smith Machine")
    }

    func testExerciseEditorEquipmentChoicesCoverCommonFreeWeights() {
        XCTAssertTrue(EquipmentCatalogService.commonChoices.contains("自重"))
        XCTAssertTrue(EquipmentCatalogService.commonChoices.contains("哑铃"))
        XCTAssertTrue(EquipmentCatalogService.commonChoices.contains("杠铃"))
        XCTAssertTrue(EquipmentCatalogService.commonChoices.contains("壶铃"))
        XCTAssertEqual(EquipmentCatalogService.englishName(for: "壶铃"), "Kettlebell")
    }

    func testPreviousSettingsCopyCompletedWorkingSetsWithoutMutatingHistory() throws {
        let exercise = Exercise(
            name: "单臂划船",
            muscleGroup: "背部",
            equipment: "哑铃"
        )
        let session = WorkoutSession(
            templateName: "拉日",
            plannedDate: .now.addingTimeInterval(-86_400),
            completedAt: .now.addingTimeInterval(-80_000),
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 12,
            targetWeight: 24,
            restSeconds: 120,
            volumeUnit: .kilogram
        )
        snapshot.equipmentSnapshot = exercise.equipment
        let first = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 24,
            targetReps: 12,
            actualWeight: 26,
            actualReps: 11,
            isCompleted: true,
            targetWeightSide: .single,
            targetRepsSide: .single
        )
        let second = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 2,
            targetWeight: 24,
            targetReps: 12,
            actualWeight: 26,
            actualReps: 10,
            isCompleted: true,
            targetWeightSide: .single,
            targetRepsSide: .single
        )

        let draft = ExerciseSetupDraft.suggested(
            for: exercise,
            sessions: [session],
            sessionExercises: [snapshot],
            setLogs: [first, second]
        )

        XCTAssertEqual(draft.plannedSets.map { $0.weight }, [26, 26])
        XCTAssertEqual(draft.plannedSets.map { $0.reps }, [11, 10])
        XCTAssertEqual(draft.measurementSide, MeasurementSide.single)
        XCTAssertEqual(draft.restSeconds, 120)
        XCTAssertNotNil(draft.previousDate)
        XCTAssertEqual(first.actualWeight, 26)
        XCTAssertEqual(snapshot.targetWeight, 24)
    }

    func testConfiguredTemporaryExerciseUsesDraftAndKeepsExistingHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "器械腿举", muscleGroup: "腿部", equipment: "腿举机")
        let session = WorkoutSession(templateName: "腿日", plannedDate: .now)
        context.insert(exercise)
        context.insert(session)
        try context.save()

        let draft = ExerciseSetupDraft(
            pattern: .fixed,
            plannedSets: [
                WorkoutSetPlan(weight: 80, reps: 12, weightSide: .bilateral, repsSide: .bilateral),
                WorkoutSetPlan(weight: 90, reps: 10, weightSide: .bilateral, repsSide: .bilateral)
            ],
            restSeconds: 150,
            previousDate: .now.addingTimeInterval(-86_400)
        )
        let snapshot = try WorkoutService.addExercise(
            exercise,
            to: session,
            configuration: draft,
            in: context
        )
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == snapshot.id }
            .sorted { $0.setNumber < $1.setNumber }

        XCTAssertEqual(snapshot.targetSets, 2)
        XCTAssertEqual(snapshot.restSeconds, 150)
        XCTAssertEqual(logs.map(\.actualWeight), [80, 90])
        XCTAssertEqual(logs.map(\.actualReps), [12, 10])
    }

    func testMockRecognitionAlwaysRequiresHumanConfirmation() {
        let result = EquipmentRecognitionService.mockResponse
        XCTAssertTrue(result.needsConfirmation)
        XCTAssertFalse(result.machine.nameZH.isEmpty)
        XCTAssertFalse(result.machine.nameEN.isEmpty)
        XCTAssertFalse(result.exerciseCandidates.isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetLog.self,
            ScheduledWorkout.self,
            WorkoutTemplate.self,
            TemplateExercise.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
