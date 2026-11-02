#if DEBUG
import Foundation
import SwiftData

/// Explicit isolated UI fixture only. Never seeds a persistent or normal device store.
@MainActor
enum ConfirmedTrainingPlanUITestFixture {
    static var isEnabled: Bool {
        CloudSyncRuntime.isTesting && CloudSyncRuntime.isUITesting && !CloudSyncRuntime.usesPersistentUITestStore
            && CommandLine.arguments.contains("--ui-testing-confirmed-plan-import")
    }
    static var fileURL: URL { URL.documentsDirectory.appendingPathComponent("UITestConfirmedTrainingPlan.json") }

    static func prepare(in context: ModelContext) throws {
        if CloudSyncRuntime.isTesting && CloudSyncRuntime.isUITesting && !CloudSyncRuntime.usesPersistentUITestStore
            && CommandLine.arguments.contains("--ui-testing-daily-prefill") {
            try prepareDailyPrefill(in: context)
            return
        }
        guard isEnabled else { return }
        guard let program = try context.fetch(FetchDescriptor<FatLossProgram>()).first else { return }
        let today = FatLossCalendar.day(.now)
        let weekday = FatLossCalendar.calendar.component(.weekday, from: today)
        let start = FatLossCalendar.adding(-((weekday + 5) % 7), to: today)
        program.startDate = start
        var preference = TrainingPreferenceSnapshot.postTravelRestoration
        preference.revisionCode = "TP-IMPORT-UI"
        preference.strengthDaysPerWeek = 1
        _ = try TrainingPreferenceService.append(snapshot: preference, effectiveAt: start,
            reason: "仅隔离 UI 测试，不是真实偏好", in: context)
        let exercise = Exercise(name: "测试推胸", muscleGroup: "胸部", equipment: "测试器械")
        context.insert(exercise)
        let historyDate = FatLossCalendar.adding(-1, to: start)
        let history = WorkoutSession(templateName: "测试历史", plannedDate: historyDate, startedAt: historyDate,
            completedAt: historyDate.addingTimeInterval(3600), status: .completed)
        context.insert(history)
        let entry = SessionExercise(sessionID: history.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 4, minReps: 8, maxReps: 12, targetWeight: 25, restSeconds: 180,
            muscleGroup: exercise.muscleGroup, equipmentSnapshot: exercise.equipment)
        context.insert(entry)
        for number in 1...4 {
            context.insert(SetLog(sessionID: history.id, sessionExerciseID: entry.id, exerciseID: exercise.id,
                setNumber: number, targetWeight: 25, targetReps: 12, actualWeight: 25, actualReps: 12,
                isCompleted: true, completedAt: history.completedAt,
                targetWeightSide: .bilateral, targetRepsSide: .bilateral,
                actualWeightSide: .bilateral, actualRepsSide: .bilateral))
        }
        try context.save()
        let targets = [
            WorkoutSetPrescription(label: "顶组", repsLower: 8, repsUpper: 10, rirLower: 3, rirUpper: 3,
                restLowerSeconds: 180, restUpperSeconds: 180),
            WorkoutSetPrescription(label: "回退组", repsLower: 10, repsUpper: 12, rirLower: 2, rirUpper: 3,
                restLowerSeconds: 150, restUpperSeconds: 180)
        ]
        var exerciseDraft = ProgramExerciseDraft(name: exercise.name, muscleGroup: exercise.muscleGroup,
            equipment: exercise.equipment, sets: 2, repsLower: 8, repsUpper: 12, restSeconds: 180,
            note: "重量留空；不力竭；疼痛则停止", catalogExerciseID: exercise.id,
            plannedSets: targets.map { WorkoutSetPlan(weight: 0, reps: $0.repsLower, actualDefaultPolicy: .blank, prescription: $0) })
        let source = "# 隔离 UI 测试\n1个顶组＋1个回退组；重量留空。不是本人的真实训练处方。"
        let newIdentity = CommandLine.arguments.contains("--ui-testing-confirmed-plan-new-catalog") ? UUID() : nil
        if let newIdentity {
            exerciseDraft.name = "测试MTS器械下斜推胸"
            exerciseDraft.catalogName = exerciseDraft.name
            exerciseDraft.catalogExerciseID = newIdentity
            exerciseDraft.equipment = "测试MTS下斜推胸机"
        }
        var packet = ConfirmedTrainingPlanPacket(version: 1, programID: program.id,
            startLocalDay: FatLossCalendar.label(start), endLocalDay: FatLossCalendar.label(FatLossCalendar.adding(6, to: start)),
            timeZoneIdentifier: "Asia/Shanghai", confirmedAt: Date.now.addingTimeInterval(-60),
            confirmationReference: "ISOLATED-UI-TEST", sourceMarkdown: source,
            sourceSHA256: ConfirmedTrainingPlanService.digest(Data(source.utf8)),
            snapshot: TrainingProgramSnapshot(code: "IMPORT-UI-R1", title: "隔离测试完整计划",
                preferenceRevisionCode: preference.revisionCode,
                strengthWorkouts: [ProgramWorkoutDraft(code: "UI_A", title: "测试胸部 A", weekday: weekday,
                    exercises: [exerciseDraft], guidance: "热身不计工作组；未完成，不自动续排")],
                cardioWorkouts: [], progressionRule: "仅测试本周", lowEnergyRule: "状态不好则减量"))
        if let newIdentity {
            packet.catalogAdditions = [ConfirmedTrainingCatalogAddition(id: newIdentity, name: exerciseDraft.name,
                muscleGroup: exerciseDraft.muscleGroup, equipment: exerciseDraft.equipment,
                volumeUnitRaw: ExerciseVolumeUnit.kilogram.rawValue, defaultRestSeconds: exerciseDraft.restSeconds)]
            packet.catalogConfirmationReference = "ISOLATED-UI-TEST: exact test machine and kg, not owner data"
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(packet).write(to: fileURL, options: .atomic)
    }

    private static func prepareDailyPrefill(in context: ModelContext) throws {
        let day = TrainingLocalDate.key(.now)
        let date = MealLocalDay.date(day, timeZone: TimeZone(identifier: "Asia/Shanghai")!)!
        guard let preference = try TrainingPreferenceService.current(in: context, on: date) else { return }
        let exercise = Exercise(name: "预填测试推胸", muscleGroup: "胸部", equipment: "隔离测试器械")
        context.insert(exercise)
        try context.save()
        let targets = (0..<4).map { index in
            WorkoutSetPlan(weight: index == 0 ? 25 : 20, reps: index == 0 ? 8 : 10,
                weightSide: .single, repsSide: .bilateral, actualDefaultPolicy: .blank,
                prescription: WorkoutSetPrescription(label: index == 0 ? "顶组" : "回退组",
                    repsLower: index == 0 ? 8 : 10, repsUpper: index == 0 ? 10 : 12,
                    rirLower: 2, rirUpper: 3, restLowerSeconds: 150, restUpperSeconds: 180))
        }
        let source = "# 隔离建议预填测试\n逐组25/20/20/20；实际由本人确认完成。"
        var packet = ConfirmedDailyTrainingPlanPacket(version: 1, id: UUID(), localDay: day,
            timeZoneIdentifier: "Asia/Shanghai", title: "隔离R1", preferenceRevisionCode: preference.revisionCode,
            confirmedAt: .now.addingTimeInterval(-60), confirmationReference: "ISOLATED-DAILY-UI",
            sourceMarkdown: source, sourceSHA256: ConfirmedTrainingPlanService.digest(Data(source.utf8)),
            guidance: "热身另计；本人完成后确认；保持动作质量",
            exercises: [ConfirmedDailyPlanExercise(catalogExerciseID: exercise.id, catalogName: exercise.name,
                equipment: exercise.equipment, volumeUnit: .kilogram, displayName: exercise.name,
                loadGuidance: "每侧片重kg，不含器械初始阻力", notes: "可修改建议重量与次数", plannedSets: targets)])
        let original = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(packet, in: context), in: context)
        packet.id = UUID()
        packet.title = "隔离R2建议预填"
        packet.actualPrefillConfirmationReference = "ISOLATED-OWNER-PREFILL-CONFIRMATION"
        packet.replacement = ConfirmedDailyTrainingPlanReplacement(scheduleID: original.readback.schedule.id,
            packetSHA256: original.readback.packetSHA256)
        for index in packet.exercises[0].plannedSets.indices {
            packet.exercises[0].plannedSets[index].id = UUID()
            packet.exercises[0].plannedSets[index].actualDefaultPolicyRaw = "plan"
        }
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(packet, in: context), in: context)
    }
}
#endif
