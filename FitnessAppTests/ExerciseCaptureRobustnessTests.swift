import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FitnessApp

@MainActor
final class ExerciseCaptureRobustnessTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: NotificationService.workoutEnabledKey)
    }

    func testCatalogRequiredFieldsAndURLProtocolMatrixAreAtomic() throws {
        let container = try makeContainer()
        let context = container.mainContext

        assertCatalogError(.missingName) {
            _ = try saveExercise(name: "  ", in: context)
        }
        assertCatalogError(.missingMuscleGroup) {
            _ = try saveExercise(name: "空肌群", muscleGroup: "  ", in: context)
        }
        assertCatalogError(.missingEquipment) {
            _ = try saveExercise(name: "空器械", equipment: "\n", in: context)
        }

        let invalidURLs = [
            "javascript:alert(1)",
            "file:///tmp/video.mov",
            "ftp://example.com/demo",
            "https://",
            "not a url"
        ]
        for (index, value) in invalidURLs.enumerated() {
            assertCatalogError(.invalidReferenceURL) {
                _ = try saveExercise(
                    name: "非法链接\(index)",
                    referenceURL: value,
                    in: context
                )
            }
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)

        let validURLs = ["", "http://example.com/demo", "https://example.com/动作?q=1"]
        for (index, value) in validURLs.enumerated() {
            let result = try saveExercise(
                name: "合法链接\(index)",
                referenceURL: value,
                in: context
            )
            XCTAssertEqual(result.kind, .created)
            XCTAssertEqual(result.exercise.referenceURL, value)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, validURLs.count)
    }

    func testCatalogReusesCompatibleActiveExerciseWithoutOverwritingIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = Exercise(
            name: "单臂下拉",
            muscleGroup: "背部",
            equipment: "龙门架",
            defaultRestSeconds: 75,
            isBuiltIn: false,
            notes: "原始提示",
            referenceURL: "https://example.com/original"
        )
        context.insert(existing)
        try context.save()

        let result = try ExerciseCatalogService.save(
            exercise: nil,
            name: "  单臂下拉  ",
            muscleGroup: "背部",
            equipment: "龙门架",
            defaultRestSeconds: 120,
            notes: "新输入不应静默覆盖",
            referenceURL: "https://example.com/new",
            allExercises: [existing],
            in: context
        )

        XCTAssertEqual(result.kind, .reused)
        XCTAssertEqual(result.exercise.id, existing.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertEqual(existing.defaultRestSeconds, 75)
        XCTAssertEqual(existing.notes, "原始提示")
        XCTAssertEqual(existing.referenceURL, "https://example.com/original")
    }

    func testCatalogRejectsIdentityConflictsAndDuplicateEditAtomically() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = Exercise(
            name: "器械推胸",
            muscleGroup: "胸部",
            equipment: "器械",
            isBuiltIn: false,
            volumeUnit: .kilogram
        )
        let editable = Exercise(
            name: "待编辑动作",
            muscleGroup: "胸部",
            equipment: "器械",
            isBuiltIn: false,
            notes: "保持不变"
        )
        context.insert(existing)
        context.insert(editable)
        try context.save()

        let conflicts: [(String, String, ExerciseVolumeUnit)] = [
            ("背部", "器械", .kilogram),
            ("胸部", "哑铃", .kilogram),
            ("胸部", "器械", .count)
        ]
        for (muscleGroup, equipment, unit) in conflicts {
            assertCatalogError(.conflictingIdentity) {
                _ = try ExerciseCatalogService.save(
                    exercise: nil,
                    name: "器械推胸",
                    muscleGroup: muscleGroup,
                    equipment: equipment,
                    volumeUnit: unit,
                    defaultRestSeconds: 90,
                    notes: "",
                    referenceURL: "",
                    allExercises: [existing, editable],
                    in: context
                )
            }
        }

        assertCatalogError(.duplicateName) {
            _ = try ExerciseCatalogService.save(
                exercise: editable,
                name: "器械推胸",
                muscleGroup: "胸部",
                equipment: "器械",
                defaultRestSeconds: 60,
                notes: "不应保存",
                referenceURL: "https://example.com/not-saved",
                allExercises: [existing, editable],
                in: context
            )
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 2)
        XCTAssertEqual(editable.name, "待编辑动作")
        XCTAssertEqual(editable.notes, "保持不变")
        XCTAssertEqual(editable.referenceURL, "")
    }

    func testCatalogSuccessfulEditKeepsUUIDAndHistoricalSnapshotImmutable() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "原动作名",
            muscleGroup: "胸部",
            equipment: "哑铃",
            isBuiltIn: false,
            notes: "原要点",
            referenceURL: "https://example.com/original"
        )
        let session = WorkoutSession(
            templateName: "历史训练",
            plannedDate: .now,
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 10,
            restSeconds: 60,
            muscleGroup: exercise.muscleGroup,
            exerciseNotes: exercise.notes,
            referenceURL: exercise.referenceURL
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        try context.save()
        let originalID = exercise.id

        let result = try ExerciseCatalogService.save(
            exercise: exercise,
            name: "新动作名",
            muscleGroup: "肩部",
            equipment: "龙门架",
            defaultRestSeconds: 120,
            notes: "新要点",
            referenceURL: "https://example.com/updated",
            allExercises: [exercise],
            in: context
        )

        XCTAssertEqual(result.kind, .updated)
        XCTAssertEqual(result.exercise.id, originalID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertEqual(exercise.name, "新动作名")
        XCTAssertEqual(exercise.referenceURL, "https://example.com/updated")
        XCTAssertEqual(snapshot.exerciseID, originalID)
        XCTAssertEqual(snapshot.exerciseName, "原动作名")
        XCTAssertEqual(snapshot.exerciseNotes, "原要点")
        XCTAssertEqual(snapshot.referenceURL, "https://example.com/original")
    }

    func testCatalogSearchCoversEveryFieldNormalizesSortsAndExcludes() {
        let primary = Exercise(
            name: "ＭＴＳ 划船",
            muscleGroup: "背部",
            equipment: "器械",
            isBuiltIn: false,
            notes: "肩胛后缩",
            referenceURL: "https://example.com/row",
            terminologyCanonicalID: "cable_row",
            terminologyStandardNameZH: "标准划船",
            terminologyStandardNameEN: "Cable Row"
        )
        let second = Exercise(
            name: "Alpha Row",
            muscleGroup: "背部",
            equipment: "龙门架",
            notes: "排序命中"
        )
        let archived = Exercise(
            name: "Beta Row",
            muscleGroup: "背部",
            equipment: "龙门架",
            isArchived: true,
            notes: "排序命中"
        )

        for query in [
            "mts", "背部", "器械", "肩胛后缩", "example.com/row",
            "标准划船", "cable row", "cable_row"
        ] {
            XCTAssertEqual(
                ExerciseCatalogService.search([primary], query: query).map(\.id),
                [primary.id],
                "未命中字段：\(query)"
            )
        }

        XCTAssertEqual(
            ExerciseCatalogService.search([archived, second], query: "排序命中").map(\.id),
            [second.id, archived.id]
        )
        XCTAssertEqual(
            ExerciseCatalogService.search([primary, archived], query: "").map(\.id),
            [primary.id]
        )
        XCTAssertTrue(
            ExerciseCatalogService.search(
                [primary],
                query: "mts",
                excludedExerciseIDs: [primary.id]
            ).isEmpty
        )
    }

    func testDailyPlanValidationPreservesExistingPlanForArchivedAndDuplicateDrafts() throws {
        for invalidKind in ["archived", "duplicate"] {
            let container = try makeContainer()
            let context = container.mainContext
            let date = Date.now.startOfDay
            let active = Exercise(name: "有效卧推", muscleGroup: "胸部", equipment: "杠铃")
            let archived = Exercise(
                name: "归档飞鸟",
                muscleGroup: "胸部",
                equipment: "龙门架",
                isArchived: true
            )
            let oldTemplate = WorkoutTemplate(
                name: "旧当天菜单",
                weekday: date.weekdayNumber,
                isActive: false,
                isOneOff: true,
                plannedForDate: date,
                focusMuscleGroups: ["胸部"]
            )
            let oldItem = TemplateExercise(
                templateID: oldTemplate.id,
                exerciseID: active.id,
                order: 0,
                targetSets: 2,
                minReps: 10,
                maxReps: 10,
                targetWeight: 40,
                restSeconds: 90
            )
            let oldSchedule = ScheduledWorkout(
                templateID: oldTemplate.id,
                templateName: oldTemplate.name,
                plannedDate: date,
                isManuallyScheduled: true
            )
            [active, archived].forEach(context.insert)
            context.insert(oldTemplate)
            context.insert(oldItem)
            context.insert(oldSchedule)
            try context.save()

            let activeInput = DailyPlanExerciseInput(
                exerciseID: active.id,
                targetSets: 3,
                minReps: 8,
                maxReps: 12,
                targetWeight: 42.5,
                restSeconds: 90
            )
            let inputs = invalidKind == "archived"
                ? [DailyPlanExerciseInput(
                    exerciseID: archived.id,
                    targetSets: 3,
                    minReps: 8,
                    maxReps: 12,
                    targetWeight: 10,
                    restSeconds: 60
                )]
                : [activeInput, activeInput]

            XCTAssertThrowsError(
                try DailyPlanService.create(
                    on: date,
                    muscleGroups: ["胸部"],
                    exercises: inputs,
                    replaceExistingPlans: true,
                    in: context
                )
            )

            XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.id), [oldTemplate.id])
            XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExercise>()).map(\.id), [oldItem.id])
            XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).map(\.id), [oldSchedule.id])
            XCTAssertEqual(oldSchedule.status, .planned)
        }
    }

    func testDailyPlanReplacementIsDateScopedAndPreservesFutureOneOff() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let targetDate = Date.now.startOfDay
        let futureDate = targetDate.addingDays(1)
        let exercise = Exercise(name: "卧推", muscleGroup: "胸部", equipment: "杠铃")
        context.insert(exercise)

        let targetWeekly = WorkoutTemplate(name: "目标日固定计划", weekday: targetDate.weekdayNumber)
        let futureWeekly = WorkoutTemplate(name: "未来固定计划", weekday: futureDate.weekdayNumber)
        let oldTargetOneOff = WorkoutTemplate(
            name: "旧目标菜单",
            weekday: targetDate.weekdayNumber,
            isActive: false,
            isOneOff: true,
            plannedForDate: targetDate,
            focusMuscleGroups: ["胸部"]
        )
        let futureOneOff = WorkoutTemplate(
            name: "未来菜单",
            weekday: futureDate.weekdayNumber,
            isActive: false,
            isOneOff: true,
            plannedForDate: futureDate,
            focusMuscleGroups: ["胸部"]
        )
        [targetWeekly, futureWeekly, oldTargetOneOff, futureOneOff].forEach(context.insert)

        let targetWeeklySchedule = ScheduledWorkout(
            templateID: targetWeekly.id,
            templateName: targetWeekly.name,
            plannedDate: targetDate
        )
        let futureWeeklySchedule = ScheduledWorkout(
            templateID: futureWeekly.id,
            templateName: futureWeekly.name,
            plannedDate: futureDate
        )
        let oldTargetSchedule = ScheduledWorkout(
            templateID: oldTargetOneOff.id,
            templateName: oldTargetOneOff.name,
            plannedDate: targetDate,
            status: .skipped,
            isManuallyScheduled: true
        )
        let futureOneOffSchedule = ScheduledWorkout(
            templateID: futureOneOff.id,
            templateName: futureOneOff.name,
            plannedDate: futureDate,
            isManuallyScheduled: true
        )
        [targetWeeklySchedule, futureWeeklySchedule, oldTargetSchedule, futureOneOffSchedule]
            .forEach(context.insert)

        let oldTargetItem = TemplateExercise(
            templateID: oldTargetOneOff.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 10,
            targetWeight: 35,
            restSeconds: 90
        )
        let futureItem = TemplateExercise(
            templateID: futureOneOff.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 40,
            restSeconds: 90
        )
        context.insert(oldTargetItem)
        context.insert(futureItem)
        try context.save()

        let replacement = try DailyPlanService.create(
            on: targetDate,
            muscleGroups: ["胸部"],
            exercises: [
                DailyPlanExerciseInput(
                    exerciseID: exercise.id,
                    targetSets: 4,
                    minReps: 6,
                    maxReps: 6,
                    targetWeight: 45,
                    restSeconds: 120
                )
            ],
            replaceExistingPlans: true,
            in: context
        )

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
        XCTAssertFalse(templates.contains(where: { $0.id == oldTargetOneOff.id }))
        XCTAssertFalse(schedules.contains(where: { $0.id == oldTargetSchedule.id }))
        XCTAssertFalse(items.contains(where: { $0.id == oldTargetItem.id }))
        XCTAssertTrue(templates.contains(where: { $0.id == futureOneOff.id }))
        XCTAssertTrue(schedules.contains(where: { $0.id == futureOneOffSchedule.id }))
        XCTAssertTrue(items.contains(where: { $0.id == futureItem.id }))
        XCTAssertEqual(targetWeeklySchedule.status, .skipped)
        XCTAssertEqual(targetWeeklySchedule.skipReason, "已用当天自选菜单替代")
        XCTAssertEqual(futureWeeklySchedule.status, .planned)
        XCTAssertEqual(futureOneOffSchedule.status, .planned)
        XCTAssertTrue(replacement.plannedDate.isSameDay(as: targetDate))
    }

    func testWorkoutStartRejectsInvalidCatalogReferencesBeforeCreatingSession() throws {
        for scenario in ["missing", "archived"] {
            let container = try makeContainer()
            let context = container.mainContext
            let template = WorkoutTemplate(name: "原子启动", weekday: Date.now.weekdayNumber)
            let exerciseID: UUID
            if scenario == "archived" {
                let archived = Exercise(
                    name: "已归档",
                    muscleGroup: "胸部",
                    equipment: "器械",
                    isArchived: true
                )
                exerciseID = archived.id
                context.insert(archived)
            } else {
                exerciseID = UUID()
            }
            let item = TemplateExercise(
                templateID: template.id,
                exerciseID: exerciseID,
                order: 0,
                targetSets: 3,
                minReps: 8,
                maxReps: 12,
                targetWeight: 20,
                restSeconds: 90
            )
            let schedule = ScheduledWorkout(
                templateID: template.id,
                templateName: template.name,
                plannedDate: .now
            )
            context.insert(template)
            context.insert(item)
            context.insert(schedule)
            try context.save()

            XCTAssertThrowsError(try WorkoutService.start(schedule: schedule, in: context))
            XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
            XCTAssertEqual(schedule.status, .planned)
        }
    }

    func testActiveWorkoutGuardsArchivedDuplicateAndFinishedSession() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            templateName: "进行中",
            plannedDate: .now,
            status: .inProgress
        )
        let active = Exercise(name: "绳索弯举", muscleGroup: "手臂", equipment: "龙门架")
        let archived = Exercise(
            name: "归档弯举",
            muscleGroup: "手臂",
            equipment: "哑铃",
            isArchived: true
        )
        let another = Exercise(name: "锤式弯举", muscleGroup: "手臂", equipment: "哑铃")
        context.insert(session)
        context.insert(active)
        context.insert(archived)
        context.insert(another)
        try context.save()

        let snapshot = try WorkoutService.addExercise(active, to: session, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).count, 3)

        assertWorkoutError(.exerciseAlreadyAdded) {
            _ = try WorkoutService.addExercise(active, to: session, in: context)
        }
        assertWorkoutError(.archivedExercise) {
            _ = try WorkoutService.addExercise(archived, to: session, in: context)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).count, 3)

        assertWorkoutError(.cannotRemoveLastExercise) {
            try WorkoutService.removeExercise(snapshot, from: session, in: context)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).count, 3)

        session.status = .completed
        assertWorkoutError(.sessionNotInProgress) {
            _ = try WorkoutService.addExercise(another, to: session, in: context)
        }
        assertWorkoutError(.sessionNotInProgress) {
            _ = try WorkoutService.addSet(to: snapshot, in: context)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).count, 3)
    }

    func testActiveWorkoutUsesRecentValuesAndCreatesImmutableSourceSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "古巴推举",
            muscleGroup: "肩部",
            equipment: "哑铃",
            defaultRestSeconds: 75,
            notes: "肘部抬高",
            referenceURL: "https://example.com/cuban",
            volumeUnit: .kilogram
        )
        let oldSessionID = UUID()
        let previous = SetLog(
            sessionID: oldSessionID,
            sessionExerciseID: UUID(),
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 8,
            targetReps: 12,
            actualWeight: 10,
            actualReps: 9,
            isCompleted: true,
            completedAt: Date.now.addingTimeInterval(-3_600)
        )
        let current = WorkoutSession(
            templateName: "肩部",
            plannedDate: .now,
            status: .inProgress
        )
        context.insert(exercise)
        context.insert(previous)
        context.insert(current)
        try context.save()

        let snapshot = try WorkoutService.addExercise(exercise, to: current, in: context)
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == snapshot.id }
            .sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(snapshot.exerciseName, "古巴推举")
        XCTAssertEqual(snapshot.exerciseNotes, "肘部抬高")
        XCTAssertEqual(snapshot.referenceURL, "https://example.com/cuban")
        XCTAssertEqual(snapshot.restSeconds, 75)
        XCTAssertEqual(logs.map(\.actualWeight), [10, 10, 10])
        XCTAssertEqual(logs.map(\.actualReps), [9, 9, 9])

        exercise.name = "后来改名"
        exercise.notes = "后来修改"
        exercise.referenceURL = "https://example.com/changed"
        exercise.volumeUnit = .count
        try context.save()
        XCTAssertEqual(snapshot.exerciseName, "古巴推举")
        XCTAssertEqual(snapshot.exerciseNotes, "肘部抬高")
        XCTAssertEqual(snapshot.referenceURL, "https://example.com/cuban")
        XCTAssertEqual(snapshot.volumeUnit, .kilogram)
    }

    func testShareDraftNormalizationNameSuggestionAndEmptyState() {
        let source = URL(string: "https://example.com/pulldown")
        let draft = ExerciseShareDraft(
            sharedText: "  \n 单臂绳索下拉 \n保持肩胛下沉  ",
            sourceURL: source
        )
        XCTAssertEqual(draft.sharedText, "单臂绳索下拉 \n保持肩胛下沉")
        XCTAssertEqual(draft.suggestedExerciseName, "单臂绳索下拉")
        XCTAssertFalse(draft.isEmpty)

        let urlOnly = ExerciseShareDraft(sharedText: source?.absoluteString ?? "", sourceURL: source)
        XCTAssertEqual(urlOnly.suggestedExerciseName, "")
        XCTAssertFalse(urlOnly.isEmpty)
        XCTAssertTrue(ExerciseShareDraft(sharedText: "  ").isEmpty)

        let longName = String(repeating: "动作", count: 60)
        XCTAssertEqual(ExerciseShareDraft(sharedText: longName).suggestedExerciseName.count, 80)
    }

    func testShareContentCollectorHandlesURLTextMixedAndUnsupportedProviders() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/cable-row"))
        let urlProvider = NSItemProvider(
            item: url as NSURL,
            typeIdentifier: UTType.url.identifier
        )
        let textProvider = NSItemProvider(
            item: "绳索划船\n肩胛后收" as NSString,
            typeIdentifier: UTType.plainText.identifier
        )
        let unsupportedProvider = NSItemProvider(
            item: Data([0x01, 0x02]) as NSData,
            typeIdentifier: UTType.data.identifier
        )

        let urlOnly = try collectSharedContent(providers: [urlProvider])
        XCTAssertEqual(urlOnly.urls, [url])
        XCTAssertEqual(urlOnly.combinedText, "")

        let textOnly = try collectSharedContent(providers: [textProvider])
        XCTAssertEqual(textOnly.urls, [])
        XCTAssertEqual(textOnly.combinedText, "绳索划船\n肩胛后收")

        let mixed = try collectSharedContent(
            providers: [urlProvider, textProvider],
            initialTexts: ["编辑提示", "编辑提示"]
        )
        XCTAssertEqual(mixed.urls, [url])
        XCTAssertEqual(mixed.combinedText, "编辑提示\n\n绳索划船\n肩胛后收")

        let unsupported = try collectSharedContent(providers: [unsupportedProvider])
        XCTAssertTrue(unsupported.urls.isEmpty)
        XCTAssertEqual(unsupported.combinedText, "")
    }

    func testShareInboxLatestWinsReadIsNonDestructiveAndConsumeIsIdempotent() throws {
        let suiteName = "xfit-share-robustness-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let inbox = ExerciseShareDraftInbox(defaults: defaults)
        let first = ExerciseShareDraft(sharedText: "动作 A")
        let latest = ExerciseShareDraft(
            sharedText: "动作 B",
            sourceURL: URL(string: "https://example.com/b")
        )

        defaults.set(try JSONEncoder().encode(first), forKey: ExerciseShareDraftStorage.pendingDraftKey)
        defaults.set(try JSONEncoder().encode(latest), forKey: ExerciseShareDraftStorage.pendingDraftKey)
        XCTAssertEqual(inbox.pendingDraft(), latest)
        XCTAssertEqual(inbox.pendingDraft(), latest, "读取/稍后处理不能消费草稿")
        XCTAssertEqual(inbox.consumePendingDraft(), latest)
        XCTAssertNil(inbox.consumePendingDraft())
        XCTAssertNil(inbox.pendingDraft())
    }

    func testProductionAndUITestShareInboxesUseIsolatedKeys() throws {
        let suiteName = "xfit-share-key-isolation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let productionDraft = ExerciseShareDraft(sharedText: "真实分享动作")
        let uiTestDraft = ExerciseShareDraft(sharedText: "UI 测试动作")

        defaults.set(
            try JSONEncoder().encode(productionDraft),
            forKey: ExerciseShareDraftStorage.pendingDraftKey
        )
        defaults.set(
            try JSONEncoder().encode(uiTestDraft),
            forKey: ExerciseShareDraftStorage.uiTestingPendingDraftKey
        )

        let productionInbox = ExerciseShareDraftInbox(defaults: defaults)
        let uiTestInbox = ExerciseShareDraftInbox(
            defaults: defaults,
            pendingDraftKey: ExerciseShareDraftStorage.uiTestingPendingDraftKey
        )

        XCTAssertEqual(productionInbox.pendingDraft(), productionDraft)
        XCTAssertEqual(uiTestInbox.pendingDraft(), uiTestDraft)
        uiTestInbox.clearPendingDraft(matching: uiTestDraft.id)
        XCTAssertEqual(productionInbox.pendingDraft(), productionDraft)
        XCTAssertNil(uiTestInbox.pendingDraft())
    }

    func testShareInboxRejectsCorruptAndUnsupportedSchema() throws {
        let suiteName = "xfit-share-schema-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let inbox = ExerciseShareDraftInbox(defaults: defaults)

        defaults.set(Data("not-json".utf8), forKey: ExerciseShareDraftStorage.pendingDraftKey)
        XCTAssertNil(inbox.pendingDraft())

        let valid = ExerciseShareDraft(sharedText: "未来草稿")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
        )
        object["schemaVersion"] = ExerciseShareDraftStorage.schemaVersion + 1
        defaults.set(
            try JSONSerialization.data(withJSONObject: object),
            forKey: ExerciseShareDraftStorage.pendingDraftKey
        )
        XCTAssertNil(inbox.pendingDraft())
    }

    func testLegacyBackupWithoutReferenceURLDefaultsSafely() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let exercise = Exercise(
            name: "旧备份动作",
            muscleGroup: "核心",
            equipment: "自重",
            referenceURL: "https://example.com/source"
        )
        let session = WorkoutSession(
            templateName: "旧备份训练",
            plannedDate: .now,
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 0,
            restSeconds: 60,
            muscleGroup: exercise.muscleGroup,
            referenceURL: exercise.referenceURL
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        try context.save()

        let currentData = try Data(contentsOf: DataExportService.createBackup(in: context))
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        root["schemaVersion"] = 4
        root["exercises"] = try XCTUnwrap(root["exercises"] as? [[String: Any]]).map { record in
            var mutable = record
            mutable.removeValue(forKey: "referenceURL")
            return mutable
        }
        root["sessionExercises"] = try XCTUnwrap(
            root["sessionExercises"] as? [[String: Any]]
        ).map { record in
            var mutable = record
            mutable.removeValue(forKey: "referenceURL")
            return mutable
        }

        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(legacyData, into: destination.mainContext)
        XCTAssertEqual(
            try destination.mainContext.fetch(FetchDescriptor<Exercise>()).first?.referenceURL,
            ""
        )
        XCTAssertEqual(
            try destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first?.referenceURL,
            ""
        )
    }

    func testCSVQuotesReferenceURLAndNotes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            templateName: "CSV 测试",
            plannedDate: .now,
            status: .completed,
            notes: "第一行,第二列\n下一行"
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: UUID(),
            exerciseName: "参考动作",
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 10,
            restSeconds: 60,
            muscleGroup: "核心",
            referenceURL: "https://example.com/demo?cue=a,b",
            performanceNotes: "慢放,停顿\n保持稳定"
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: snapshot.exerciseID,
            setNumber: 1,
            targetWeight: 10,
            targetReps: 8,
            actualWeight: 10,
            actualReps: 8,
            isCompleted: true,
            completedAt: .now
        )
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let csv = try String(contentsOf: DataExportService.createCSV(in: context), encoding: .utf8)
        XCTAssertTrue(csv.contains("exercise_reference_url"))
        XCTAssertTrue(csv.contains("\"https://example.com/demo?cue=a,b\""))
        XCTAssertTrue(csv.contains("\"慢放,停顿\n保持稳定\""))
        XCTAssertTrue(csv.contains("\"第一行,第二列\n下一行\""))
    }

    func testCatalogSearchHandlesOneThousandExercisesWithinBudget() {
        let exercises = (0..<1_000).map { index in
            Exercise(
                name: "压力动作 \(index)",
                muscleGroup: index.isMultiple(of: 2) ? "胸部" : "背部",
                equipment: "器械",
                notes: index == 777 ? "唯一压力命中" : "普通记录"
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        let result = ExerciseCatalogService.search(exercises, query: "唯一压力命中")
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(result.map(\.name), ["压力动作 777"])
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    private func saveExercise(
        name: String,
        muscleGroup: String = "胸部",
        equipment: String = "哑铃",
        referenceURL: String = "",
        in context: ModelContext
    ) throws -> ExerciseCatalogSaveResult {
        try ExerciseCatalogService.save(
            exercise: nil,
            name: name,
            muscleGroup: muscleGroup,
            equipment: equipment,
            defaultRestSeconds: 90,
            notes: "",
            referenceURL: referenceURL,
            allExercises: try context.fetch(FetchDescriptor<Exercise>()),
            in: context
        )
    }

    private func collectSharedContent(
        providers: [NSItemProvider],
        initialTexts: [String] = []
    ) throws -> ExerciseSharedContent {
        let completion = expectation(description: "分享内容解析完成")
        var result: ExerciseSharedContent?
        ExerciseSharedContentCollector.collect(
            providers: providers,
            initialTexts: initialTexts
        ) { content in
            result = content
            completion.fulfill()
        }
        wait(for: [completion], timeout: 3)
        return try XCTUnwrap(result)
    }

    private func assertCatalogError(
        _ expected: ExerciseCatalogError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ExerciseCatalogError, expected, file: file, line: line)
        }
    }

    private func assertWorkoutError(
        _ expected: WorkoutServiceError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let actual = error as? WorkoutServiceError else {
                return XCTFail("错误类型不正确：\(error)", file: file, line: line)
            }
            XCTAssertEqual(
                actual.errorDescription,
                expected.errorDescription,
                file: file,
                line: line
            )
        }
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
