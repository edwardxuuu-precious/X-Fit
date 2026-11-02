#if DEBUG
import Foundation
import SwiftData

@MainActor
enum TrainingCoachUITestFixture {
    static func prepare(in context: ModelContext) throws {
        guard CloudSyncRuntime.isTesting, CommandLine.arguments.contains("--ui-testing-coach-loop") else { return }
        guard try context.fetch(FetchDescriptor<WorkoutSession>()).allSatisfy({ $0.importIdentifier != "coach-ui-fixture" }) else { return }
        if CommandLine.arguments.contains("--ui-testing-home-plan-week"), CloudSyncRuntime.isUITesting,
           !CloudSyncRuntime.usesPersistentUITestStore {
            try prepareHomePlanWeek(in: context)
            return
        }
        let day = Date.now.startOfDay.addingDays(-2)
        var preference = TrainingPreferenceSnapshot.confirmed
        preference.revisionCode = "TP-COACH-UI"
        _ = try TrainingPreferenceService.append(snapshot: preference, effectiveAt: day.addingDays(-1), reason: "隔离UI测试", in: context)
        let session = WorkoutSession(templateName: "下肢综合 · 隔离测试", plannedDate: day,
            startedAt: day.addingTimeInterval(8 * 3600), completedAt: day.addingTimeInterval(9 * 3600),
            status: .completed, importIdentifier: "coach-ui-fixture")
        context.insert(session)
        var feedback = CoachFeedback(stage: "after", pain: "none")
        for (order, values) in [("测试腿举", 4, 60.0), ("测试腿屈伸", 3, 30.0)].enumerated() {
            let exercise = Exercise(name: values.0, muscleGroup: "腿部", equipment: "隔离测试器械")
            context.insert(exercise)
            let plans = (0..<values.1).map { _ in
                WorkoutSetPlan(weight: values.2, reps: 10, weightSide: .single, repsSide: .bilateral,
                    actualDefaultPolicy: .blank, prescription: WorkoutSetPrescription(label: "工作组", repsLower: 10, repsUpper: 12,
                        rirLower: 2, rirUpper: 3, restLowerSeconds: 90, restUpperSeconds: 120))
            }
            let item = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
                order: order, targetSets: plans.count, minReps: 10, maxReps: 12, targetWeight: values.2,
                restSeconds: 120, muscleGroup: exercise.muscleGroup, plannedSets: plans, equipmentSnapshot: exercise.equipment)
            context.insert(item)
            for (index, _) in plans.enumerated() {
                context.insert(SetLog(sessionID: session.id, sessionExerciseID: item.id, exerciseID: exercise.id,
                    setNumber: index + 1, targetWeight: values.2, targetReps: 10, actualWeight: values.2 + 5,
                    actualReps: 10, isCompleted: true, completedAt: day.addingTimeInterval(Double(8 * 3600 + index * 120)),
                    targetWeightSide: .single, targetRepsSide: .bilateral, actualEntrySource: .manual))
            }
            feedback.lastRIR[item.id.uuidString] = order == 0 ? 5 : 3
            feedback.loadConventions[item.id.uuidString] = "同机每侧加片，不含空载阻力"
        }
        try context.save()
        try TrainingCoachService.saveFeedback(feedback, sessionID: session.id, in: context)
        if CommandLine.arguments.contains("--ui-testing-coach-ready") {
            let morning = CoachFeedback(stage: "morning", pain: "none", function: "normal", recovery: "good")
            try TrainingCoachService.saveFeedback(morning, sessionID: session.id, in: context)
            let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
            let date = (3...20).map { Date.now.startOfDay.addingDays($0) }.first { candidate in
                schedules.allSatisfy { TrainingScheduleDate.localDay($0) != TrainingLocalDate.key(candidate) }
            }!
            _ = try TrainingCoachService.makeDraft(sessionID: session.id, date: date, in: context)
        }
        let meal = MealEntry(mealType: .lunch, name: "隔离示例餐食", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        meal.nutritionKnown = false
        context.insert(meal)
        if CommandLine.arguments.contains("--ui-testing-home-timeline") {
            // This fixture runs only in the explicitly gated, isolated UI-test store.
            for schedule in try context.fetch(FetchDescriptor<ScheduledWorkout>())
                where TrainingScheduleDate.localDay(schedule) > TrainingLocalDate.key(.now) {
                context.delete(schedule)
            }
            for (offset, name) in ["固定单车 · 稳定有氧35分钟 · R1", "背部＋二头 · R2建议预填 · 22组", "椭圆机 · 稳定有氧40分钟 · R1"].enumerated() {
                let plannedDate = Date.now.startOfDay.addingDays(offset + 1)
                let schedule = ScheduledWorkout(templateID: UUID(), templateName: name, plannedDate: plannedDate)
                schedule.plannedLocalDay = TrainingLocalDate.key(plannedDate)
                schedule.plannedTimeZoneIdentifier = TimeZone.current.identifier
                context.insert(schedule)
            }
        }
        try context.save()
        if CommandLine.arguments.contains("--ui-testing-cardio-menu") {
            // Keep this case about one chosen cardio plan, rather than the seed's same-day strength plan.
            for existing in try context.fetch(FetchDescriptor<ScheduledWorkout>())
                where TrainingScheduleDate.localDay(existing) == TrainingLocalDate.key(.now) && existing.status == .planned {
                context.delete(existing)
            }
            let exercise = Exercise(name: "固定单车", muscleGroup: "心肺", equipment: "单车", volumeUnit: .second)
            context.insert(exercise)
            let schedule = ScheduledWorkout(templateID: UUID(), templateName: "固定单车 · 稳定有氧35分钟 · R1",
                plannedDate: .now, planSnapshot: [.init(exerciseID: exercise.id, exerciseName: exercise.name,
                    muscleGroup: "心肺", equipment: "单车", exerciseNotes: "", referenceURL: "", volumeUnit: .second,
                    order: 0, targetSets: 1, minReps: 2_100, maxReps: 2_100, targetWeight: 0, restSeconds: 0,
                    plannedSets: [.init(weight: 0, reps: 2_100, actualDefaultPolicy: .blank)],
                    planPattern: .fixed, patternSource: .exerciseOverride)])
            context.insert(schedule); try context.save()
        }
        if CommandLine.arguments.contains("--ui-testing-date-menu") {
            // Legacy unknown ownership is deliberate. Only the isolated test store receives this row.
            context.insert(JumpRopeEntry(count: nil, durationSeconds: 480, date: .now))
            try context.save()
        }
        if CommandLine.arguments.contains("--ui-testing-superseded-menu") {
            try prepareSupersededMenu(in: context)
            return
        }
        if CommandLine.arguments.contains("--ui-testing-past-reschedule") {
            try preparePastReschedule(in: context)
            return
        }
        TrainingDateSelection.shared.select(localDay: TrainingLocalDate.key(
            CommandLine.arguments.contains("--ui-testing-home-timeline") ? .now : day))
    }

    private static func prepareHomePlanWeek(in context: ModelContext) throws {
        let today = Date.now.startOfDay
        let future = today.addingDays(7)
        for schedule in try context.fetch(FetchDescriptor<ScheduledWorkout>()) {
            context.delete(schedule)
        }
        let exercise = Exercise(name: "模板已修改动作", muscleGroup: "胸部", equipment: "器械")
        context.insert(exercise)
        let template = WorkoutTemplate(name: "后来修改的模板", weekday: 1)
        context.insert(template)
        context.insert(TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: 0,
            targetSets: 1, minReps: 3, maxReps: 3, targetWeight: 99, restSeconds: 30))
        let plan = ScheduledWorkoutExerciseSnapshot(exerciseID: exercise.id, exerciseName: "保存的计划动作",
            muscleGroup: "胸部", equipment: "器械", exerciseNotes: "保存的备注", referenceURL: "", volumeUnit: .kilogram,
            order: 0, targetSets: 2, minReps: 8, maxReps: 10, targetWeight: 25, restSeconds: 90,
            plannedSets: [.init(weight: 25, reps: 8, weightSide: .single, repsSide: .bilateral),
                .init(weight: 20, reps: 10, weightSide: .single, repsSide: .bilateral)],
            planPattern: .fixed, patternSource: .exerciseOverride)
        let uncalibrated = ScheduledWorkoutExerciseSnapshot(exerciseID: exercise.id, exerciseName: "待校准负重动作",
            muscleGroup: "胸部", equipment: "器械", exerciseNotes: "当天热身后校准", referenceURL: "", volumeUnit: .kilogram,
            order: 1, targetSets: 1, minReps: 6, maxReps: 6, targetWeight: 0, restSeconds: 90,
            plannedSets: [.init(weight: 0, reps: 6, weightSide: .unknown, repsSide: .unknown, actualDefaultPolicy: .blank)],
            planPattern: .fixed, patternSource: .exerciseOverride)
        let schedule = ScheduledWorkout(templateID: template.id, templateName: "下周保存计划", plannedDate: future,
            planSnapshot: CommandLine.arguments.contains("--ui-testing-saved-plan-cards") ? illustratedPlan() : [plan, uncalibrated])
        schedule.plannedLocalDay = TrainingLocalDate.key(future)
        schedule.plannedTimeZoneIdentifier = TimeZone.current.identifier
        context.insert(schedule)
        for offset in [-1, 1] {
            let empty = ScheduledWorkout(templateID: UUID(), templateName: "空计划", plannedDate: future.addingDays(offset))
            context.insert(empty)
        }
        if !CommandLine.arguments.contains("--ui-testing-home-plan-no-active") {
            let active = WorkoutSession(templateName: "其他日期活动训练", plannedDate: today.addingDays(-1),
                startedAt: today.addingDays(-1), status: .inProgress)
            context.insert(active)
            let item = SessionExercise(sessionID: active.id, exerciseID: exercise.id, exerciseName: "原会话保留动作",
                order: 0, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 10, restSeconds: 90)
            context.insert(item)
            context.insert(SetLog(sessionID: active.id, sessionExerciseID: item.id, exerciseID: exercise.id,
                setNumber: 1, targetWeight: 10, targetReps: 8, actualWeight: 12, actualReps: 9,
                isCompleted: true, actualEntrySource: .manual))
        }
        try context.save()
        TrainingDateSelection.shared.select(localDay: TrainingLocalDate.key(today))
    }

    private static func illustratedPlan() -> [ScheduledWorkoutExerciseSnapshot] {
        let identities: [(String, String, String)] = [
            ("8C2B39A3-8F47-413E-BC5F-93EC3CB313DA", "史密斯卧推，胸部主项", "史密斯机"),
            ("62B7E172-C76F-4502-8643-87249F7199E3", "器械上斜卧推，上胸推举", "器械"),
            ("2FFA02FD-85F0-4938-A9C9-59A3561C241E", "坐姿飞鸟，胸部夹胸", "器械"),
            ("8DE3EE03-A5A3-4767-954B-333D4BD17332", "站姿绳索夹胸，胸部夹胸", "龙门架"),
            ("57E855E6-E0AB-46FB-AE88-AED4ABF9144B", "史密斯肩推，肩前束", "史密斯机"),
            ("785412EA-AC6A-4910-9942-8C3B2E380CB8", "坐姿哑铃侧平举，肩中束", "哑铃"),
            ("67518BD0-1C2E-464C-8753-EB48E62581DB", "绳索反向飞鸟，肩后束", "龙门架"),
            ("9BB12534-10A3-435D-BE9A-10A70ED0616F", "器械坐姿侧平举，肩中束", "器械")
        ]
        return identities.enumerated().map { index, identity in
            let rest = [0, 1, 4].contains(index) ? 90 : 50
            let sets = [14, 12, 10, 8].enumerated().map { setIndex, reps in
                WorkoutSetPlan(weight: index == 0 ? Double(25 + setIndex * 5) : 0, reps: reps,
                    weightSide: index == 0 ? .single : .unknown, repsSide: .bilateral, actualDefaultPolicy: .blank,
                    prescription: WorkoutSetPrescription(label: setIndex == 3 ? "本组后条件递减，安全换片时执行" : "保存的条件目标",
                        repsLower: reps, repsUpper: reps, rirLower: 1, rirUpper: 2,
                        restLowerSeconds: rest, restUpperSeconds: rest,
                        effortCue: "疼痛、动作不稳或异常疲劳时停止或调整"))
            }
            return ScheduledWorkoutExerciseSnapshot(exerciseID: UUID(uuidString: identity.0)!, exerciseName: identity.1,
                muscleGroup: index < 4 ? "胸部" : "肩部", equipment: identity.2,
                exerciseNotes: "隔离测试保存的完整备注。不能安全快速换片时跳过递减，不同时做两种强化。", referenceURL: "",
                volumeUnit: .kilogram, order: index, targetSets: 4, minReps: 8, maxReps: 14, targetWeight: 0,
                restSeconds: rest, plannedSets: sets, planPattern: .pyramidUp, patternSource: .exerciseOverride)
        }
    }

    private static func prepareSupersededMenu(in context: ModelContext) throws {
        guard CloudSyncRuntime.isTesting, CloudSyncRuntime.isUITesting,
              !CloudSyncRuntime.usesPersistentUITestStore else { return }
        let today = TrainingLocalDate.key(.now)
        let tomorrow = TrainingLocalDate.key(Date.now.addingDays(1))
        for row in try context.fetch(FetchDescriptor<ScheduledWorkout>())
            where [today, tomorrow].contains(TrainingScheduleDate.localDay(row)) {
            context.delete(row)
        }
        let loadHistory = CommandLine.arguments.contains("--ui-testing-superseded-load-history")
        let exercise = Exercise(name: loadHistory ? "隔离原计划推胸" : "隔离菜单跳绳",
            muscleGroup: loadHistory ? "胸部" : "心肺", equipment: loadHistory ? "隔离推胸机" : "跳绳",
            volumeUnit: loadHistory ? .kilogram : .second)
        context.insert(exercise); try context.save()
        guard let preference = try TrainingPreferenceService.current(in: context) else { return }
        let target = WorkoutSetPrescription(label: "计划目标", repsLower: loadHistory ? 8 : 600, repsUpper: loadHistory ? 8 : 600,
            rirLower: nil, rirUpper: nil, restLowerSeconds: 60, restUpperSeconds: 60)
        let draft = ConfirmedDailyPlanExercise(catalogExerciseID: exercise.id, catalogName: exercise.name,
            equipment: exercise.equipment, volumeUnit: exercise.volumeUnit, displayName: exercise.name,
            loadGuidance: loadHistory ? "同机原计划，实际留空" : "按秒数记录", notes: "仅隔离UI测试",
            plannedSets: loadHistory ? [
                .init(weight: 20, reps: 8, weightSide: .single, repsSide: .bilateral, actualDefaultPolicy: .blank, prescription: target),
                .init(weight: 25, reps: 8, weightSide: .bilateral, repsSide: .unknown, actualDefaultPolicy: .blank, prescription: target)
            ] : [.init(weight: 0, reps: 600, actualDefaultPolicy: .blank, prescription: target)])
        let source = "隔离UI测试的确认修订链，不是真实训练数据。"
        for (day, suffix) in [(today, "81"), (tomorrow, "82")] {
            let oldID = UUID(uuidString: "F53446EA-1488-43C4-93BD-C6842CCD" + suffix + "01")!
            let currentID = UUID(uuidString: "F53446EA-1488-43C4-93BD-C6842CCD" + suffix + "02")!
            let original = ConfirmedDailyTrainingPlanPacket(version: 1, id: oldID, localDay: day,
                timeZoneIdentifier: TimeZone.current.identifier, title: "旧菜单跳绳",
                preferenceRevisionCode: preference.revisionCode, confirmedAt: .now.addingTimeInterval(-60),
                confirmationReference: "ISOLATED-UI-SUPERSEDED", sourceMarkdown: source,
                sourceSHA256: ConfirmedTrainingPlanService.digest(Data(source.utf8)),
                guidance: "只用于菜单与来源保留回归", exercises: [draft])
            _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
                ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
            var revision = original
            revision.id = currentID; revision.title = "当前菜单跳绳"
            revision.replacement = .init(scheduleID: oldID, packetSHA256: try ConfirmedTrainingPlanService.digest(original))
            _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
                ConfirmedDailyTrainingPlanService.preview(revision, in: context), in: context)
            if day == tomorrow {
                let old = try context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == oldID }!
                old.status = .planned
                try context.save()
            }
        }
        let template = WorkoutTemplate(name: "主动休息跳绳", weekday: Date.now.weekdayNumber, isActive: false, isOneOff: true)
        let voluntary = ScheduledWorkout(id: UUID(uuidString: "F53446EA-1488-43C4-93BD-C6842CCD8103")!,
            templateID: template.id, templateName: template.name, plannedDate: .now, isManuallyScheduled: true)
        voluntary.jumpRopePlan = .init(targetCount: 900, activeSeconds: nil, elapsedSeconds: nil, notes: "本人主动休息")
        context.insert(template); context.insert(voluntary); try context.save()
        _ = try ScheduleService.skipManaged(voluntary, reason: "本人主动休息", in: context)
        if CommandLine.arguments.contains("--ui-testing-superseded-actuals") {
            let oldID = UUID(uuidString: "F53446EA-1488-43C4-93BD-C6842CCD8101")!
            let actual = WorkoutSession(id: UUID(uuidString: "F53446EA-1488-43C4-93BD-C6842CCD8104")!,
                scheduledWorkoutID: oldID, templateName: "保留旧来源实际", plannedDate: .now,
                isStartTimeKnown: false, status: .completed)
            actual.trainingLocalDay = nil; actual.trainingTimeZoneIdentifier = nil
            let rope = JumpRopeEntry(id: UUID(uuidString: "F53446EA-1488-43C4-93BD-C6842CCD8105")!,
                count: 700, activeDurationSeconds: 480, date: .now)
            rope.scheduledWorkoutID = oldID
            context.insert(actual); context.insert(rope); try context.save()
        }
        TrainingDateSelection.shared.select(localDay: today)
    }

    private static func preparePastReschedule(in context: ModelContext) throws {
        guard CloudSyncRuntime.isTesting, CommandLine.arguments.contains("--ui-testing") else { return }
        let arguments = CommandLine.arguments
        let offset = arguments.contains("--ui-testing-past-reschedule-today") ? 0
            : arguments.contains("--ui-testing-past-reschedule-future") ? 1 : -1
        let date = Date.now.startOfDay.addingDays(offset)
        let localDay = TrainingLocalDate.key(date)
        // Keep the source deterministic; retain today's seed plan to cover a real multi-plan destination.
        for schedule in try context.fetch(FetchDescriptor<ScheduledWorkout>())
            where TrainingScheduleDate.localDay(schedule) == localDay {
            context.delete(schedule)
        }
        let strength = arguments.contains("--ui-testing-past-reschedule-strength")
        let rope = arguments.contains("--ui-testing-past-reschedule-rope")
        let exercise = Exercise(name: strength ? "测试哑铃划船" : "固定单车", muscleGroup: strength ? "背部" : "心肺",
            equipment: strength ? "哑铃" : "单车", volumeUnit: strength ? .kilogram : .second)
        context.insert(exercise)
        let plan = ScheduledWorkout(id: UUID(uuidString: "F53446EA-1488-43C4-93BD-C6842CCD8101")!,
            templateID: UUID(), templateName: rope ? "跳绳" : strength ? "背部 · 隔离改期力量" : "固定单车 · 稳定有氧40分钟 · R1",
            plannedDate: date, isManuallyScheduled: true,
            planSnapshot: rope ? [] : [.init(exerciseID: exercise.id, exerciseName: exercise.name,
                muscleGroup: exercise.muscleGroup, equipment: exercise.equipment, exerciseNotes: "保留原训练内容",
                referenceURL: "", volumeUnit: exercise.volumeUnit, order: 0, targetSets: strength ? 3 : 1,
                minReps: strength ? 8 : 2_400, maxReps: strength ? 10 : 2_400,
                targetWeight: strength ? 20 : 0, restSeconds: strength ? 90 : 0,
                plannedSets: (0..<(strength ? 3 : 1)).map { _ in
                    .init(weight: strength ? 20 : 0, reps: strength ? 10 : 2_400, actualDefaultPolicy: .blank)
                }, planPattern: .fixed, patternSource: .exerciseOverride)])
        if rope {
            plan.jumpRopePlan = .init(targetCount: 1_200, activeSeconds: 480, elapsedSeconds: 600, notes: "保留原跳绳目标")
        }
        context.insert(plan)
        let other = ScheduledWorkout(id: UUID(uuidString: "F53446EA-1488-43C4-93BD-C6842CCD8102")!,
            templateID: UUID(), templateName: "椭圆机 · 稳定有氧20分钟 · 同日另一场",
            plannedDate: date, isManuallyScheduled: true)
        // Home sorts by plannedDate. Keep the primary plan ahead without changing civil ownership.
        other.plannedDate = date.addingTimeInterval(60)
        context.insert(other)
        if arguments.contains("--ui-testing-past-reschedule-started")
            || arguments.contains("--ui-testing-past-reschedule-actual") {
            let actual = arguments.contains("--ui-testing-past-reschedule-actual")
            let session = WorkoutSession(scheduledWorkoutID: plan.id, templateID: plan.templateID,
                templateName: plan.templateName, plannedDate: date, startedAt: date.addingTimeInterval(8 * 3_600),
                completedAt: actual ? date.addingTimeInterval(9 * 3_600) : nil,
                status: actual ? .completed : .inProgress, importIdentifier: "past-reschedule-ui-fixture")
            session.trainingLocalDay = localDay
            session.trainingTimeZoneIdentifier = TimeZone.current.identifier
            // Deliberately retain planned for the actual case: a linked record alone must protect it.
            if !actual { plan.status = .inProgress }
            context.insert(session)
        }
        try context.save()
        TrainingDateSelection.shared.select(localDay: localDay)
    }
}
#endif
