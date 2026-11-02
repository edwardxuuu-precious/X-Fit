import Foundation
import SwiftData

@MainActor
enum CoachWeekService {
    static let legacyMethodVersion = "METHOD-20261028-11"
    static let methodVersion = "METHOD-20261029-12"
    static let alternatingMethodVersion = "METHOD-20261030-13"
    private static func modern(_ version: String) -> Bool { version == methodVersion || version == alternatingMethodVersion }
    static let personalRuleVersion = "PERSONAL-20261028-01"
    static let overlapRuleVersion = "PERSONAL-20261028-02"
    static let coreExceptionConsent = "本人明确确认本周腹部目标可少于4个动作"
    static let pastRestConsent = "本人明确核对该过去日期为休息"
    private static let ruleRootID = UUID(uuidString: "78283952-B6AC-4B03-B215-76864BE804D1")!
    private static let roles: [String: [String]] = [
        "machine_incline_chest_press": ["水平推"], "machine_decline_chest_press": ["水平推"],
        "standing_cable_chest_fly": ["胸内收"], "machine_pec_deck_fly": ["胸内收"],
        "machine_shoulder_press": ["垂直推"], "seated_dumbbell_shoulder_press": ["垂直推"],
        "cable_triceps_pushdown": ["肘伸"], "machine_triceps_press": ["肘伸"],
        "machine_reverse_fly": ["肩水平外展"], "landmine_zercher_squat": ["膝主导"],
        "barbell_conventional_deadlift": ["髋铰链", "髋伸"], "barbell_hip_thrust": ["髋伸"],
        "dumbbell_side_lunge": ["侧向单腿"]
    ]

    // Exact pairs identify a movement role, not a canonical or personal-record identity.
    private static let seedRoles: [String: [String]] = [
        "史密斯卧推|史密斯机": ["水平推"], "杠铃卧推|杠铃": ["水平推"], "上斜哑铃卧推|哑铃": ["水平推"],
        "器械坐姿推胸|器械": ["水平推"], "蝴蝶机夹胸|器械": ["胸内收"],
        "锤式弯举|哑铃": ["肘屈"], "绳索过顶臂屈伸|龙门架": ["肘伸"], "坐姿推举|哑铃": ["垂直推"], "绳索下压|龙门架": ["肘伸"],
        "高位下拉|器械": ["垂直拉"], "坐姿划船|器械": ["水平拉"],
        "面拉|龙门架": ["肩水平外展"], "哑铃弯举|哑铃": ["肘屈"],
        "深蹲|杠铃": ["膝主导"], "罗马尼亚硬拉|杠铃": ["髋铰链"],
        "腿举|器械": ["膝主导"], "站姿提踵|器械": ["踝跖屈"],
        "杠铃划船|杠铃": ["水平拉"], "引体向上|自重": ["垂直拉"],
        "坐姿腿弯举|器械": ["屈膝"], "腿屈伸|器械": ["伸膝"],
        "MTS 下斜卧推|器械": ["水平推"], "MTS器械下斜推胸|MTS下斜推胸机": ["水平推"],
        "器械上斜推胸|器械": ["水平推"], "站姿绳索夹胸|龙门架": ["胸内收"],
        "MTS 划船|MTS 器械": ["水平拉"], "胸托T-Bar划船|胸托T-Bar划船机": ["水平拉"],
        "胸托划船|器械或哑铃": ["水平拉"], "胸托划船|器械": ["水平拉"],
        "双滑轮高位下拉|双滑轮器械": ["垂直拉"], "双滑轮低位划船|双滑轮器械": ["水平拉"], "中立握高位下拉|器械": ["垂直拉"], "双滑轮高位下拉|器械": ["垂直拉"],
        "直臂下压|龙门架": ["肩伸"], "绳索直臂下压|龙门架": ["肩伸"],
        "上斜凳胸托哑铃划船|哑铃": ["水平拉"], "单臂哑铃划船|哑铃": ["水平拉", "单侧"],
        "哑铃侧平举|哑铃": ["肩外展"], "绳索侧平举|龙门架": ["肩外展", "单侧"],
        "反向飞鸟|器械": ["肩水平外展"], "器械反向飞鸟|器械": ["肩水平外展"],
        "器械肩推|器械": ["垂直推"], "坐姿哑铃肩上推举|哑铃": ["垂直推"],
        "坐姿哑铃侧平举|哑铃": ["肩外展"], "绳索面拉|龙门架": ["肩水平外展"],
        "器械臀推|臀推机": ["髋伸"], "器械臀推|器械臀推机": ["髋伸"],
        "器械臀推|器械": ["髋伸"], "杠铃臀推|杠铃": ["髋伸"],
        "坐姿腿弯举|坐姿腿弯举机": ["屈膝"], "腿屈伸|腿屈伸机": ["伸膝"],
        "哈克深蹲|哈克深蹲机": ["膝主导"], "保加利亚分腿蹲|哑铃": ["单腿"],
        "反向箭步蹲|哑铃": ["单腿"], "扶架单手哑铃反向箭步蹲|哑铃": ["单腿"],
        "双手髋铰链壶铃摆动|壶铃": ["髋伸速度", "技术"],
        "罗马椅髋伸|罗马椅＋可选负重片": ["后侧控制"],
        "臀桥脚跟走步|地垫": ["屈膝", "髋伸控制"],
        "双手壶铃摆动|壶铃": ["髋伸速度", "技术"],
        "罗马椅髋伸与后侧控制|罗马椅": ["后侧控制"],
        "臀桥脚跟走步|自重": ["屈膝", "髋伸控制"]
    ]

    private static let addedCanonicalRoles: [String: [String]] = [
        "cable_crunch": ["腹部", "躯干屈曲"],
        "cable_trunk_rotation": ["腹部", "侧腹", "单侧"]
    ]
    private static let addedSeedRoles: [String: [String]] = [
        "MTS 卧推|MTS 器械": ["水平推"], "上斜卧推|杠铃": ["水平推"],
        "史密斯上斜卧推|史密斯机": ["水平推"], "器械上斜卧推|器械": ["水平推"],
        "器械下斜卧推|器械": ["水平推"], "传统硬拉|杠铃": ["髋铰链", "髋伸"],
        "钟摆深蹲|器械": ["膝主导"], "颈前深蹲|杠铃": ["膝主导"],
        "反向蝴蝶机|器械": ["肩水平外展"], "哑铃反向飞鸟|哑铃": ["肩水平外展"],
        "哑铃站姿反向飞鸟|哑铃": ["肩水平外展"], "器械坐姿反向飞鸟|器械": ["肩水平外展"],
        "绳索反向飞鸟|龙门架": ["肩水平外展"], "器械坐姿侧平举|器械": ["肩外展"],
        "哑铃站姿侧平举|哑铃": ["肩外展"],
        "绳索卷腹|龙门架": ["腹部", "躯干屈曲"], "绳索跪姿卷腹|龙门架": ["腹部", "躯干屈曲"],
        "负重仰卧起坐|负重片": ["腹部", "躯干屈曲"], "仰卧反向卷腹|自重": ["腹部", "躯干屈曲"],
        "绳索躯干旋转|龙门架": ["腹部", "侧腹", "单侧"],
        "垫高绳索站姿侧屈|龙门架": ["腹部", "侧腹", "单侧"],
        "站姿水平伐木|龙门架": ["腹部", "侧腹", "单侧"],
        "绳索伸展转体|龙门架": ["腹部", "侧腹", "单侧"],
        "地雷杆转体|地雷杆": ["腹部", "侧腹", "单侧"],
        "杠铃片过头侧屈（单边）|杠铃片": ["腹部", "侧腹", "单侧"]
    ]

    static func roleEvidence(name: String, equipment: String, canonicalID: String?, exerciseID: UUID? = nil,
                             ruleMethod: String? = nil) -> (roles: [String], source: String) {
        let method = ruleMethod ?? methodVersion
        let canonical = canonicalID.flatMap { roles[$0] ?? (modern(method) ? addedCanonicalRoles[$0] : nil) }
        let clarified: [String]?
        if exerciseID?.uuidString.lowercased() == "0fcd2a94-feb5-4433-abee-50750a249bb4", name == "Hip and glute machine" {
            clarified = ["髋外展"]
        } else if exerciseID?.uuidString.lowercased() == "fc230b90-0405-492d-bf30-4c391c803578", name == "Abductor machine" {
            clarified = ["髋内收"]
        } else { clarified = nil }
        if let clarified {
            if let canonical, Set(canonical) != Set(clarified) { return ([], "未知：已确认术语与本人实际方向冲突") }
            return (clarified, "本人10/26对该动作UUID的方向澄清 · 力量表现档案08；不合并身份或推断同机")
        }
        let key = "\(name)|\(equipment)"
        let alternatingRoles: [String: [String]] = ["Smith Bench Press|史密斯机": ["水平推"]]
        let pair = seedRoles[key] ?? (modern(method) ? addedSeedRoles[key] : nil)
            ?? (method == alternatingMethodVersion ? alternatingRoles[key] : nil)
        if let canonical, let pair, Set(canonical) != Set(pair) {
            return ([], "未知：术语角色与名称器械定义冲突")
        }
        if let canonical { return (canonical, "已确认术语 \(canonicalID!) · \(method)") }
        if let pair { return (pair, "受控名称与器械定义 · \(method)；不代表术语或个人纪录身份已确认") }
        return ([], "未知：缺少明确角色定义")
    }

    static func defaultGoals(start: Date, zone: TimeZone, ruleMethod: String = methodVersion) -> [CoachWeekGoal] {
        let days = dateKeys(start: start, zone: zone)
        guard days.count == 7 else { return [] }
        let definitions: [(CoachWeekDayKind, String)] = [
            (.strength, "胸"), (.strength, "背"), (.cardio, "跳绳"),
            (.strength, "腿"), (.strength, "肩"), (.rest, ""), (.rest, "")
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return days.compactMap { day in
            guard let date = TrainingLocalDate.date(day, timeZone: zone) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            var value = definitions[(weekday + 5) % 7]
            if ruleMethod == alternatingMethodVersion, let anchor = TrainingLocalDate.date("2026-11-02", timeZone: zone) {
                let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
                let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
                let weeks = (calendar.dateComponents([.day], from: anchorWeek, to: week).day ?? 0) / 7
                let upper = weeks.isMultiple(of: 2)
                let alternating: [(CoachWeekDayKind, String)] = [(.strength, upper ? "胸肩" : "前链"), (.cardio, "跳绳"),
                    (.strength, upper ? "背腹" : "后链"), (.cardio, "Zone 2"),
                    (.strength, upper ? "胸背肩综合" : "腿部综合"), (.rest, ""), (.rest, "")]
                value = alternating[(weekday + 5) % 7]
            }
            return CoachWeekGoal(localDay: day, kind: value.0, focus: value.1,
                                 reason: ruleMethod == alternatingMethodVersion
                                    ? "长期默认候选；每周三次力量、两次有氧，周末休息，不默认同日分课；保留已有安排并核对恢复。"
                                    : "长期默认候选；周末休息且不默认同日分课，未排有氧缺额待本人决定；保留已有安排并核对恢复。")
        }
    }

    static func requiresAnkleAttachment(name: String, equipment: String) -> Bool {
        let label = name.lowercased()
        let device = equipment.lowercased()
        if [label, device].contains(where: { $0.contains("踝带") || $0.contains("ankle") }) { return true }
        let cable = [label, device].contains { value in ["绳索", "cable", "龙门架", "拉力器"].contains(where: value.contains) }
        let lowerLimb = ["后踢", "踢腿", "kickback", "髋外展", "hip abduction", "腿外展", "髋内收", "hip adduction", "腿内收"].contains(where: label.contains)
        return cable && lowerLimb
    }

    static func dateKeys(start: Date, zone: TimeZone) -> [String] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let start = calendar.startOfDay(for: start)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .map { TrainingLocalDate.key($0, timeZone: zone) }
    }

    private static func validCoreException(_ exception: CoachWeekCoreException, days: [String]) -> Bool {
        days.count == 7 && exception.startDay == days.first && exception.endDay == days.last
            && Set(exception.goals.map(\.localDay)) == Set(days)
            && exception.goals.count == days.count
            && !exception.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !exception.confirmation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && exception.confirmation == coreExceptionConsent
    }

    private static func validCoreExceptionScope(_ exception: CoachWeekCoreException, zone: TimeZone) -> Bool {
        guard let first = TrainingLocalDate.date(exception.startDay, timeZone: zone) else { return false }
        return validCoreException(exception, days: dateKeys(start: first, zone: zone))
    }

    private static func validCapturedDay(_ input: CoachWeekInput) -> Bool {
        guard let zone = TimeZone(identifier: input.timeZone), let captured = input.capturedLocalDay,
              let date = TrainingLocalDate.date(captured, timeZone: zone) else { return false }
        return TrainingLocalDate.key(date, timeZone: zone) == captured
    }

    private static func validPastRestReview(_ day: CoachWeekDay, input: CoachWeekInput) -> Bool {
        guard modern(input.methodVersion), let captured = input.capturedLocalDay, day.localDay < captured,
              day.kind == .rest, let review = day.pastRestReview, review.localDay == day.localDay,
              review.confirmation == pastRestConsent, !review.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !input.existing.contains(where: { $0.localDay == day.localDay })
            && !input.history.contains(where: { $0.localDay == day.localDay })
    }

    static func capture(start: Date, exception: CoachWeekException?, coreException: CoachWeekCoreException? = nil, now: Date = .now, retainedReviews: [CoachWeekRetainedReview]? = nil, validateRetainedReviewBindings: Bool = true, ruleMethod: String = methodVersion,
                        in context: ModelContext) throws -> CoachWeekInput {
        let zone = TimeZone.current
        let days = dateKeys(start: start, zone: zone)
        guard days.count == 7 else { throw TrainingCoachError.invalid("无法确定七个本地日期。") }
        if let exception {
            guard exception.startDay <= exception.endDay,
                  !exception.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !exception.confirmation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(exception.goals.map(\.localDay)).count == exception.goals.count,
                  exception.goals.allSatisfy({ $0.localDay >= exception.startDay && $0.localDay <= exception.endDay }) else {
                throw TrainingCoachError.invalid("例外须有明确有效期、原因和本人确认，且每日目标不能重复或越期。")
            }
        }
        if let coreException, !validCoreExceptionScope(coreException, zone: zone) {
            throw TrainingCoachError.invalid("腹部目标例外须限定本周七日，填写原因并明确确认。")
        }
        let preferences = try days.map { day -> CoachWeekPreference in
            let date = TrainingLocalDate.date(day, timeZone: zone)!
            let row = try TrainingPreferenceService.current(in: context, on: date)
            return CoachWeekPreference(localDay: day, revisionID: row?.id, code: row?.revisionCode, snapshot: row?.snapshot)
        }
        let catalog = try context.fetch(FetchDescriptor<Exercise>()).map { row in
            let role = roleEvidence(name: row.name, equipment: row.equipment, canonicalID: row.approvedCanonicalID, exerciseID: row.id, ruleMethod: ruleMethod)
            let found = role.roles
            return CoachWeekCatalogItem(id: row.id, name: row.name, muscle: row.muscleGroup,
                equipment: row.equipment, unit: row.volumeUnit, approvedCanonicalID: row.approvedCanonicalID,
                approvedName: row.approvedStandardNameZH, archived: row.isArchived, roles: found,
                roleSource: role.source)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let allSchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let schedules = allSchedules.filter { TrainingScheduleDate.localDay($0) >= days[0] && TrainingScheduleDate.localDay($0) <= days[6] }
        func scheduleInput(_ schedule: ScheduledWorkout, source: String) throws -> CoachWeekExisting {
            let content = [schedule.templateID.uuidString, schedule.planSnapshotJSON ?? "<missing>",
                           schedule.jumpRopePlanJSON ?? "<missing>", schedule.confirmedDailyImportJSON ?? "<missing>",
                           schedule.plannedTimeZoneIdentifier ?? "<missing>", schedule.plannedLocalDay ?? "<missing>"]
            return CoachWeekExisting(id: schedule.id, localDay: TrainingScheduleDate.localDay(schedule), title: schedule.templateName,
                                     status: schedule.statusRaw, source: source,
                                     contentDigest: try ConfirmedTrainingPlanService.digest(content),
                                     confirmedPacketDigest: schedule.confirmedDailyImportJSON == nil ? nil : try ConfirmedDailyTrainingPlanService.readback(id: schedule.id, in: context)?.packetSHA256,
                                     exerciseIDs: schedule.planSnapshot.isEmpty ? nil : schedule.planSnapshot.map(\.exerciseID),
                                     knownCardio: schedule.jumpRopePlan != nil || CardioWorkoutPresentation.plan(schedule) != nil ? true : nil,
                                     cardioMode: schedule.jumpRopePlan != nil ? "跳绳" : (CardioWorkoutPresentation.plan(schedule) != nil ? "Zone 2" : nil),
                                     frozenExercises: schedule.planSnapshot.map { item in
                                         CoachWeekFrozenExercise(exerciseID: item.exerciseID, name: item.exerciseName, muscle: item.muscleGroup,
                                             equipment: item.equipment, roles: roleEvidence(name: item.exerciseName, equipment: item.equipment, canonicalID: nil, exerciseID: item.exerciseID, ruleMethod: ruleMethod).roles,
                                             plannedSets: item.plannedSets)
                                     })
        }
        var existing = try schedules.map { try scheduleInput($0, source: "日程") }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let startDate = TrainingLocalDate.date(days[0], timeZone: zone)!
        var localCalendar = Calendar(identifier: .gregorian); localCalendar.timeZone = zone
        let boundaryStart = TrainingLocalDate.key(localCalendar.date(byAdding: .day, value: -2, to: startDate)!, timeZone: zone)
        let boundaryEnd = TrainingLocalDate.key(localCalendar.date(byAdding: .day, value: 8, to: startDate)!, timeZone: zone)
        let cutoff = now
        let lower = min(now, startDate).addingTimeInterval(-180 * 86400)
        let historySessions = sessions.filter {
            $0.status == .completed && $0.plannedDate >= lower && $0.plannedDate < cutoff
                && ($0.completedAt.map { $0 <= cutoff } ?? true)
        }
        let relevantSessions = Set(historySessions.map(\.id))
        let allSnapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let snapshots = allSnapshots.filter { relevantSessions.contains($0.sessionID) }
        let logs = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.reductionOrder == nil }
        let coachRows = try context.fetch(FetchDescriptor<TrainingCoachRecord>()).filter { $0.createdAt <= now }
        let history = snapshots.compactMap { row -> CoachWeekActual? in
            guard let session = historySessions.first(where: { $0.id == row.sessionID }) else { return nil }
            let day = TrainingHistoryDate.localDay(session)
            let feedback = (try? TrainingCoachService.latestFeedback("after", rows: TrainingCoachService.ordered(coachRows.filter { $0.sessionID == session.id })))
            let actual = logs.filter { $0.sessionExerciseID == row.id && $0.sessionID == session.id }.sorted { $0.setNumber < $1.setNumber }.map {
                CoachActualSet(id: $0.id, weight: $0.isActualWeightBlank ? nil : $0.actualWeight, reps: $0.actualReps, rir: $0.rir,
                    weightSide: $0.actualWeightSideRaw == nil ? .unknown : $0.actualWeightSide,
                    repsSide: $0.actualRepsSideRaw == nil ? .unknown : $0.actualRepsSide, completed: $0.isCompleted, warmup: $0.isWarmup)
            }
            let convention = feedback?.loadConventions[row.id.uuidString]
            let unknownClassification = session.importIdentifier.lowercased().contains("notes") || row.exerciseNotes.contains("Notes")
            return CoachWeekActual(id: row.id, sessionID: session.id, localDay: day, exerciseID: row.exerciseID,
                name: row.exerciseName, equipment: row.equipmentSnapshot, unit: row.volumeUnit, plannedSets: row.plannedSetsJSON.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([WorkoutSetPlan].self, from: $0) } ?? [],
                actual: actual, feedback: [row.performanceNotes, feedback?.note ?? ""].filter { !$0.isEmpty }.joined(separator: "；"),
                loadConvention: convention, feelingRaw: row.feelingRaw,
                supplementaryLastRIR: feedback?.lastRIR[row.id.uuidString], classificationKnown: !unknownClassification,
                scheduledWorkoutID: session.scheduledWorkoutID,
                supplementaryLastSetID: logs.filter { $0.sessionExerciseID == row.id && $0.sessionID == session.id && $0.isCompleted && !$0.isWarmup }.max(by: { $0.setNumber < $1.setNumber })?.id,
                actualSetNumbers: logs.filter { $0.sessionExerciseID == row.id && $0.sessionID == session.id }.sorted { $0.setNumber < $1.setNumber }.map(\.setNumber))
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        for session in sessions where session.status != .discarded {
            let day = TrainingHistoryDate.localDay(session)
            guard day >= boundaryStart && day <= boundaryEnd else { continue }
            let sessionSnapshots = allSnapshots.filter { $0.sessionID == session.id }.sorted { $0.id.uuidString < $1.id.uuidString }
            let snapshotDetails = sessionSnapshots.map { item in
                [item.id.uuidString, item.exerciseID.uuidString, item.exerciseName, item.equipmentSnapshot ?? "<unknown>",
                 item.volumeUnit.rawValue, item.plannedSetsJSON ?? "<missing>", item.feelingRaw ?? "<unknown>", item.performanceNotes].joined(separator: "|")
            }
            let setDetails = logs.filter { $0.sessionID == session.id }.sorted { $0.id.uuidString < $1.id.uuidString }.map { set in
                [set.id.uuidString, set.sessionExerciseID.uuidString, String(set.actualWeight), String(set.actualReps),
                 set.rir.map(String.init) ?? "<unknown>", set.actualWeightSideRaw ?? "<unknown>", set.actualRepsSideRaw ?? "<unknown>",
                 String(set.isCompleted), String(set.isWarmup), String(set.isActualWeightBlank)].joined(separator: "|")
            }
            let details = [session.notes, session.importIdentifier, session.scheduledWorkoutID?.uuidString ?? "<none>"] + snapshotDetails + setDetails
            existing.append(CoachWeekExisting(id: session.id, localDay: day, title: session.templateName, status: session.statusRaw,
                                              source: "实际训练", contentDigest: try ConfirmedTrainingPlanService.digest(details),
                                              actualBaselineJSON: session.status == .inProgress ? try ConfirmedDailyTrainingPlanService.coachActualBaseline(session, in: context) : nil,
                                              exerciseIDs: sessionSnapshots.isEmpty ? nil : sessionSnapshots.map(\.exerciseID),
                                              frozenExercises: sessionSnapshots.map { item in
                                                  CoachWeekFrozenExercise(exerciseID: item.exerciseID, name: item.exerciseName, muscle: item.muscleGroup,
                                                      equipment: item.equipmentSnapshot ?? "", roles: roleEvidence(name: item.exerciseName, equipment: item.equipmentSnapshot ?? "", canonicalID: nil, exerciseID: item.exerciseID, ruleMethod: ruleMethod).roles,
                                                      plannedSets: item.plannedSetsJSON.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([WorkoutSetPlan].self, from: $0) } ?? [])
                                              }))
        }
        let future = allSchedules.filter { (TrainingScheduleDate.localDay($0) > days[6] || TrainingScheduleDate.localDay($0) < days[0]) && TrainingScheduleDate.localDay($0) >= boundaryStart && TrainingScheduleDate.localDay($0) <= boundaryEnd && $0.status != .skipped }
        existing += try future.map { try scheduleInput($0, source: "临近周边界安排") }
        existing.sort { $0.id.uuidString < $1.id.uuidString }
        let recovery = try context.fetch(FetchDescriptor<DailyBodyCheckIn>()).filter {  $0.createdAt <= now && $0.updatedAt <= now && $0.date >= lower && $0.date < cutoff }.sorted { $0.date < $1.date }.suffix(7).map {
            "\(TrainingLocalDate.key($0.date, timeZone: zone))：体感分数\($0.conditionScore)；\($0.discomfortNotes.isEmpty ? "体感细节未记录" : $0.discomfortNotes)；身体标记\($0.bodyMarkersJSON ?? "未记录")"
        }
        let bodyReports = try context.fetch(FetchDescriptor<DailyBodyCheckIn>()).filter { $0.createdAt <= now && $0.updatedAt <= now && $0.date <= now && $0.date >= lower }.map {
            CoachWeekBodyReport(id: $0.id, localDay: TrainingLocalDate.key($0.date, timeZone: zone), capturedAt: $0.updatedAt,
                note: $0.discomfortNotes, hasBodyMarkers: !$0.bodyMarkers.isEmpty)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let signals = try coachRows.filter { ["after", "morning"].contains($0.kind) }.compactMap { row -> CoachWeekRecoverySignal? in
            guard let session = sessions.first(where: { $0.id == row.sessionID }), session.status != .discarded else { return nil }
            return CoachWeekRecoverySignal(id: row.id, sessionID: session.id, trainingDay: TrainingHistoryDate.localDay(session),
                capturedAt: row.createdAt, feedback: try TrainingCoachService.decode(CoachFeedback.self, row), sequence: row.sequence)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        for review in validateRetainedReviewBindings ? (retainedReviews ?? []) : [] {
            guard let entry = existing.first(where: { $0.id == review.existingID && $0.localDay == review.localDay }),
                  try retainedSourceDigest(entry) == review.sourceDigest, !review.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validReviewTarget(kind: review.kind, focus: review.focus), !reviewConflicts(entry, kind: review.kind, focus: review.focus), review.confirmedAt <= now else {
                throw TrainingCoachError.invalid("保留安排核对的来源或期限已变化，请重新审阅该安排。")
            }
        }
        return CoachWeekInput(startDay: days[0], timeZone: zone.identifier, methodVersion: ruleMethod,
            personalRuleVersion: try activeRuleVersion(in: context), preferences: preferences, exception: exception,
            catalog: catalog, history: history, existing: existing, recovery: Array(recovery),
            unknowns: ["缺记录不等于未训练；历史器械缺快照时不由当前目录补写。", "恢复、器械可用性和动作当前接受程度须本人核实。", "本人当前无踝带；不得自动安排需要踝带的动作。"],
            sourceRuleVersions: ["SESSION-PREF-20261026-01", "COACH-DEFAULT-20261026-02", "CARDIO-PREF-20261026-01", "EXERCISE-PREF-20261020-01", "SET-PREF-20261016-01", "COACH-PREF-20261021-01", "CONTEXT-PREF-20261025-01", "WEEK-PREF-20261028-01", "STRENGTH-CORE-PREF-20261029-01"] + (ruleMethod == alternatingMethodVersion ? ["ALTERNATING-PREF-20261030-01"] : []), supportedFromDay: "2026-10-26", recoverySignals: signals, bodyReports: bodyReports, retainedReviews: retainedReviews, coreException: coreException,
            capturedLocalDay: TrainingLocalDate.key(now, timeZone: zone))
    }

    static func fingerprint(_ input: CoachWeekInput) throws -> String {
        try ConfirmedTrainingPlanService.digest(input)
    }

    static func generate(input: CoachWeekInput, goals: [CoachWeekGoal], now: Date = .now, honorException: Bool = true) throws -> CoachWeekDraft {
        guard [legacyMethodVersion, methodVersion, alternatingMethodVersion].contains(input.methodVersion) else {
            throw TrainingCoachError.invalid("不支持的编排方法版本，不能生成或回放。")
        }
        guard let zone = TimeZone(identifier: input.timeZone), let start = TrainingLocalDate.date(input.startDay, timeZone: zone) else { throw TrainingCoachError.invalid("周日期或时区无效。") }
        if modern(input.methodVersion) {
            guard validCapturedDay(input) else { throw TrainingCoachError.invalid("输入采集日未知，不能为过去日期生成计划。") }
        }
        let keys = dateKeys(start: start, zone: zone)
        if let coreException = input.coreException {
            guard modern(input.methodVersion), validCoreExceptionScope(coreException, zone: zone) else {
                throw TrainingCoachError.invalid("腹部目标例外须限定本周七日，填写原因并明确确认。")
            }
        }
        guard Set(goals.map(\.localDay)).count == goals.count, goals.allSatisfy({ keys.contains($0.localDay) }) else { throw TrainingCoachError.invalid("每日目标重复或超出所选周。") }
        var effectiveGoals = goals
        // Reassign only untouched default goals. Unknown preserved activities stay unknown.
        if (input.exception == nil || input.exception!.endDay < keys[0] || input.exception!.startDay > keys[6]) && goals.count == 7 && goals.allSatisfy({ $0.reason.hasPrefix("长期默认候选") }) {
            func preservedKind(_ day: String) -> CoachWeekDayKind? {
                let rows = input.existing.filter { $0.localDay == day && isActive($0) }
                guard !rows.isEmpty else { return nil }
                if rows.contains(where: { retainedReview($0, input: input)?.kind == .strength || $0.frozenExercises?.contains { !$0.roles.isEmpty } == true }) { return .strength }
                if rows.allSatisfy({ preservedCardioMode($0, input: input) != nil }) { return .cardio }
                if rows.allSatisfy({ retainedReview($0, input: input)?.kind == .rest }) { return .rest }
                return nil
            }
            let occupied = keys.filter { day in input.existing.contains { $0.localDay == day } }
            if occupied.allSatisfy({ preservedKind($0) != nil && (preservedKind($0) != .strength || preservedFocus(on: $0, input: input) != nil) }) {
                var remaining = goals
                var assigned: [String: CoachWeekGoal] = [:]
                var possible = true
                for day in occupied {
                    let kind = preservedKind(day)!
                    let mode = input.existing.filter { $0.localDay == day }.compactMap { preservedCardioMode($0, input: input) }.first
                    let focus = kind == .strength ? preservedFocus(on: day, input: input) : mode
                    let match: (CoachWeekGoal) -> Bool = { $0.kind == kind && $0.focus == focus }
                    guard let index = remaining.firstIndex(where: match) ?? remaining.firstIndex(where: { $0.localDay == day }) else { possible = false; break }
                    remaining.remove(at: index)
                    assigned[day] = CoachWeekGoal(localDay: day, kind: kind, focus: focus ?? "",
                                                  reason: "保留已有安排，计入对应类型。")
                }
                let freeDays = keys.filter { !occupied.contains($0) }
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                var bestScore = Int.max
                var best: [String: CoachWeekGoal]?
                var allowDeferral = false
                func search(_ index: Int, _ pool: [CoachWeekGoal], _ current: [String: CoachWeekGoal]) {
                    if index == freeDays.count {
                        let kinds = keys.map { current[$0]?.kind }
                        guard freeDays.allSatisfy({ day in
                            guard let date = TrainingLocalDate.date(day, timeZone: zone) else { return false }
                            let weekday = calendar.component(.weekday, from: date)
                            return (weekday != 1 && weekday != 7) || current[day]?.kind == .rest
                        }) else { return }
                        guard !(0...4).contains(where: { n in kinds[n...n + 2].allSatisfy { $0 == .strength } }) else { return }
                        let score = freeDays.filter { current[$0]?.kind == .rest }.count * 100 + freeDays.reduce(0) { total, day in
                            guard let proposed = current[day], let original = goals.first(where: { $0.localDay == day }),
                                  let date = TrainingLocalDate.date(day, timeZone: zone) else { return total + 100 }
                            let weekday = calendar.component(.weekday, from: date)
                            let weekendStrength = proposed.kind == .strength && (weekday == 1 || weekday == 7)
                            return total + (weekendStrength ? 20 : 0) + (proposed.kind == original.kind && proposed.focus == original.focus ? 0 : 1)
                        }
                        if score < bestScore { bestScore = score; best = current }
                        return
                    }
                    let day = freeDays[index]
                    for position in pool.indices {
                        let goal = pool[position]
                        var rest = pool; rest.remove(at: position)
                        var next = current
                        next[day] = CoachWeekGoal(localDay: day, kind: goal.kind, focus: goal.focus,
                            reason: goal.localDay == day ? goal.reason : "保留已有安排后调整默认目标到本日。")
                        search(index + 1, rest, next)
                        if allowDeferral && goal.kind != .rest {
                            next[day] = CoachWeekGoal(localDay: day, kind: .rest, focus: "", reason: "工作日无可行位置；\(goal.focus)目标缺额待本人决定，不移周末或新增同日分课。")
                            search(index + 1, rest, next)
                        }
                    }
                }
                if possible && remaining.count == freeDays.count {
                    search(0, remaining, assigned)
                    if best == nil { allowDeferral = true; search(0, remaining, assigned) }
                    if let best { effectiveGoals = keys.compactMap { best[$0] } }
                }
            }
        }
        var days: [CoachWeekDay] = []
        func buildDay(_ day: String) -> CoachWeekDay {
            let kept = input.existing.filter { $0.localDay == day }
            if !kept.isEmpty {
                return CoachWeekDay(localDay: day, kind: .preserved, title: "保留已有安排", focus: "", movements: [], cardio: nil, estimatedSeconds: nil,
                    rationale: ["已计划、进行中或完成的记录保持原样。"]
                        + (kept.contains { $0.source == "日程" && $0.exerciseIDs == nil } ? ["冻结动作缺失，暴露未知，不能视为零。"] : []),
                    blockers: [], existing: kept)
            }
            if modern(input.methodVersion), let captured = input.capturedLocalDay, day < captured {
                return CoachWeekDay(localDay: day, kind: .missing, title: "过去日期待核", focus: "", movements: [], cardio: nil,
                    estimatedSeconds: nil, rationale: ["缺记录不代表已休息或已训练。"],
                    blockers: ["过去日期没有可核对安排或实际，不能生成新日程。"], existing: [])
            }
            let exceptionGoal: CoachWeekGoal? = input.exception.flatMap { exception in
                guard honorException else { return nil }
                return day >= exception.startDay && day <= exception.endDay ? exception.goals.first(where: { $0.localDay == day }) : nil
            }
            let goal = exceptionGoal ?? effectiveGoals.first { $0.localDay == day }
            guard let goal else {
                return CoachWeekDay(localDay: day, kind: .missing, title: "未指定", focus: "", movements: [], cardio: nil, estimatedSeconds: nil,
                    rationale: [], blockers: ["请明确选择力量、有氧或休息；缺项不是休息。"], existing: [])
            }
            if input.preferences.first(where: { $0.localDay == day })?.snapshot == nil {
                return CoachWeekDay(localDay: day, kind: .missing, title: goal.focus, focus: goal.focus, movements: [], cardio: nil, estimatedSeconds: nil,
                    rationale: [goal.reason], blockers: ["当日生效偏好缺失。"], existing: [])
            }
            switch goal.kind {
            case .rest:
                return CoachWeekDay(localDay: day, kind: .rest, title: "休息", focus: "", movements: [], cardio: nil, estimatedSeconds: 0, rationale: [goal.reason], blockers: [], existing: [])
            case .cardio:
                if goal.focus == "跳绳" {
                    let rope = JumpRopeMenuPlan(targetCount: nil, activeSeconds: 450, elapsedSeconds: 1800,
                        notes: "候选：热身5分钟，10轮45秒跳／45秒轻松步行，缓和约10分钟；以可说短句为上限，足踝或膝不适则停止。次数未知，不换算次数。")
                    return CoachWeekDay(localDay: day, kind: .cardio, title: "跳绳", focus: goal.focus, movements: [], cardio: rope, estimatedSeconds: 1800,
                        rationale: [goal.reason, "本次候选须结合当天足踝、膝及恢复核对；不把历史例外当长期固定处方。"], blockers: [], existing: [])
                }
                if goal.focus == "Zone 2" {
                    let candidate = input.catalog.filter { item in
                        !item.archived && CardioWorkoutPresentation.symbol(name: item.name, muscle: item.muscle,
                            equipment: item.equipment, unit: item.unit) != nil
                            && (item.name.contains("单车") || item.name.contains("椭圆机")
                                || item.equipment.contains("单车") || item.equipment.contains("椭圆机"))
                    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.first
                    let zoneDuration = (input.preferences.first { $0.localDay == day }?.snapshot?.zone2Minutes ?? 30) * 60
                    let plan = CoachZone2Plan(mode: candidate?.name ?? "单车或椭圆机", durationSeconds: zoneDuration,
                        guidance: "轻松可说完整句子；器械和具体阻力现场确认，状态不佳可休息。", exerciseID: candidate?.id)
                    var result = CoachWeekDay(localDay: day, kind: .cardio, title: "Zone 2", focus: goal.focus, movements: [], cardio: nil, estimatedSeconds: zoneDuration,
                        rationale: [goal.reason], blockers: candidate == nil ? ["未找到符合心肺记录入口的秒单位单车或椭圆机动作；须确认动作身份。"] : [], existing: [])
                    result.zone2 = plan
                    return result
                }
                return CoachWeekDay(localDay: day, kind: .missing, title: goal.focus, focus: goal.focus, movements: [], cardio: nil, estimatedSeconds: nil,
                    rationale: [goal.reason], blockers: ["有氧模式未知，须选择跳绳或 Zone 2。"], existing: [])
            case .strength:
                let future = keys.filter { candidate in
                    guard candidate > day, !input.existing.contains(where: { $0.localDay == candidate }) else { return false }
                    let explicit = input.exception.flatMap { exception in
                        honorException && candidate >= exception.startDay && candidate <= exception.endDay
                            ? exception.goals.first(where: { $0.localDay == candidate }) : nil
                    }
                    return (explicit ?? effectiveGoals.first(where: { $0.localDay == candidate }))?.kind == .strength
                }.count
                if input.methodVersion == alternatingMethodVersion {
                    return makeAlternatingStrength(day: day, goal: goal, input: input, priorDays: days, futureStrengthDays: future)
                }
                return makeStrength(day: day, goal: goal, input: input, priorDays: days, futureStrengthDays: future)
            case .preserved, .missing:
                return CoachWeekDay(localDay: day, kind: .missing, title: goal.focus, focus: goal.focus, movements: [], cardio: nil, estimatedSeconds: nil,
                    rationale: [], blockers: ["该日没有可保留的日程，须选择实际目标。"], existing: [])
            }
        }
        func strengthState(_ day: CoachWeekDay) -> Bool? { Self.strengthState(day, input: input) }
        for day in keys {
            var next = buildDay(day)
            if strengthState(next) == true && days.count >= 2 {
                let prior = days.suffix(2).map(strengthState)
                if prior.allSatisfy({ $0 == true }) {
                    next.blockers.append("这天会形成连续三天力量；请调整并核对保留安排。")
                } else if prior.contains(where: { $0 == nil }) && prior.contains(where: { $0 == true }) {
                    next.blockers.append("相邻保留安排的力量性质未知，无法排除连续三天力量。")
                }
            }
            days.append(next)
        }
        var result = CoachWeekDraft(id: UUID(), rootID: UUID(), revision: 1, createdAt: now, sourceFingerprint: try fingerprint(input), input: input, days: revalidateWeek(days, input: input), edits: [], ruleCandidates: [])
        result.weeklyShortfall = weeklyShortfalls(result.days, input: input)
        return result
    }

    static func prepareConfirmation(_ draft: CoachWeekDraft, now: Date = .now,
                                    in context: ModelContext) throws -> CoachWeekConfirmation {
        try validateStored(draft, rowID: draft.id, rootID: draft.rootID)
        let checkedDays = revalidateWeek(draft.days, input: draft.input)
        guard checkedDays == draft.days, checkedDays.allSatisfy({ $0.blockers.isEmpty }),
              weeklyShortfalls(checkedDays, input: draft.input).isEmpty else {
            throw TrainingCoachError.invalid("整周实际处方重验未通过，或显示的角色/时间/阻断已过期；请重新审阅保存。")
        }
        guard !context.hasChanges, let zone = TimeZone(identifier: draft.input.timeZone),
              let start = TrainingLocalDate.date(draft.input.startDay, timeZone: zone),
              draft.weeklyShortfall?.isEmpty == true,
              draft.days.allSatisfy({ $0.kind != .missing && $0.blockers.isEmpty }) else {
            throw TrainingCoachError.invalid("七日草案有缺口、未保存编辑或阻断项，不能准备确认。")
        }
        let fresh = try capture(start: start, exception: draft.input.exception, coreException: draft.input.coreException, now: now, retainedReviews: draft.input.retainedReviews, ruleMethod: draft.input.methodVersion, in: context)
        guard try fingerprint(fresh) == draft.sourceFingerprint else {
            throw TrainingCoachError.invalid("训练记录、恢复、偏好或安排已改变，请重新生成并审阅。")
        }
        let rows = try TrainingCoachService.records(sessionID: draft.rootID, in: context).filter { $0.kind == "week_draft" }
        guard let latest = rows.last, try TrainingCoachService.decode(CoachWeekDraft.self, latest) == draft else {
            throw TrainingCoachError.invalid("请先审阅最新保存的草案版本。")
        }
        let source = try TrainingCoachService.encode(draft)
        let sourceHash = ConfirmedTrainingPlanService.digest(Data(source.utf8))
        let requestID = UUID()
        var previews: [ConfirmedDailyTrainingPlanPreview] = []
        var ropes: [CoachWeekRopeMember] = []
        var dayDigests: [String: String] = [:]
        for day in draft.days {
            dayDigests[day.localDay] = try ConfirmedTrainingPlanService.digest(day)
            guard day.kind != .rest && day.kind != .preserved else { continue }
            guard let preference = draft.input.preferences.first(where: { $0.localDay == day.localDay })?.code else {
                throw TrainingCoachError.invalid("\(day.localDay)缺少生效偏好。")
            }
            if let rope = day.cardio {
                guard rope.isValid else { throw TrainingCoachError.invalid("\(day.localDay)跳绳目标无效。") }
                ropes.append(CoachWeekRopeMember(id: UUID(), localDay: day.localDay, plan: rope))
            }
            func addPacket(_ exercises: [ConfirmedDailyPlanExercise], title: String) throws {
                let packet = ConfirmedDailyTrainingPlanPacket(version: 1, id: UUID(), localDay: day.localDay,
                    timeZoneIdentifier: draft.input.timeZone, title: title, preferenceRevisionCode: preference,
                    confirmedAt: now, confirmationReference: "周请求 \(requestID.uuidString)", sourceMarkdown: source,
                    sourceSHA256: sourceHash, guidance: day.rationale.isEmpty ? "本人确认整周候选。" : day.rationale.joined(separator: "；"), exercises: exercises)
                let preview = try ConfirmedDailyTrainingPlanService.preview(packet, in: context)
                guard preview.conflicts.isEmpty else { throw TrainingCoachError.invalid(preview.conflicts.joined(separator: "；")) }
                previews.append(preview)
            }
            if !day.movements.isEmpty {
                let checked = revalidateStrength(day, input: draft.input)
                guard day.kind == .strength, checked.blockers.isEmpty,
                      let duration = checked.estimatedSeconds, duration <= 5400 else {
                    throw TrainingCoachError.invalid("\(day.localDay)力量课的动作、组数或时间需重新核对。")
                }
                try addPacket(day.movements.map(\.exercise), title: day.title)
            }
            if let zone2 = day.zone2 {
                guard let id = zone2.exerciseID, let item = draft.input.catalog.first(where: { $0.id == id }),
                      CardioWorkoutPresentation.symbol(name: item.name, muscle: item.muscle, equipment: item.equipment, unit: item.unit) != nil else {
                    throw TrainingCoachError.invalid("\(day.localDay)缺少可记录的有氧动作身份。")
                }
                let set = WorkoutSetPlan(weight: 0, reps: zone2.durationSeconds, weightSide: .unknown, repsSide: .bilateral,
                    actualDefaultPolicy: .blank, prescription: WorkoutSetPrescription(label: "活动秒数", repsLower: zone2.durationSeconds,
                        repsUpper: zone2.durationSeconds, restLowerSeconds: 0, restUpperSeconds: 0, effortCue: zone2.guidance))
                let exercise = ConfirmedDailyPlanExercise(catalogExerciseID: id, catalogName: item.name, equipment: item.equipment,
                    volumeUnit: item.unit, displayName: item.name, loadGuidance: "按实际时长记录；阻力现场确认。",
                    notes: zone2.guidance, plannedSets: [set])
                try addPacket([exercise], title: "Zone 2 · \(item.name)")
            }
            if day.movements.isEmpty && day.zone2 == nil && day.cardio == nil {
                throw TrainingCoachError.invalid("\(day.localDay)没有可保存的训练目标。")
            }
        }
        let digest = try ConfirmedTrainingPlanService.digest([try ConfirmedTrainingPlanService.digest(draft),
            try ConfirmedTrainingPlanService.digest(previews), try ConfirmedTrainingPlanService.digest(ropes),
            try ConfirmedTrainingPlanService.digest(dayDigests), requestID.uuidString])
        return CoachWeekConfirmation(id: requestID, draft: draft, confirmedAt: now, members: previews,
                                     ropes: ropes, dayDigests: dayDigests, requestDigest: digest)
    }

    static func validateConfirmation(_ confirmation: CoachWeekConfirmation, rowID: UUID, rootID: UUID) throws {
        try validateStored(confirmation.draft, rowID: confirmation.draft.id, rootID: rootID)
        let checkedDays = revalidateWeek(confirmation.draft.days, input: confirmation.draft.input)
        guard checkedDays == confirmation.draft.days, checkedDays.allSatisfy({ $0.blockers.isEmpty }),
              weeklyShortfalls(checkedDays, input: confirmation.draft.input).isEmpty else {
            throw TrainingCoachError.invalid("确认请求的真实七日处方未通过独立规则重验。")
        }
        guard confirmation.id == rowID, confirmation.draft.rootID == rootID,
              Set(confirmation.dayDigests.keys) == Set(confirmation.draft.days.map(\.localDay)),
              Set(confirmation.members.map { $0.packet.id }).count == confirmation.members.count,
              Set(confirmation.ropes.map(\.id)).count == confirmation.ropes.count,
              Set(confirmation.members.map { $0.packet.id }).isDisjoint(with: Set(confirmation.ropes.map(\.id))) else {
            throw TrainingCoachError.invalid("整周请求成员或七日封印无效。")
        }
        let source = try TrainingCoachService.encode(confirmation.draft)
        let sourceHash = ConfirmedTrainingPlanService.digest(Data(source.utf8))
        for day in confirmation.draft.days {
            guard confirmation.dayDigests[day.localDay] == (try ConfirmedTrainingPlanService.digest(day)) else {
                throw TrainingCoachError.invalid("整周逐日封印不一致。")
            }
            let members = confirmation.members.filter { $0.packet.localDay == day.localDay }
            let ropes = confirmation.ropes.filter { $0.localDay == day.localDay }
            let expectedCount = (day.movements.isEmpty ? 0 : 1) + (day.zone2 == nil ? 0 : 1)
            guard members.count == expectedCount, ropes.count == (day.cardio == nil ? 0 : 1),
                  ropes.allSatisfy({ $0.plan == day.cardio }) else {
                throw TrainingCoachError.invalid("七日请求成员不完整或不属于草案。")
            }
            for member in members {
                let packet = member.packet
                guard packet.id != confirmation.id, packet.confirmedAt == confirmation.confirmedAt,
                      packet.confirmationReference == "周请求 \(confirmation.id.uuidString)",
                      packet.sourceMarkdown == source, packet.sourceSHA256 == sourceHash,
                      packet.timeZoneIdentifier == confirmation.draft.input.timeZone,
                      packet.preferenceRevisionCode == confirmation.draft.input.preferences.first(where: { $0.localDay == day.localDay })?.code,
                      member.packetSHA256 == (try ConfirmedTrainingPlanService.digest(packet)) else {
                    throw TrainingCoachError.invalid("日程成员与周草案不一致。")
                }
            }
            if !day.movements.isEmpty {
                guard members.filter({ $0.packet.title == day.title && $0.packet.exercises == day.movements.map(\.exercise) }).count == 1 else {
                    throw TrainingCoachError.invalid("力量日程与草案不一致。")
                }
            }
            if let zone2 = day.zone2 {
                guard members.filter({ member in
                    member.packet.exercises.count == 1 && member.packet.exercises[0].catalogExerciseID == zone2.exerciseID
                        && member.packet.exercises[0].volumeUnit == .second && member.packet.exercises[0].plannedSets.count == 1
                        && member.packet.exercises[0].plannedSets[0].reps == zone2.durationSeconds
                }).count == 1 else { throw TrainingCoachError.invalid("Zone 2 目标与独立成员不一致。") }
            }
        }
        guard confirmation.members.allSatisfy({ member in confirmation.draft.days.contains { $0.localDay == member.packet.localDay } }),
              confirmation.ropes.allSatisfy({ rope in confirmation.draft.days.contains { $0.localDay == rope.localDay } }) else {
            throw TrainingCoachError.invalid("请求包含周范围外的成员。")
        }
        let digest = try ConfirmedTrainingPlanService.digest([try ConfirmedTrainingPlanService.digest(confirmation.draft),
            try ConfirmedTrainingPlanService.digest(confirmation.members), try ConfirmedTrainingPlanService.digest(confirmation.ropes),
            try ConfirmedTrainingPlanService.digest(confirmation.dayDigests), confirmation.id.uuidString])
        guard digest == confirmation.requestDigest else { throw TrainingCoachError.invalid("整周请求封印不一致。") }
    }

    static func validateStored(_ draft: CoachWeekDraft, rowID: UUID, rootID: UUID) throws {
        for day in draft.days where day.pastRestReview != nil {
            guard validPastRestReview(day, input: draft.input),
                  draft.edits.contains(where: { $0.day == day.localDay && $0.field == "日安排" && $0.reason == day.pastRestReview?.reason }) else {
                throw TrainingCoachError.invalid("过去休息日期缺少本人核对或来源不一致。")
            }
        }
        if let coreException = draft.input.coreException {
            guard modern(draft.input.methodVersion), let zone = TimeZone(identifier: draft.input.timeZone),
                  validCoreExceptionScope(coreException, zone: zone) else {
                throw TrainingCoachError.invalid("腹部目标例外的原因、确认或本周期限无效。")
            }
        }
        for review in draft.input.retainedReviews ?? [] {
            guard let entry = draft.input.existing.first(where: { $0.id == review.existingID && $0.localDay == review.localDay }),
                  review.sourceDigest == (try retainedSourceDigest(entry)), validReviewTarget(kind: review.kind, focus: review.focus),
                  !reviewConflicts(entry, kind: review.kind, focus: review.focus),
                  !review.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  review.confirmedAt <= draft.createdAt else { throw TrainingCoachError.invalid("保留安排核对注记缺少有效来源或与原证据冲突。") }
        }
        guard [legacyMethodVersion, methodVersion, alternatingMethodVersion].contains(draft.input.methodVersion),
              (!modern(draft.input.methodVersion) || validCapturedDay(draft.input)),
              draft.id == rowID, draft.rootID == rootID, draft.revision > 0,
              draft.sourceFingerprint == (try fingerprint(draft.input)),
              let zone = TimeZone(identifier: draft.input.timeZone),
              let start = TrainingLocalDate.date(draft.input.startDay, timeZone: zone),
              draft.days.map(\.localDay) == dateKeys(start: start, zone: zone),
              draft.input.preferences.map(\.localDay) == draft.days.map(\.localDay) else {
            throw TrainingCoachError.invalid("整周草案来源、日期或版本损坏。")
        }
    }

    static func save(_ draft: CoachWeekDraft, in context: ModelContext) throws {
        try validateStored(draft, rowID: draft.id, rootID: draft.rootID)
        let rows = try TrainingCoachService.records(sessionID: draft.rootID, in: context).filter { $0.kind == "week_draft" }
        let previous = try rows.map { try TrainingCoachService.decode(CoachWeekDraft.self, $0) }
        guard !previous.contains(where: { $0.id == draft.id }),
              draft.revision == (previous.map(\.revision).max() ?? 0) + 1,
              previous.allSatisfy({ $0.sourceFingerprint == draft.sourceFingerprint && $0.input == draft.input }) else {
            throw TrainingCoachError.invalid("草案版本或原始来源不一致，请保留已有记录并重新生成。")
        }
        try TrainingCoachService.append(draft, kind: "week_draft", sessionID: draft.rootID, id: draft.id, in: context)
    }

    static func revise(_ original: CoachWeekDraft, days: [CoachWeekDay], edits: [CoachWeekEdit],
                       candidates: [CoachWeekRuleCandidate], weeklyShortfall: [String]? = nil,
                       in context: ModelContext) throws -> CoachWeekDraft {
        guard !edits.isEmpty, edits.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              days.map(\.localDay) == original.days.map(\.localDay) else {
            throw TrainingCoachError.invalid("每次修改须保留七天并填写原因。")
        }
        let rows = try TrainingCoachService.records(sessionID: original.rootID, in: context).filter { $0.kind == "week_draft" }
        let latest = try rows.last.map { try TrainingCoachService.decode(CoachWeekDraft.self, $0) }
        guard latest == original else { throw TrainingCoachError.invalid("草案已有新版本，请先重新审阅。") }
        let draft = CoachWeekDraft(id: UUID(), rootID: original.rootID, revision: original.revision + 1,
            createdAt: .now, sourceFingerprint: original.sourceFingerprint, input: original.input, days: revalidateWeek(days, input: original.input),
            edits: original.edits + edits, ruleCandidates: original.ruleCandidates + candidates,
            weeklyShortfall: weeklyShortfalls(days, input: original.input), parentDraftID: original.parentDraftID)
        try save(draft, in: context)
        return draft
    }

    private static func isActive(_ row: CoachWeekExisting) -> Bool {
        ["planned", "inProgress", "completed"].contains(row.status)
    }

    private static func validReviewTarget(kind: CoachWeekDayKind, focus: String) -> Bool {
        (kind == .strength && ["胸", "背", "腿", "肩"].contains(focus))
            || (kind == .cardio && ["跳绳", "Zone 2"].contains(focus)) || (kind == .rest && focus.isEmpty)
    }

    private static func reviewConflicts(_ entry: CoachWeekExisting, kind: CoachWeekDayKind, focus: String) -> Bool {
        if entry.source == "实际训练" && ["inProgress", "completed"].contains(entry.status) && kind == .rest { return true }
        if entry.knownCardio == true && kind != .cardio { return true }
        if let mode = entry.cardioMode, entry.knownCardio == true && mode != focus { return true }
        if entry.frozenExercises?.contains(where: { !$0.roles.isEmpty }) == true && kind != .strength { return true }
        if let known = frozenFocus(entry.frozenExercises ?? []), kind == .strength && known != focus { return true }
        return false
    }

    private static func retainedSourceDigest(_ entry: CoachWeekExisting) throws -> String {
        try ConfirmedTrainingPlanService.digest(entry)
    }

    private static func retainedReview(_ entry: CoachWeekExisting, input: CoachWeekInput) -> CoachWeekRetainedReview? {
        (input.retainedReviews ?? []).last { review in
            review.existingID == entry.id && review.localDay == entry.localDay
                && review.sourceDigest == (try? retainedSourceDigest(entry)) && validReviewTarget(kind: review.kind, focus: review.focus)
                && !review.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !reviewConflicts(entry, kind: review.kind, focus: review.focus)
        }
    }

    private static func preservedCardioMode(_ entry: CoachWeekExisting, input: CoachWeekInput) -> String? {
        guard isActive(entry) else { return nil }
        if let review = retainedReview(entry, input: input) { return review.kind == .cardio ? review.focus : nil }
        return entry.knownCardio == true ? entry.cardioMode : nil
    }

    static func reviewPreservedArrangement(_ draft: CoachWeekDraft, existingID: UUID, kind: CoachWeekDayKind,
                                          focus: String, reason: String, now: Date = .now, in context: ModelContext) throws -> CoachWeekDraft {
        guard validReviewTarget(kind: kind, focus: focus), !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let entry = draft.input.existing.first(where: { $0.id == existingID && isActive($0) }),
              draft.days.contains(where: { $0.localDay == entry.localDay && $0.kind == .preserved }),
              let zone = TimeZone(identifier: draft.input.timeZone), let start = TrainingLocalDate.date(draft.input.startDay, timeZone: zone) else {
            throw TrainingCoachError.invalid("请为本周具体保留安排选择明确类型/主肌，并填写核对原因。")
        }
        guard !reviewConflicts(entry, kind: kind, focus: focus), retainedReview(entry, input: draft.input) == nil,
              frozenFocus(entry.frozenExercises ?? []) == nil && !(entry.knownCardio == true && entry.cardioMode != nil) else {
            throw TrainingCoachError.invalid("已有安排的类型/主肌已明确，或所填与原证据冲突；不能用本周注记覆盖。")
        }
        let rows = try TrainingCoachService.records(sessionID: draft.rootID, in: context).filter { $0.kind == "week_draft" }
        guard let latest = rows.last, try TrainingCoachService.decode(CoachWeekDraft.self, latest) == draft else { throw TrainingCoachError.invalid("请先保存并审阅最新草案。") }
        let fresh = try capture(start: start, exception: draft.input.exception, coreException: draft.input.coreException, now: now, retainedReviews: draft.input.retainedReviews, ruleMethod: draft.input.methodVersion, in: context)
        guard try fingerprint(fresh) == draft.sourceFingerprint else { throw TrainingCoachError.invalid("原始资料已变化，请重新生成；核对不覆盖新数据。") }
        let review = CoachWeekRetainedReview(id: UUID(), existingID: entry.id, localDay: entry.localDay,
            sourceDigest: try retainedSourceDigest(entry), kind: kind, focus: focus, reason: reason, confirmedAt: now)
        let source = try capture(start: start, exception: draft.input.exception, coreException: draft.input.coreException, now: now,
            retainedReviews: (draft.input.retainedReviews ?? []) + [review], ruleMethod: draft.input.methodVersion, in: context)
        let days = revalidateWeek(draft.days, input: source)
        let result = CoachWeekDraft(id: UUID(), rootID: UUID(), revision: 1, createdAt: now,
            sourceFingerprint: try fingerprint(source), input: source, days: days, edits: draft.edits,
            ruleCandidates: [], weeklyShortfall: weeklyShortfalls(days, input: source), parentDraftID: draft.id)
        try save(result, in: context)
        return result
    }

    static func preservedFocus(on day: String, input: CoachWeekInput) -> String? {
        let rows = input.existing.filter { $0.localDay == day && isActive($0) }
        let actualRows = rows.filter { $0.source == "实际训练" }
        let relevant = actualRows.isEmpty ? rows : actualRows
        guard !relevant.isEmpty else { return nil }
        let focuses = relevant.compactMap { row -> String? in
            if let review = retainedReview(row, input: input) { return review.kind == .strength ? review.focus : nil }
            return frozenFocus(row.frozenExercises ?? [])
        }
        guard focuses.count == relevant.count, Set(focuses).count == 1 else { return nil }
        return focuses.first
    }

    private static func frozenFocus(_ snapshots: [CoachWeekFrozenExercise]) -> String? {
        guard !snapshots.isEmpty, snapshots.allSatisfy({ !$0.roles.isEmpty || $0.muscle == "心肺" }) else { return nil }
        var seen = Set<UUID>()
        var counts: [String: Int] = [:]
        for item in snapshots where !item.roles.isEmpty && !item.roles.contains("技术") && seen.insert(item.exerciseID).inserted {
            let groups = Set(["胸", "背", "肩", "腿", "臀"].filter { item.muscle.contains($0) }.map { $0 == "臀" ? "腿" : $0 })
            if groups.count == 1, let group = groups.first { counts[group, default: 0] += 1 }
        }
        guard let maximum = counts.values.max(), counts.values.filter({ $0 == maximum }).count == 1 else { return nil }
        return counts.first { $0.value == maximum }?.key
    }

    static func taskExposure(on day: String, input: CoachWeekInput, priorDays: [CoachWeekDay]) -> (actualRoles: Set<String>, scheduledRoles: Set<String>, unknowns: [String]) {
        guard let zone = TimeZone(identifier: input.timeZone), let target = TrainingLocalDate.date(day, timeZone: zone) else { return ([], [], ["日期未知"]) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var actualRoles = Set<String>(), scheduledRoles = Set<String>(), unknowns: [String] = []
        for actual in input.history {
            guard let date = TrainingLocalDate.date(actual.localDay, timeZone: zone) else { continue }
            let gap = calendar.dateComponents([.day], from: date, to: target).day ?? -1
            guard gap > 0 && gap <= 7, actual.actual.contains(where: { $0.completed }) else { continue }
            let known = roleEvidence(name: actual.name, equipment: actual.equipment ?? "", canonicalID: nil, exerciseID: actual.exerciseID, ruleMethod: input.methodVersion).roles
            if known.isEmpty { unknowns.append("近期实际\(actual.localDay)/\(actual.id)：原名称、器械快照的任务角色未知；未从当前目录补写。") }
            else { actualRoles.formUnion(known) }
        }
        for existing in input.existing where isActive(existing) && existing.source != "实际训练" && existing.localDay != day {
            guard let frozen = existing.frozenExercises, !frozen.isEmpty else {
                if existing.knownCardio != true { unknowns.append("保留安排\(existing.localDay)/\(existing.id)：冻结任务角色未知；未从当前目录补写。") }
                continue
            }
            for item in frozen {
                if item.roles.isEmpty { unknowns.append("保留安排\(existing.localDay)/\(item.exerciseID)：冻结任务角色未知。") }
                else { scheduledRoles.formUnion(item.roles) }
            }
        }
        for prior in priorDays where prior.localDay != day { scheduledRoles.formUnion(prior.movements.flatMap(\.roles)) }
        return (actualRoles, scheduledRoles, Array(Set(unknowns)).sorted())
    }

    private static func strengthState(_ day: CoachWeekDay, input: CoachWeekInput) -> Bool? {
        switch day.kind {
        case .strength: return true
        case .rest, .cardio: return false
        case .missing: return nil
        case .preserved:
            if day.existing.filter(isActive).contains(where: { row in
                retainedReview(row, input: input)?.kind == .strength || row.frozenExercises?.contains { !$0.roles.isEmpty } == true

            }) { return true }
            if !day.existing.filter(isActive).isEmpty && day.existing.filter(isActive).allSatisfy({ $0.knownCardio == true || retainedReview($0, input: input).map { $0.kind == .cardio || $0.kind == .rest } == true }) { return false }
            return nil
        }
    }

    private static func matchesConfirmedGoal(_ day: CoachWeekDay, goal: CoachWeekGoal, input: CoachWeekInput) -> Bool {
        let kind: CoachWeekDayKind
        let focus: String
        switch day.kind {
        case .strength, .cardio:
            kind = day.kind; focus = day.focus
        case .rest:
            kind = .rest; focus = ""
        case .missing:
            return false
        case .preserved:
            guard let strength = strengthState(day, input: input) else { return false }
            if strength {
                guard let retainedFocus = preservedFocus(on: day.localDay, input: input) else { return false }
                kind = .strength; focus = retainedFocus
            } else if !day.existing.filter(isActive).isEmpty && day.existing.filter(isActive).allSatisfy({ retainedReview($0, input: input)?.kind == .rest }) {
                kind = .rest; focus = ""
            } else {
                let modes = Set(day.existing.compactMap { preservedCardioMode($0, input: input) })
                guard modes.count == 1, let mode = modes.first else { return false }
                kind = .cardio; focus = mode
            }
        }
        return kind == goal.kind && (kind == .rest || focus == goal.focus)
    }

    static func revalidateWeek(_ days: [CoachWeekDay], input: CoachWeekInput) -> [CoachWeekDay] {
        var result = days.map { day -> CoachWeekDay in
            var checked = revalidateStrength(day, input: input)
            for entry in day.existing {
                if let review = retainedReview(entry, input: input) {
                    let note = "本人本周核对保留安排\(entry.id)：\(review.kind.title) / \(review.focus)；\(review.reason)。仅识别安排目标，原动作任务/完成与恢复未知不被补写；其他天不重排，若仍有重复/三连或目标缺口，须本人逐日调整并重新审阅。"
                    if !checked.rationale.contains(note) { checked.rationale.append(note) }
                }
            }
            checked.blockers.removeAll { $0.hasPrefix("偏好冲突") || $0.hasPrefix("已有跳过") || $0.hasPrefix("版本范围") || $0.hasPrefix("恢复待处理") || $0.hasPrefix("保留主肌") || $0.hasPrefix("本周例外目标") || $0.hasPrefix("腹部例外目标") || $0.hasPrefix("过去日期") }
            if modern(input.methodVersion), let captured = input.capturedLocalDay, day.localDay < captured,
               day.kind != .preserved, !validPastRestReview(day, input: input) {
                checked.blockers.append("过去日期没有可核对安排或实际，不能生成新日程。")
            }
            if modern(input.methodVersion) && day.kind != .missing {
                if let exception = input.exception, day.localDay >= exception.startDay, day.localDay <= exception.endDay,
                   let goal = exception.goals.first(where: { $0.localDay == day.localDay }), !matchesConfirmedGoal(day, goal: goal, input: input) {
                    checked.blockers.append("本周例外目标已更改或保留安排待核；须重新确认当前七日目标。")
                }
                if let exception = input.coreException, day.localDay >= exception.startDay, day.localDay <= exception.endDay,
                   let goal = exception.goals.first(where: { $0.localDay == day.localDay }), !matchesConfirmedGoal(day, goal: goal, input: input) {
                    checked.blockers.append("腹部例外目标已更改或保留安排待核；须重新确认当周腹部例外。")
                }
            }
            if day.kind == .strength || day.kind == .cardio || day.cardio != nil || day.zone2 != nil {
                for report in input.bodyReports ?? [] where !report.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || report.hasBodyMarkers {
                    guard let zone = TimeZone(identifier: input.timeZone), let date = TrainingLocalDate.date(day.localDay, timeZone: zone),
                          let reportedDate = TrainingLocalDate.date(report.localDay, timeZone: zone) else { continue }
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                    let gap = calendar.dateComponents([.day], from: reportedDate, to: date).day ?? -1
                    guard gap >= 0 && gap <= 7 else { continue }
                    let message = "恢复需本人核对：\(report.localDay)体感记录\(report.id)有本人说明「\(report.note)」\(report.hasBodyMarkers ? "及身体标记" : "")；含义未结构化，不推断疾病或疼痛程度。审阅本周时核对原记录；若存在疼痛/功能受限/恢复差，请在训练反馈明确记录并重新生成，勿直接确认正常剂量。"
                    if !checked.rationale.contains(message) { checked.rationale.append(message) }
                }
                let groups = Dictionary(grouping: input.recoverySignals ?? [], by: \.sessionID)
                for sessionID in groups.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                    let signals = groups[sessionID] ?? []
                    guard let zone = TimeZone(identifier: input.timeZone), let date = TrainingLocalDate.date(day.localDay, timeZone: zone) else { continue }
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                    let relevant = signals.filter { signal in
                        guard let prior = TrainingLocalDate.date(signal.trainingDay, timeZone: zone) else { return false }
                        let gap = calendar.dateComponents([.day], from: prior, to: date).day ?? -1
                        return gap >= 0 && gap <= 7
                    }.sorted { lhs, rhs in
                        if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt > rhs.capturedAt }
                        if lhs.sequence != rhs.sequence { return (lhs.sequence ?? 0) > (rhs.sequence ?? 0) }
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    let pain = relevant.first { $0.feedback.pain != "unknown" }
                    let function = relevant.first { $0.feedback.function != "unknown" }
                    let recovery = relevant.first { $0.feedback.recovery != "unknown" }
                    let concerns = [pain?.feedback.pain == "yes" ? "已报告疼痛" : nil,
                                    function?.feedback.function == "limited" ? "日常功能受限" : nil,
                                    recovery?.feedback.recovery == "poor" ? "恢复差" : nil].compactMap { $0 }
                    if !concerns.isEmpty, let latest = relevant.first {
                        checked.blockers.append("恢复待处理：\(latest.trainingDay)场次\(latest.sessionID)反馈（\(latest.capturedAt)取得）：\(concerns.joined(separator: "、"))；先核实并记录恢复或本日处理，再重新生成正常剂量。")
                    }
                }
            }
            if day.localDay < (input.supportedFromDay ?? "2026-10-26") { checked.blockers.append("版本范围：当前自动规则仅支持2026-10-26起的新候选，不能倒灌到更早历史周。") }
            if day.kind == .preserved && day.existing.contains(where: { isActive($0) && $0.knownCardio != true && retainedReview($0, input: input) == nil }) && preservedFocus(on: day.localDay, input: input) == nil {
                checked.blockers.append("保留主肌/任务快照不足或并列，待本人核对；不能按当前目录反填，也不当作胸/背目标已覆盖。")
            }
            if day.kind == .preserved && !day.existing.contains(where: isActive) { checked.blockers.append("已有跳过/撤销记录不计本周目标；该日需先明确处理已有日程冲突。") }
            if let preference = input.preferences.first(where: { $0.localDay == day.localDay })?.snapshot {
                if input.methodVersion == alternatingMethodVersion {
                    if preference.splitStyle != .upperLowerAlternating || preference.strengthDaysPerWeek != 3 || preference.totalCardioSessionsPerWeek != 2 {
                        checked.blockers.append("偏好冲突：当日生效偏好与上下肢交替、三力量两有氧规则不同，请重新核对。")
                    }
                } else if preference.splitStyle != .bodyPartSplit { checked.blockers.append("偏好冲突：当前拆分方式不属于已实现的部位分化，须明确编排规则。") }
                if day.kind == .strength && preference.maxFocusAreasPerSession < 2 {
                    let groups = Set(day.movements.compactMap { movement in input.catalog.first { $0.id == movement.id }?.muscle })
                    if groups.count > preference.maxFocusAreasPerSession { checked.blockers.append("偏好冲突：本课肌群数超过当日生效偏好。") }
                }
                let configurations = Set(input.preferences.compactMap { $0.snapshot }.map { "\($0.strengthDaysPerWeek)/\($0.jumpRopeSessionsPerWeek)/\($0.zone2SessionsPerWeek)/\($0.totalCardioSessionsPerWeek.map(String.init) ?? "legacy")/\($0.splitStyle.rawValue)" })
                if configurations.count > 1 { checked.blockers.append("偏好冲突：周中生效频率/分化规则变化，须明确本周目标，不能自动拼接。") }
                let hasDayException = input.exception.map { day.localDay >= $0.startDay && day.localDay <= $0.endDay && $0.goals.contains { $0.localDay == day.localDay } } ?? false
                if input.methodVersion != alternatingMethodVersion && !hasDayException && (preference.strengthDaysPerWeek != 4 || preference.jumpRopeSessionsPerWeek != 2 || preference.zone2SessionsPerWeek != 1) {
                    checked.blockers.append("偏好冲突：生效频率与4力量/2跳绳/1Zone2个人补充规则不同，请明确本周例外；未覆盖偏好。")
                }
            }
            checked.blockers.removeAll { $0.hasPrefix("这天会形成") || $0.hasPrefix("相邻保留") || $0.hasPrefix("有氧校验") || $0.hasPrefix("未找到符合心肺") }
            if let rope = checked.cardio, !rope.isValid { checked.blockers.append("有氧校验：跳绳时长或次数无效。") }
            if let zone = checked.zone2 {
                let valid = input.catalog.contains { item in
                    item.id == zone.exerciseID && !item.archived && item.unit == .second
                        && CardioWorkoutPresentation.symbol(name: item.name, muscle: item.muscle, equipment: item.equipment, unit: item.unit) != nil
                        && ["单车", "椭圆机"].contains { item.name.contains($0) || item.equipment.contains($0) }
                }
                if !valid || zone.durationSeconds <= 0 || zone.durationSeconds > 5400 {
                    checked.blockers.append("有氧校验：Zone 2须选择来源目录内秒单位单车/椭圆机及有效时长。")
                }
            }
            if checked.kind == .cardio {
                if checked.cardio == nil && checked.zone2 == nil { checked.blockers.append("有氧校验：缺少实际有氧处方。") }
                checked.estimatedSeconds = (checked.cardio?.elapsedSeconds ?? checked.cardio?.activeSeconds ?? 0) + (checked.zone2?.durationSeconds ?? 0)
            }
            if checked.kind == .missing && checked.blockers.isEmpty { checked.blockers.append("每日目标缺失。") }
            return checked
        }
        for index in result.indices where index >= 2 {
            let states = result[(index - 2)...index].map { strengthState($0, input: input) }
            if states.allSatisfy({ $0 == true }) {
                result[index].blockers.append("这天会形成连续三天力量；请调整并核对保留安排。")
            } else if states.filter({ $0 == true }).count == 2 && states.contains(where: { $0 == nil }) {
                result[index].blockers.append("相邻保留安排的力量性质未知，无法排除连续三天力量。")
            }
        }
        if let zone = TimeZone(identifier: input.timeZone), let start = TrainingLocalDate.date(input.startDay, timeZone: zone) {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let expanded = (-2...8).compactMap { offset -> CoachWeekDay? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let key = TrainingLocalDate.key(date, timeZone: zone)
                if let current = result.first(where: { $0.localDay == key }) { return current }
                let existing = input.existing.filter { $0.localDay == key && isActive($0) }
                return CoachWeekDay(localDay: key, kind: .preserved, title: "相邻周", focus: "", movements: [], cardio: nil,
                    estimatedSeconds: nil, rationale: [], blockers: [], existing: existing)
            }
            for index in 2..<expanded.count {
                let window = Array(expanded[(index - 2)...index])
                guard window.contains(where: { !result.map(\.localDay).contains($0.localDay) }),
                      window.allSatisfy({ strengthState($0, input: input) == true }) else { continue }
                for day in window {
                    if let current = result.firstIndex(where: { $0.localDay == day.localDay }) {
                        result[current].blockers.append("这天会形成跨周连续三天力量；须核对相邻周实际/安排。")
                    }
                }
            }
            for index in result.indices where index < 2 || index > 4 {
                if !input.existing.contains(where: { $0.localDay < input.startDay || $0.localDay > result.last!.localDay }) {
                    let message = "相邻周暴露未知；缺记录不代表已休息，开始训练前须核对。"
                    if !result[index].rationale.contains(message) { result[index].rationale.append(message) }
                }
            }
        }
        return result
    }

    static func weeklyShortfalls(_ days: [CoachWeekDay], input: CoachWeekInput) -> [String] {
        guard [legacyMethodVersion, methodVersion, alternatingMethodVersion].contains(input.methodVersion) else { return ["不支持的编排方法版本。"] }
        guard let zone = TimeZone(identifier: input.timeZone), let start = TrainingLocalDate.date(input.startDay, timeZone: zone) else { return ["周日期未知。"] }
        if input.methodVersion == alternatingMethodVersion { return alternatingShortfalls(days, input: input, start: start, zone: zone) }
        let defaults = defaultGoals(start: start, zone: zone)
        let validExceptionGoals = defaults.compactMap { goal in
            input.exception.flatMap { exception in
                goal.localDay >= exception.startDay && goal.localDay <= exception.endDay ? exception.goals.first { $0.localDay == goal.localDay } : nil
            }
        }
        let fullException = validExceptionGoals.count == 7
        let preference = input.preferences.first?.snapshot
        var expected = [preference?.strengthDaysPerWeek ?? 4, preference?.jumpRopeSessionsPerWeek ?? 2, preference?.zone2SessionsPerWeek ?? 1]
        func targetIndex(_ goal: CoachWeekGoal) -> Int? {
            if goal.kind == .strength { return 0 }
            if goal.kind == .cardio && goal.focus == "跳绳" { return 1 }
            if goal.kind == .cardio && goal.focus == "Zone 2" { return 2 }
            return nil
        }
        if fullException {
            expected = [0, 0, 0]
            for goal in validExceptionGoals { if let index = targetIndex(goal) { expected[index] += 1 } }
        }
        let actual = [days.filter { strengthState($0, input: input) == true }.count,
            days.filter { $0.cardio != nil || ($0.kind == .preserved && $0.existing.contains { preservedCardioMode($0, input: input) == "跳绳" }) }.count,
            days.filter { $0.zone2 != nil || ($0.kind == .preserved && $0.existing.contains { preservedCardioMode($0, input: input) == "Zone 2" }) }.count]
        var result = zip(["力量", "跳绳", "Zone 2"], zip(expected, actual)).compactMap { name, counts in
            counts.0 > counts.1 ? "\(name)候选缺\(counts.0 - counts.1)次；未按缺失记录推断已经完成。" : nil
        }
        if !fullException {
            let expectedFocus = Set(defaults.filter { $0.kind == .strength }.map(\.focus))
            let covered = Set(days.compactMap { day -> String? in
                if day.kind == .preserved { return preservedFocus(on: day.localDay, input: input) }
                guard day.kind == .strength else { return nil }
                if ["腿", "前链", "后链", "综合"].contains(where: day.focus.contains) { return "腿" }
                return ["胸", "背", "肩"].first(where: day.focus.contains)
            })
            for focus in expectedFocus.subtracting(covered).sorted() { result.append("默认\(focus)部目标未被明确覆盖；未知保留主肌不能替代该目标。") }
        }
        if days.contains(where: { strengthState($0, input: input) == nil }) { result.append("部分日期类型未知，不能视为零暴露或休息。") }
        if input.methodVersion == methodVersion {
            let count = coreCoverage(days, input: input).count
            let permittedException = input.coreException.map { exception in
                validCoreException(exception, days: defaults.map(\.localDay)) && days.count == 7
                    && days.allSatisfy { day in exception.goals.first(where: { $0.localDay == day.localDay }).map { matchesConfirmedGoal(day, goal: $0, input: input) } == true }
            } == true
            if count < 4 && !permittedException { result.append("腹部每周至少4个不同动作，当前可核对\(count)个；其余待决定。") }
        }
        return result
    }

    static func regenerateDay(_ draft: CoachWeekDraft, goal: CoachWeekGoal) throws -> [CoachWeekDay] {
        guard let index = draft.days.firstIndex(where: { $0.localDay == goal.localDay }), draft.days[index].kind != .preserved else {
            throw TrainingCoachError.invalid("目标日不在当前周或已有受保护安排。")
        }
        var days = draft.days
        if modern(draft.input.methodVersion), let captured = draft.input.capturedLocalDay,
           goal.localDay < captured, goal.kind == .rest {
            guard !goal.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !draft.input.existing.contains(where: { $0.localDay == goal.localDay }),
                  !draft.input.history.contains(where: { $0.localDay == goal.localDay }) else {
                throw TrainingCoachError.invalid("过去日期已有记录或缺少本人核对原因，不能标为休息。")
            }
            var reviewed = CoachWeekDay(localDay: goal.localDay, kind: .rest, title: "本人核对休息", focus: "", movements: [], cardio: nil,
                estimatedSeconds: 0, rationale: ["本人核对过去日期为休息：\(goal.reason)；不新增历史训练记录。"], blockers: [], existing: [])
            reviewed.pastRestReview = CoachWeekPastRestReview(localDay: goal.localDay, reason: goal.reason, confirmation: pastRestConsent)
            days[index] = reviewed
            return revalidateWeek(days, input: draft.input)
        }
        if goal.kind == .strength {
            let others = draft.days.filter { $0.localDay != goal.localDay }
            days[index] = draft.input.methodVersion == alternatingMethodVersion
                ? makeAlternatingStrength(day: goal.localDay, goal: goal, input: draft.input, priorDays: others)
                : makeStrength(day: goal.localDay, goal: goal, input: draft.input, priorDays: others)
        } else {
            let generated = try generate(input: draft.input, goals: [goal], honorException: false)
            days[index] = generated.days[index]
        }
        return revalidateWeek(days, input: draft.input)
    }

    static func validateRuleActivation(_ activation: CoachWeekRuleActivation, rowID: UUID, rootID: UUID) throws {
        guard activation.id == rowID, rootID == ruleRootID,
              [personalRuleVersion, overlapRuleVersion].contains(activation.version),
              [personalRuleVersion, overlapRuleVersion].contains(activation.previousVersion),
              activation.version != activation.previousVersion,
              activation.sourceDraftID != nil,
              activation.replayFingerprint?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              (activation.candidateID != nil && activation.rollbackOfActivationID == nil)
                || (activation.candidateID == nil && activation.rollbackOfActivationID != nil) else {
            throw TrainingCoachError.invalid("规则激活记录的身份、版本或回放证据无效。")
        }
    }

    static func confirmWeekException(_ draft: CoachWeekDraft, reason: String, now: Date = .now, in context: ModelContext) throws -> CoachWeekDraft {
        try confirmException(draft, reason: reason, coreOnly: false, now: now, in: context)
    }

    static func confirmCoreException(_ draft: CoachWeekDraft, reason: String, now: Date = .now, in context: ModelContext) throws -> CoachWeekDraft {
        try confirmException(draft, reason: reason, coreOnly: true, now: now, in: context)
    }

    private static func confirmException(_ draft: CoachWeekDraft, reason: String, coreOnly: Bool, now: Date, in context: ModelContext) throws -> CoachWeekDraft {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let zone = TimeZone(identifier: draft.input.timeZone), let start = TrainingLocalDate.date(draft.input.startDay, timeZone: zone) else {
            throw TrainingCoachError.invalid("本周例外须有明确原因和有效日期。")
        }
        let fresh = try capture(start: start, exception: draft.input.exception, coreException: draft.input.coreException, now: now, retainedReviews: draft.input.retainedReviews, ruleMethod: draft.input.methodVersion, in: context)
        guard try fingerprint(fresh) == draft.sourceFingerprint else { throw TrainingCoachError.invalid("来源已变化，请重新生成；不能用例外绕过新记录。") }
        let latest = try TrainingCoachService.records(sessionID: draft.rootID, in: context).filter { $0.kind == "week_draft" }.last
        guard let latest, try TrainingCoachService.decode(CoachWeekDraft.self, latest) == draft else { throw TrainingCoachError.invalid("请先保存并审阅最新完整草案。") }
        let goals = try draft.days.map { day -> CoachWeekGoal in
            var kind = day.kind, focus = day.focus
            if kind == .preserved {
                guard let strength = strengthState(day, input: draft.input) else { throw TrainingCoachError.invalid("已有安排类型未知，不能自动降低周目标。") }
                let reviewedRest = !day.existing.filter(isActive).isEmpty && day.existing.filter(isActive).allSatisfy { retainedReview($0, input: draft.input)?.kind == .rest }
                kind = strength ? .strength : reviewedRest ? .rest : .cardio
                if reviewedRest { focus = "" }
                if strength {
                    guard let retainedFocus = preservedFocus(on: day.localDay, input: draft.input) else { throw TrainingCoachError.invalid("已有力量安排主肌未知，不能猜测本周目标。") }
                    focus = retainedFocus
                }
                if !strength && !reviewedRest {
                    guard let mode = day.existing.compactMap({ preservedCardioMode($0, input: draft.input) }).first else { throw TrainingCoachError.invalid("已有有氧模式未知，不能猜测本周目标。") }
                    focus = mode
                }
            }
            guard kind != .missing else { throw TrainingCoachError.invalid("先明确全部七日目标，再确认本周例外。") }
            return CoachWeekGoal(localDay: day.localDay, kind: kind, focus: focus, reason: reason)
        }
        let exception = coreOnly ? draft.input.exception : CoachWeekException(id: UUID(), startDay: draft.days[0].localDay, endDay: draft.days[6].localDay,
            reason: reason, goals: goals, confirmation: "本人在App明确确认本周目标例外；原草案\(draft.id)；\(now)")
        let coreException = coreOnly ? CoachWeekCoreException(startDay: draft.days[0].localDay, endDay: draft.days[6].localDay,
            reason: reason, confirmation: coreExceptionConsent, goals: goals) : draft.input.coreException
        let newInput = try capture(start: start, exception: exception, coreException: coreException, now: now, retainedReviews: draft.input.retainedReviews, ruleMethod: draft.input.methodVersion, in: context)
        let days = revalidateWeek(draft.days, input: newInput)
        var result = CoachWeekDraft(id: UUID(), rootID: UUID(), revision: 1, createdAt: now,
            sourceFingerprint: try fingerprint(newInput), input: newInput, days: days, edits: draft.edits,
            ruleCandidates: [], weeklyShortfall: weeklyShortfalls(days, input: newInput))
        result.parentDraftID = draft.id
        try save(result, in: context)
        return result
    }

    static func validateStoredRuleActivations(in context: ModelContext) throws {
        _ = try checkedRuleVersion(in: context)
    }

    static func activeRuleVersion(in context: ModelContext) throws -> String {
        try checkedRuleVersion(in: context)
    }

    private static func checkedRuleVersion(in context: ModelContext) throws -> String {
        let records = try context.fetch(FetchDescriptor<TrainingCoachRecord>())
        let rows = TrainingCoachService.ordered(records.filter { $0.kind == "week_rule_activation" })
        var version = personalRuleVersion
        var previous: CoachWeekRuleActivation?
        for row in rows {
            let activation = try TrainingCoachService.decode(CoachWeekRuleActivation.self, row)
            try validateRuleActivation(activation, rowID: row.id, rootID: row.sessionID)
            guard activation.previousVersion == version, activation.createdAt <= .now,
                  previous.map({ $0.createdAt <= activation.createdAt }) ?? true else {
                throw TrainingCoachError.invalid("规则激活时间或版本链不连续。")
            }
            if let candidateID = activation.candidateID {
                let matches = records.filter { $0.kind == "week_draft" && $0.id == activation.sourceDraftID }
                guard matches.count == 1 else { throw TrainingCoachError.invalid("规则激活缺少唯一来源草案。") }
                let draft = try TrainingCoachService.decode(CoachWeekDraft.self, matches[0])
                try validateStored(draft, rowID: matches[0].id, rootID: matches[0].sessionID)
                guard let candidate = draft.ruleCandidates.first(where: { $0.id == candidateID }),
                      candidate.originalRule == version, candidate.executableVersion == activation.version,
                      candidate.replayFingerprint == activation.replayFingerprint,
                      let originalID = candidate.replaySourceDraftID,
                      let originalRow = records.first(where: { $0.kind == "week_draft" && $0.id == originalID && $0.sessionID == draft.rootID }),
                      let editIDs = candidate.replayEditIDs, !editIDs.isEmpty, Set(editIDs).count == editIDs.count else {
                    throw TrainingCoachError.invalid("规则激活的候选、原稿或精确修改证据缺失。")
                }
                let original = try TrainingCoachService.decode(CoachWeekDraft.self, originalRow)
                guard original.input == draft.input, original.sourceFingerprint == draft.sourceFingerprint else { throw TrainingCoachError.invalid("规则来源冻结输入不一致。") }
                let edits = draft.edits.filter { editIDs.contains($0.id) }
                guard edits.count == editIDs.count else { throw TrainingCoachError.invalid("规则候选引用了其他草案的修改。") }
                let replayed = try ruleCandidate(original: original, revisedDays: draft.days, edits: edits, outcome: candidate.outcome)
                guard replayed.executableVersion == activation.version, replayed.replayFingerprint == activation.replayFingerprint else { throw TrainingCoachError.invalid("规则激活的结构回放不匹配。") }
            } else {
                guard let previous, activation.rollbackOfActivationID == previous.id,
                      activation.version == previous.previousVersion,
                      activation.sourceDraftID == previous.sourceDraftID,
                      activation.replayFingerprint == previous.replayFingerprint else {
                    throw TrainingCoachError.invalid("规则回退未指向前一有效激活。")
                }
            }
            previous = activation
            version = activation.version
        }
        return version
    }

    private static func withRule(_ input: CoachWeekInput, version: String) -> CoachWeekInput {
        CoachWeekInput(startDay: input.startDay, timeZone: input.timeZone, methodVersion: input.methodVersion,
            personalRuleVersion: version, preferences: input.preferences, exception: input.exception,
            catalog: input.catalog, history: input.history, existing: input.existing, recovery: input.recovery, unknowns: input.unknowns, sourceRuleVersions: input.sourceRuleVersions, supportedFromDay: input.supportedFromDay, recoverySignals: input.recoverySignals, bodyReports: input.bodyReports, retainedReviews: input.retainedReviews, coreException: input.coreException, capturedLocalDay: input.capturedLocalDay)
    }

    private static func replayDigest(_ days: [CoachWeekDay]) throws -> String {
        let data = Data(try TrainingCoachService.encode(days).utf8)
        func stable(_ value: Any) -> Any {
            if let object = value as? [String: Any] {
                return object.filter { $0.key != "id" }.mapValues(stable)
            }
            if let array = value as? [Any] { return array.map(stable) }
            return value
        }
        let value = stable(try JSONSerialization.jsonObject(with: data))
        return ConfirmedTrainingPlanService.digest(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }

    static func ruleCandidate(original: CoachWeekDraft, revisedDays: [CoachWeekDay], edits: [CoachWeekEdit], outcome: CoachWeekOutcome? = nil) throws -> CoachWeekRuleCandidate {
        guard original.days.map(\.localDay) == revisedDays.map(\.localDay), (!edits.isEmpty || outcome != nil),
              edits.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TrainingCoachError.invalid("规则候选须保留完整周和本人修改原因。")
        }
        if let outcome, outcome.rootID != original.rootID || outcome.sourceFingerprint != original.sourceFingerprint { throw TrainingCoachError.invalid("结果观察不属于相同root及冻结输入，不能拼接。") }
        let version = original.input.personalRuleVersion == overlapRuleVersion ? personalRuleVersion : overlapRuleVersion
        let input = withRule(original.input, version: version)
        var replay = original.days
        for index in replay.indices where replay[index].kind == .strength {
            let goal = CoachWeekGoal(localDay: replay[index].localDay, kind: .strength, focus: replay[index].focus, reason: "同一冻结输入回放")
            replay[index] = makeStrength(day: goal.localDay, goal: goal, input: input, priorDays: replay.filter { $0.localDay != goal.localDay })
        }
        replay = revalidateWeek(replay, input: input)
        let editedDays = Set(edits.map(\.day))
        func distance(_ automatic: [CoachWeekDay]) -> Int {
            automatic.filter { editedDays.contains($0.localDay) }.reduce(0) { count, day in
                let human = revisedDays.first { $0.localDay == day.localDay }
                return count + Set(day.movements.map(\.id)).symmetricDifference(Set(human?.movements.map(\.id) ?? [])).count
            }
        }
        func recentIDs(on day: String) -> Set<UUID> {
            guard let zone = TimeZone(identifier: original.input.timeZone), let date = TrainingLocalDate.date(day, timeZone: zone) else { return [] }
            return Set(original.input.history.filter { row in
                guard let previous = TrainingLocalDate.date(row.localDay, timeZone: zone) else { return false }
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                let age = calendar.dateComponents([.day], from: previous, to: date).day ?? -1
                return age > 0 && age <= 7 && row.actual.contains { $0.completed }
            }.map(\.exerciseID) + original.input.existing.filter { $0.localDay < day && isActive($0) && $0.source != "实际训练" }.flatMap { $0.exerciseIDs ?? [] })
        }
        func repeats(_ days: [CoachWeekDay]) -> Int {
            days.filter { editedDays.contains($0.localDay) }.reduce(0) { count, day in
                count + Set(day.movements.map(\.id)).intersection(recentIDs(on: day.localDay)).count
            }
        }
        let beforeDistance = distance(original.days), afterDistance = distance(replay)
        let beforeRepeats = repeats(original.days), humanRepeats = repeats(revisedDays), afterRepeats = repeats(replay)
        let relevant = original.input.personalRuleVersion == personalRuleVersion && humanRepeats < beforeRepeats
            && afterRepeats < beforeRepeats && afterDistance < beforeDistance
        let pass = relevant && replay.allSatisfy { $0.blockers.isEmpty && $0.kind != .missing }
            && weeklyShortfalls(replay, input: input).isEmpty
        let evidence = edits.map { "\($0.day) / \($0.field)：\($0.before) → \($0.after)；原因：\($0.reason)" }
        let seal = try ConfirmedTrainingPlanService.digest([try fingerprint(input), try replayDigest(replay), original.id.uuidString])
        return CoachWeekRuleCandidate(id: UUID(), originalRule: original.input.personalRuleVersion,
            proposedChange: "切换近期重复排序版本 \(version)：02先减少同UUID重复，01先覆盖不同角色；不变更动作身份、负重资格、长期偏好或已保存日程。",
            evidence: evidence + ["同UUID近期重复动作：原版\(beforeRepeats) / 候选\(afterRepeats) / 人工\(humanRepeats)；与人工动作集合差异：原版\(beforeDistance) / 候选\(afterDistance)。", "输入指纹 \(original.sourceFingerprint)；原草案 \(original.id)；\(revisedDays.filter { $0.kind == .strength }.count)课人工修订参与对照。"],
            unknowns: ["人工修改是选择证据，不是训练效果。", "反证：重复同一动作可支持稳定比较；减少重复不保证更好。", outcome.map { "已冻结结果版本\($0.draftID)：\($0.actual.count)动作实际、\($0.ropeActual.count)跳绳条目；\($0.unknowns.joined(separator: "；"))；不据此推断因果效果。" } ?? "尚缺该版本真实训练、恢复与本人接受度；仅通过结构回放。"],
            replayResult: pass ? "PASS：同一冻结输入七日回放通过动作、组数、时间、频率和三连约束；不证明效果。" : "仅记录：没有与近期重复直接相关且改善人工对照的回放变化，或仍有结构阻断/周缺口；不可激活。",
            status: pass ? "可审阅应用" : "仅记录", executableVersion: pass ? version : nil, replayFingerprint: seal, replaySourceDraftID: original.id, replayEditIDs: edits.map(\.id), outcome: outcome)
    }

    static func activateRuleCandidate(_ candidate: CoachWeekRuleCandidate, draft: CoachWeekDraft, in context: ModelContext) throws -> String {
        guard let version = candidate.executableVersion, [personalRuleVersion, overlapRuleVersion].contains(version),
              candidate.originalRule == (try activeRuleVersion(in: context)),
              draft.ruleCandidates.contains(candidate), candidate.replayResult.hasPrefix("PASS"), let seal = candidate.replayFingerprint else {
            throw TrainingCoachError.invalid("仅最新保存草案内回放通过且与当前版本一致的规则可应用。")
        }
        let rows = try TrainingCoachService.records(sessionID: draft.rootID, in: context).filter { $0.kind == "week_draft" }
        guard let last = rows.last, try TrainingCoachService.decode(CoachWeekDraft.self, last) == draft else { throw TrainingCoachError.invalid("草案版本已改变。") }
        guard let sourceID = candidate.replaySourceDraftID,
              let sourceRow = rows.first(where: { $0.id == sourceID }) else { throw TrainingCoachError.invalid("回放原草案缺失。") }
        let original = try TrainingCoachService.decode(CoachWeekDraft.self, sourceRow)
        guard let editIDs = candidate.replayEditIDs, !editIDs.isEmpty,
              Set(editIDs).count == editIDs.count else { throw TrainingCoachError.invalid("候选缺少精确编辑证据。") }
        let scopedEdits = draft.edits.filter { editIDs.contains($0.id) }
        guard scopedEdits.count == editIDs.count else { throw TrainingCoachError.invalid("候选编辑不属于当前草案。") }
        let replayed = try ruleCandidate(original: original, revisedDays: draft.days, edits: scopedEdits, outcome: candidate.outcome)
        guard replayed.executableVersion == version, replayed.replayFingerprint == seal else {
            throw TrainingCoachError.invalid("实际执行回放与候选封印不一致，不激活规则。")
        }
        if let outcome = candidate.outcome {
            guard let resultRow = rows.first(where: { $0.id == outcome.draftID }) else { throw TrainingCoachError.invalid("结果修订版已缺失。") }
            let resultDraft = try TrainingCoachService.decode(CoachWeekDraft.self, resultRow)
            let freshOutcome = try evaluateOutcome(resultDraft, now: outcome.capturedAt, in: context)
            guard freshOutcome == outcome else { throw TrainingCoachError.invalid("结果证据已变化，请重新观察并回放。") }
        }
        let update = CoachWeekRuleActivation(id: UUID(), version: version, previousVersion: candidate.originalRule,
            candidateID: candidate.id, sourceDraftID: draft.id, replayFingerprint: seal, createdAt: .now)
        try TrainingCoachService.append(update, kind: "week_rule_activation", sessionID: ruleRootID, id: update.id, in: context)
        return version
    }

    static func rollbackRule(in context: ModelContext) throws -> String {
        try validateStoredRuleActivations(in: context)
        let rows = try TrainingCoachService.records(sessionID: ruleRootID, in: context).filter { $0.kind == "week_rule_activation" }
        guard let row = rows.last else { throw TrainingCoachError.invalid("没有已激活规则可回退。") }
        let latest = try TrainingCoachService.decode(CoachWeekRuleActivation.self, row)
        let update = CoachWeekRuleActivation(id: UUID(), version: latest.previousVersion, previousVersion: latest.version,
            candidateID: nil, sourceDraftID: latest.sourceDraftID, replayFingerprint: latest.replayFingerprint, createdAt: .now, rollbackOfActivationID: latest.id)
        try TrainingCoachService.append(update, kind: "week_rule_activation", sessionID: ruleRootID, id: update.id, in: context)
        return update.version
    }

    static func ruleCandidateFromOutcome(_ confirmedDraft: CoachWeekDraft, now: Date = .now, in context: ModelContext) throws -> CoachWeekRuleCandidate {
        let rows = try TrainingCoachService.records(sessionID: confirmedDraft.rootID, in: context)
        let revisions = try rows.filter { $0.kind == "week_draft" }.map { try TrainingCoachService.decode(CoachWeekDraft.self, $0) }
        guard revisions.contains(confirmedDraft), let original = revisions.min(by: { $0.revision < $1.revision }),
              original.sourceFingerprint == confirmedDraft.sourceFingerprint,
              try rows.filter({ $0.kind == "week_confirmation" }).contains(where: { try TrainingCoachService.decode(CoachWeekConfirmation.self, $0).draft == confirmedDraft }) else {
            throw TrainingCoachError.invalid("结果候选须使用同一冻结输入的已确认修订版。")
        }
        let outcome = try evaluateOutcome(confirmedDraft, now: now, in: context)
        return try ruleCandidate(original: original, revisedDays: confirmedDraft.days, edits: confirmedDraft.edits, outcome: outcome)
    }

    static func saveOutcomeRuleCandidate(_ confirmedDraft: CoachWeekDraft, candidate: CoachWeekRuleCandidate, in context: ModelContext) throws -> CoachWeekDraft {
        guard !context.hasChanges, let outcome = candidate.outcome, outcome.draftID == confirmedDraft.id else {
            throw TrainingCoachError.invalid("先保存当前编辑，结果候选必须绑定该确认版。")
        }
        let verified = try ruleCandidateFromOutcome(confirmedDraft, now: outcome.capturedAt, in: context)
        guard verified.replayFingerprint == candidate.replayFingerprint, verified.outcome == outcome,
              verified.executableVersion == candidate.executableVersion, verified.replayEditIDs == candidate.replayEditIDs else {
            throw TrainingCoachError.invalid("结果候选已变化，请重新审阅。")
        }
        let rows = try TrainingCoachService.records(sessionID: confirmedDraft.rootID, in: context).filter { $0.kind == "week_draft" }
        guard let row = rows.last else { throw TrainingCoachError.invalid("原草案缺失。") }
        let latest = try TrainingCoachService.decode(CoachWeekDraft.self, row)
        guard latest.days == confirmedDraft.days, latest.sourceFingerprint == confirmedDraft.sourceFingerprint else {
            throw TrainingCoachError.invalid("已有不同处方修订，请先审阅；结果观察不覆盖新处方。")
        }
        let result = CoachWeekDraft(id: UUID(), rootID: latest.rootID, revision: latest.revision + 1, createdAt: .now,
            sourceFingerprint: latest.sourceFingerprint, input: latest.input, days: latest.days, edits: latest.edits,
            ruleCandidates: latest.ruleCandidates + [verified], weeklyShortfall: latest.weeklyShortfall, parentDraftID: latest.parentDraftID)
        try save(result, in: context)
        return result
    }

    static func evaluateOutcome(_ draft: CoachWeekDraft, now: Date = .now, in context: ModelContext) throws -> CoachWeekOutcome {
        let rows = try TrainingCoachService.records(sessionID: draft.rootID, in: context).filter { $0.kind == "week_confirmation" }
        let confirmations = try rows.map { try TrainingCoachService.decode(CoachWeekConfirmation.self, $0) }.filter { $0.draft.id == draft.id }
        var scheduleIDs = Set(confirmations.flatMap { $0.members.map { $0.packet.id } + $0.ropes.map(\.id) })
        var ropeIDs = Set(confirmations.flatMap { $0.ropes.map(\.id) })
        guard let zone = TimeZone(identifier: draft.input.timeZone), let start = TrainingLocalDate.date(draft.input.startDay, timeZone: zone) else { throw TrainingCoachError.invalid("日期未知。") }
        let fresh = try capture(start: start, exception: draft.input.exception, coreException: draft.input.coreException, now: now, retainedReviews: draft.input.retainedReviews, validateRetainedReviewBindings: false, ruleMethod: draft.input.methodVersion, in: context)
        var provenance = ["新成员通过本确认版request的scheduleID关联，包含力量及Zone2。"]
        var retainedSessionIDs = Set<UUID>()
        var retainedUnknowns: [String] = []
        if !confirmations.isEmpty {
            let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
            for entry in draft.days.flatMap(\.existing).filter(isActive) {
                if entry.source == "实际训练" {
                    retainedSessionIDs.insert(entry.id)
                    provenance.append("保留实际sessionID \(entry.id)；不以日期匹配。")
                } else if let current = schedules.first(where: { $0.id == entry.id }) {
                    let sealed = try entry.confirmedPacketDigest.map { expected in
                        try ConfirmedDailyTrainingPlanService.readback(id: current.id, in: context)?.packetSHA256 == expected
                    }
                    let rawMatches = fresh.existing.contains { $0.id == entry.id && $0.contentDigest == entry.contentDigest && entry.contentDigest != nil }
                    if sealed == true || (entry.confirmedPacketDigest == nil && rawMatches) {
                        scheduleIDs.insert(entry.id)
                        if entry.cardioMode == "跳绳" { ropeIDs.insert(entry.id) }
                        provenance.append("保留日程scheduleID \(entry.id)；\(sealed == true ? "原确认封印核验" : "冻结内容核验")。")
                    } else { retainedUnknowns.append("保留日程\(entry.id)身份/冻结内容未通过回读，未拼接其结果。") }
                } else { retainedUnknowns.append("保留日程\(entry.id)当前不可读取，结果未知。") }
            }
        }
        let actual = fresh.history.filter { $0.scheduledWorkoutID.map(scheduleIDs.contains) == true || retainedSessionIDs.contains($0.sessionID) }
        let ropes = try context.fetch(FetchDescriptor<JumpRopeEntry>()).filter { $0.createdAt <= now && $0.date <= now && $0.scheduledWorkoutID.map(ropeIDs.contains) == true }.map {
            CoachWeekRopeActual(id: $0.id, scheduleID: $0.scheduledWorkoutID!, date: $0.date, count: $0.count,
                activeSeconds: $0.activeDurationSeconds, elapsedSeconds: $0.elapsedDurationSeconds, legacySeconds: $0.durationSeconds)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        var unknowns = ["恢复记录仅为对应日期自报背景，不证明该计划导致恢复变化；缺失不代表正常。"] + retainedUnknowns
        for id in retainedSessionIDs.sorted(by: { $0.uuidString < $1.uuidString }) where !actual.contains(where: { $0.sessionID == id }) { unknowns.append("保留实际sessionID \(id)尚无可读取的完成组，进行中不当已完成。") }
        if confirmations.isEmpty { unknowns.append("该草案版本未找到已保存周确认，无可归属正式计划；不以同日训练拼接。") }
        let observed = Set(actual.compactMap(\.scheduledWorkoutID) + ropes.map(\.scheduleID))
        for id in scheduleIDs.subtracting(observed).sorted(by: { $0.uuidString < $1.uuidString }) { unknowns.append("日程 \(id) 尚无可归属完成记录；不等于未训练。") }
        let actualDays = Set(actual.map(\.localDay) + ropes.map { TrainingLocalDate.key($0.date, timeZone: zone) })
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let recoveryDays = Set(actualDays.compactMap { TrainingLocalDate.date($0, timeZone: zone) }.compactMap { calendar.date(byAdding: .day, value: 1, to: $0) }.map { TrainingLocalDate.key($0, timeZone: zone) })
        let checks = try context.fetch(FetchDescriptor<DailyBodyCheckIn>()).filter { $0.createdAt <= now && $0.updatedAt <= now && $0.date <= now && recoveryDays.contains(TrainingLocalDate.key($0.date, timeZone: zone)) }
        let recovery = checks.sorted { $0.date < $1.date }.map { "\(TrainingLocalDate.key($0.date, timeZone: zone))：体感\($0.conditionScore)；\($0.discomfortNotes.isEmpty ? "细节未知" : $0.discomfortNotes)" }
        for day in recoveryDays.sorted() where !checks.contains(where: { TrainingLocalDate.key($0.date, timeZone: zone) == day }) { unknowns.append("\(day)次晨恢复未取得或尚未到达。") }
        return CoachWeekOutcome(draftID: draft.id, capturedAt: now, sessionIDs: Array(Set(actual.map(\.sessionID))).sorted { $0.uuidString < $1.uuidString },
            actual: actual, recovery: recovery, unknowns: unknowns, ropeActual: ropes, scheduleIDs: Array(scheduleIDs).sorted { $0.uuidString < $1.uuidString }, rootID: draft.rootID, sourceFingerprint: draft.sourceFingerprint, provenance: provenance)
    }

    private static let compoundRoles = ["水平推", "垂直推", "水平拉", "垂直拉", "髋铰链", "髋伸", "膝主导"]

    private static func specifiedMain(_ item: CoachWeekCatalogItem, focus: String) -> Bool {
        let pair = "\(item.name)|\(item.equipment)"
        let canonical = item.approvedCanonicalID ?? ""
        if focus.contains("胸") {
            return ["史密斯卧推|史密斯机", "杠铃卧推|杠铃", "上斜哑铃卧推|哑铃", "MTS 下斜卧推|器械",
                    "MTS 卧推|MTS 器械", "上斜卧推|杠铃", "史密斯上斜卧推|史密斯机", "器械上斜卧推|器械", "器械下斜卧推|器械"].contains(pair)
                || ["smith_machine_bench_press", "smith_machine_incline_bench_press", "barbell_bench_press", "dumbbell_bench_press", "incline_dumbbell_bench_press"].contains(canonical)
        }
        if focus.contains("背") {
            return ["高位下拉|器械", "坐姿划船|器械", "杠铃划船|杠铃", "MTS 划船|MTS 器械",
                    "胸托T-Bar划船|胸托T-Bar划船机", "胸托划船|器械或哑铃", "胸托划船|器械",
                    "双滑轮高位下拉|双滑轮器械", "双滑轮低位划船|双滑轮器械", "中立握高位下拉|器械",
                    "双滑轮高位下拉|器械", "上斜凳胸托哑铃划船|哑铃", "单臂哑铃划船|哑铃"].contains(pair)
                || ["machine_seated_row", "barbell_row", "lat_pulldown", "close_grip_lat_pulldown"].contains(canonical)
        }
        if ["腿", "前链", "后链", "综合"].contains(where: focus.contains) {
            return ["深蹲|杠铃", "罗马尼亚硬拉|杠铃", "哈克深蹲|哈克深蹲机", "传统硬拉|杠铃",
                    "钟摆深蹲|器械", "颈前深蹲|杠铃"].contains(pair)
                || ["landmine_zercher_squat", "barbell_conventional_deadlift", "barbell_romanian_deadlift", "barbell_squat"].contains(canonical)
        }
        return false
    }

    private static func shoulderHeads(_ item: CoachWeekCatalogItem, focus: String) -> Set<String> {
        guard focus.contains("肩"), isMain(item, focus: focus) else { return [] }
        var heads = Set<String>()
        if item.roles.contains("垂直推") { heads.insert("前") }
        if item.roles.contains("肩外展") { heads.insert("中") }
        if item.roles.contains("肩水平外展") { heads.insert("后") }
        return heads
    }

    private static func knownWorkSet(_ set: WorkoutSetPlan) -> Bool {
        guard let prescription = set.prescription, prescription.isValid else { return false }
        return ["重主项", "中等辅助", "轻负荷正式任务", "工作组"].contains(prescription.label)
    }

    private struct CoreCoverage {
        private struct Group {
            var names = Set<String>()
            var canonicalIDs = Set<String>()
        }
        private var groups: [Group] = []
        var count: Int { groups.count }

        private func normalized(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func contains(name: String, canonicalID: String?) -> Bool {
            let name = normalized(name)
            return groups.contains { group in group.names.contains(name) || canonicalID.map { group.canonicalIDs.contains($0) } == true }
        }
        mutating func add(name: String, canonicalID: String? = nil) {
            let name = normalized(name)
            guard !name.isEmpty else { return }
            let matches = groups.indices.filter { index in groups[index].names.contains(name) || canonicalID.map { groups[index].canonicalIDs.contains($0) } == true }
            var merged = Group()
            merged.names.insert(name)
            if let canonicalID { merged.canonicalIDs.insert(canonicalID) }
            for index in matches.reversed() {
                let group = groups.remove(at: index)
                merged.names.formUnion(group.names); merged.canonicalIDs.formUnion(group.canonicalIDs)
            }
            groups.append(merged)
        }
    }

    private static func coreCoverage(_ days: [CoachWeekDay], input: CoachWeekInput) -> CoreCoverage {
        var coverage = CoreCoverage()
        let end = input.preferences.last?.localDay ?? input.startDay
        for day in days where day.localDay >= input.startDay && day.localDay <= end && day.kind == .strength
            && input.capturedLocalDay.map({ day.localDay >= $0 }) == true {
            for movement in day.movements where movement.roles.contains("腹部") && movement.exercise.plannedSets.contains(where: knownWorkSet) {
                let item = input.catalog.first { $0.id == movement.id }
                coverage.add(name: movement.exercise.catalogName, canonicalID: item?.approvedCanonicalID)
            }
        }
        for existing in input.existing where existing.source == "日程" && existing.status == "planned"
            && existing.localDay >= input.startDay && existing.localDay <= end
            && input.capturedLocalDay.map({ existing.localDay >= $0 }) == true {
            for movement in existing.frozenExercises ?? [] where movement.roles.contains("腹部") && movement.plannedSets.contains(where: knownWorkSet) {
                coverage.add(name: movement.name)
            }
        }
        for actual in input.history where actual.localDay >= input.startDay && actual.localDay <= end
            && actual.classificationKnown == true && actual.actual.contains(where: { $0.completed && !$0.warmup }) {
            let role = roleEvidence(name: actual.name, equipment: actual.equipment ?? "", canonicalID: nil,
                                    exerciseID: actual.exerciseID, ruleMethod: input.methodVersion)
            if role.roles.contains("腹部") { coverage.add(name: actual.name) }
        }
        return coverage
    }

    private static func isMain(_ item: CoachWeekCatalogItem, focus: String, method: String? = nil) -> Bool {
        if method == methodVersion && ["腿", "前链", "后链", "综合"].contains(where: focus.contains)
            && (item.muscle.contains("小腿") || item.roles.contains("踝跖屈")) { return false }
        if focus.contains("后链") {
            return item.roles.contains { ["髋铰链", "髋伸", "屈膝", "后侧控制", "髋伸控制"].contains($0) } && !item.roles.contains("技术")
        }
        if focus.contains("前链") {
            return item.roles.contains { ["膝主导", "伸膝", "单腿"].contains($0) }
        }
        if focus.contains("腿") || focus.contains("综合") {
            return (item.muscle.contains("腿") || item.muscle.contains("臀")) && !item.roles.contains("技术")
        }
        return ["胸", "背", "肩"].first(where: focus.contains).map { item.muscle.contains($0) && !item.roles.contains("技术") } ?? false
    }

    static func revalidateStrength(_ day: CoachWeekDay, input: CoachWeekInput) -> CoachWeekDay {
        guard day.kind == .strength else { return day }
        if input.methodVersion == alternatingMethodVersion { return revalidateAlternatingStrength(day, input: input) }
        var result = day
        let prefixes = ["动作数", "主肌群动作", "主肌群不足", "重点复合", "无法识别本课", "逐组处方", "估时", "动作身份", "仅有", "后链任务", "前链任务", "负荷角色", "指定主项", "肩束", "辅助肌群"]
        result.blockers.removeAll { message in prefixes.contains(where: message.hasPrefix) }
        var identities = Set<UUID>()
        result.movements = day.movements.map { movement in
            var updated = movement
            guard let item = input.catalog.first(where: { $0.id == movement.id }), !item.archived,
                  item.name == movement.exercise.catalogName, item.equipment == movement.exercise.equipment,
                  item.unit == movement.exercise.volumeUnit, !item.roles.isEmpty,
                  !requiresAnkleAttachment(name: item.name, equipment: item.equipment), identities.insert(item.id).inserted else {
                result.blockers.append("动作身份、角色或器械与来源不一致。")
                return updated
            }
            let technical = item.roles.contains("技术")
            let markedMain = isMain(item, focus: day.focus, method: input.methodVersion) && item.roles.contains(where: compoundRoles.contains) && movement.exercise.plannedSets.count >= 4
            let labels = Set(movement.exercise.plannedSets.compactMap { $0.prescription?.label })
            let declared = labels.count == 1 ? labels.first : nil
            let allowed = ["重主项", "中等辅助", "轻负荷正式任务", "技术/速度"]
            updated.loadRole = declared.flatMap { allowed.contains($0) ? $0 : nil }
                ?? (technical ? "技术/速度" : markedMain ? "重主项" : item.roles.contains(where: compoundRoles.contains) || item.roles.contains("单腿") ? "中等辅助" : "轻负荷正式任务")
            if (updated.loadRole == "技术/速度") != technical || (updated.loadRole == "重主项" && !markedMain) {
                result.blockers.append("负荷角色与真实任务或主项组数不符。")
            }
            updated.roles = item.roles
            updated.roleSource = item.roleSource
            updated.unilateral = item.roles.contains { ["单腿", "单侧", "侧向单腿"].contains($0) }
                || movement.exercise.plannedSets.contains { $0.repsSide == .single }
            return updated
        }
        let catalog = result.movements.compactMap { movement in input.catalog.first { $0.id == movement.id } }
        if !(6...8).contains(result.movements.count) { result.blockers.append("动作数需为6–8个。") }
        let lower = ["前链", "后链", "综合", "腿"].contains(where: day.focus.contains)
        let newPolicy = input.methodVersion == methodVersion
        var distinctMain = CoreCoverage()
        for item in catalog where isMain(item, focus: day.focus, method: input.methodVersion) { distinctMain.add(name: item.name, canonicalID: item.approvedCanonicalID) }
        let mainCount = newPolicy ? distinctMain.count : catalog.filter({ isMain($0, focus: day.focus, method: input.methodVersion) }).count
        if (lower || ["胸", "背"].contains(where: day.focus.contains) || (newPolicy && day.focus.contains("肩"))) && mainCount < 4 {
            result.blockers.append("主肌群动作不足4个。")
        }
        if newPolicy {
            if lower || ["胸", "背"].contains(where: day.focus.contains) {
                let mainName = day.focus.contains("胸") ? "卧推" : day.focus.contains("背") ? "划船/下拉" : "深蹲/硬拉"
                let hasMain = result.movements.contains { movement in
                    guard let item = input.catalog.first(where: { $0.id == movement.id }), isMain(item, focus: day.focus, method: input.methodVersion),
                          specifiedMain(item, focus: day.focus) else { return false }
                    return movement.exercise.plannedSets.filter(knownWorkSet).count >= 4
                }
                if !hasMain { result.blockers.append("指定主项\(mainName)缺少至少4个可核对工作组；热身不计。") }
            }
            if day.focus.contains("肩") {
                let covered = catalog.reduce(into: Set<String>()) { $0.formUnion(shoulderHeads($1, focus: day.focus)) }
                let missing = Set(["前", "中", "后"]).subtracting(covered).sorted()
                if !missing.isEmpty { result.blockers.append("肩束覆盖不足：缺\(missing.joined(separator: "、"))束可核对动作。") }
            }
            let secondary = Set(catalog.compactMap { item -> String? in
                if isMain(item, focus: day.focus, method: input.methodVersion) { return nil }
                if item.muscle.contains("小腿") || item.roles.contains("踝跖屈") { return "足踝" }
                if lower && (item.muscle.contains("腿") || item.muscle.contains("臀")) { return nil }
                if item.roles.contains("腹部") { return "核心" }
                return ["手臂", "肩", "胸", "背", "腿", "臀", "核心"].first { item.muscle.contains($0) }
            })
            let maximumGroups = input.preferences.first { $0.localDay == day.localDay }?.snapshot?.maxFocusAreasPerSession ?? 2
            if secondary.count + 1 > maximumGroups { result.blockers.append("辅助肌群超过当日上限；腹部不能与其他辅助肌群叠加凑数。") }
        }
        if day.focus.contains("后链") && catalog.contains(where: { $0.roles.contains { ["膝主导", "伸膝"].contains($0) } }) {
            result.blockers.append("后链任务含明确前链主导动作，须重新明确任务；腿部标签不能替代后链角色。")
        }
        if !result.movements.contains(where: { movement in
            guard let item = input.catalog.first(where: { $0.id == movement.id }) else { return false }
            return isMain(item, focus: day.focus, method: input.methodVersion) && item.roles.contains(where: compoundRoles.contains) && movement.exercise.plannedSets.count >= 4
        }) { result.blockers.append("重点复合主项需至少4组。") }
        if result.movements.contains(where: { movement in
            movement.exercise.plannedSets.count < 3 || movement.exercise.plannedSets.contains { set in
                !set.weight.isFinite || set.weight < 0 || set.reps <= 0 || set.prescription?.isValid != true
                    || set.prescription?.repsLower != set.reps || set.actualDefaultPolicy != .blank
                    || (set.prescription?.restUpperSeconds ?? 0) < (movement.roles.contains(where: compoundRoles.contains) ? 120 : 60)
            }
        }) { result.blockers.append("逐组处方无效、休息不足或常规动作少于3组。") }
        let loadRoles = Set(result.movements.compactMap(\.loadRole))
        if !Set(["重主项", "中等辅助", "轻负荷正式任务"]).isSubset(of: loadRoles) {
            result.blockers.append("负荷角色需同时包含重主项、中等辅助和轻负荷正式任务；技术组不替代抗阻角色。")
        }
        // General preparation + buffer, then specific preparation, every repetition,
        // side change, between-set rests and equipment transitions. No cached estimate.
        if result.movements.contains(where: { movement in
            movement.roles.contains("技术") ? movement.exercise.plannedSets.contains { $0.prescription?.rirLower != nil }
                : movement.exercise.plannedSets.contains { $0.prescription?.rirLower == nil || $0.prescription?.rirUpper == nil }
        }) { result.blockers.append("逐组处方缺少目标努力，或技术动作错误使用RIR。") }
        let seconds = 960 + result.movements.reduce(0) { total, movement in
            let sets = movement.exercise.plannedSets
            let work = sets.reduce(0) { subtotal, set in
                let upper = set.prescription?.repsUpper ?? set.reps
                return subtotal + max(40, upper * 3) * (movement.unilateral ? 2 : 1) + (movement.unilateral ? 30 : 0)
            }
            let rest = sets.dropLast().reduce(0) { $0 + ($1.prescription?.restUpperSeconds ?? 0) }
            let preparation = movement.roles.contains(where: compoundRoles.contains) ? 120 : 60
            return total + work + rest + preparation + 90
        }
        result.estimatedSeconds = seconds
        let maximum = min(90, input.preferences.first { $0.localDay == day.localDay }?.snapshot?.sessionMinutesUpper ?? 90)
        if seconds > maximum * 60 { result.blockers.append("估时\(seconds / 60)分钟超过当日\(maximum)分钟上限。") }
        result.blockers = Array(Set(result.blockers)).sorted()
        return result
    }

    private enum AlternatingFocus {
        case chestShoulder, backCore, upperCombined, lowerAnterior, lowerPosterior, lowerCombined
        case chest, back, shoulder, legs
    }

    private static func alternatingFocus(_ focus: String) -> AlternatingFocus? {
        switch focus {
        case "胸肩", "胸+肩膀", "胸+肩": return .chestShoulder
        case "背腹", "背+腹": return .backCore
        case "胸背肩综合", "胸背肩膀综合": return .upperCombined
        case "前链": return .lowerAnterior
        case "后链": return .lowerPosterior
        case "腿部综合", "综合": return .lowerCombined
        case "胸": return .chest
        case "背": return .back
        case "肩": return .shoulder
        case "腿": return .legs
        default: return nil
        }
    }

    private static func alternatingHeads(_ item: CoachWeekCatalogItem) -> Set<String> {
        var result = Set<String>()
        if item.roles.contains("垂直推") { result.insert("前") }
        if item.roles.contains("肩外展") { result.insert("中") }
        if item.roles.contains("肩水平外展") { result.insert("后") }
        return result
    }

    private static func alternatingSpecial(_ item: CoachWeekCatalogItem) -> Bool {
        let name = item.name.lowercased()
        return item.unit != .kilogram || item.roles.contains("技术")
            || ["深蹲", "硬拉", "squat", "deadlift", "高翻", "power clean"].contains(where: name.contains)
    }

    private static let alternatingDropInstruction = "第4工作组后在安全且能迅速换档时立即降重继续同一动作；降重幅度和次数按器械及动作质量现场确认；无保护或状态不佳则省略，不计第五个工作组。"

    private static func alternatingDropEligible(_ item: CoachWeekCatalogItem) -> Bool {
        !alternatingSpecial(item) && item.unit == .kilogram && item.roles.contains(where: compoundRoles.contains)
            && ["器械", "MTS", "龙门架", "史密斯", "machine", "cable"].contains { item.equipment.localizedCaseInsensitiveContains($0) }
    }

    private static func alternatingMain(_ item: CoachWeekCatalogItem, focus: String) -> Bool {
        if focus == "胸" && "\(item.name)|\(item.equipment)" == "Smith Bench Press|史密斯机" { return true }
        return specifiedMain(item, focus: focus)
    }

    private static func makeAlternatingStrength(day: String, goal: CoachWeekGoal, input: CoachWeekInput,
                                                 priorDays: [CoachWeekDay], futureStrengthDays: Int = 0) -> CoachWeekDay {
        guard let focus = alternatingFocus(goal.focus) else {
            return CoachWeekDay(localDay: day, kind: .strength, title: goal.focus + "力量", focus: goal.focus,
                movements: [], cardio: nil, estimatedSeconds: nil, rationale: [goal.reason],
                blockers: ["轮换规则：课型无法识别，请选择胸肩、背腹、胸背肩综合、前链、后链或腿部综合。"], existing: [])
        }
        let candidates = input.catalog.filter {
            !$0.archived && !$0.roles.isEmpty && !$0.equipment.isEmpty && !requiresAnkleAttachment(name: $0.name, equipment: $0.equipment)
        }
        let priorCore = coreCoverage(priorDays, input: input)
        var selected: [CoachWeekCatalogItem] = []
        var identities = CoreCoverage()
        func take(_ count: Int, where matches: (CoachWeekCatalogItem) -> Bool, priority: (CoachWeekCatalogItem) -> Int) {
            let pool = candidates.filter(matches).sorted { lhs, rhs in
                let left = priority(lhs), right = priority(rhs)
                if left != right { return left > right }
                let lh = input.history.contains { $0.exerciseID == lhs.id && $0.actual.contains { $0.completed } }
                let rh = input.history.contains { $0.exerciseID == rhs.id && $0.actual.contains { $0.completed } }
                if lh != rh { return lh }
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                return comparison == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
            }
            var added = 0
            for item in pool where added < count {
                guard !identities.contains(name: item.name, canonicalID: item.approvedCanonicalID),
                      !selected.contains(where: { $0.id == item.id }) else { continue }
                selected.append(item); identities.add(name: item.name, canonicalID: item.approvedCanonicalID); added += 1
            }
        }
        func chest(_ item: CoachWeekCatalogItem) -> Bool { item.muscle.contains("胸") && !item.roles.contains("腹部") }
        func back(_ item: CoachWeekCatalogItem) -> Bool { item.muscle.contains("背") && !item.roles.contains("腹部") }
        func shoulder(_ item: CoachWeekCatalogItem) -> Bool { item.muscle.contains("肩") && !alternatingHeads(item).isEmpty }
        func core(_ item: CoachWeekCatalogItem) -> Bool { item.roles.contains("腹部") && !priorCore.contains(name: item.name, canonicalID: item.approvedCanonicalID) }
        func coreRank(_ item: CoachWeekCatalogItem) -> Int {
            (item.unit == .kilogram && !["未知", "未记录", "自重"].contains(item.equipment) ? 2 : 0) + (item.roles.contains("侧腹") ? 1 : 0)
        }
        func takeShoulders(_ count: Int) {
            for head in ["前", "中", "后"] where selected.filter(shoulder).count < count {
                take(1, where: { shoulder($0) && alternatingHeads($0).contains(head) }, priority: { _ in 0 })
            }
            take(max(0, count - selected.filter(shoulder).count), where: shoulder, priority: { _ in 0 })
        }
        func lower(_ item: CoachWeekCatalogItem) -> Bool {
            guard !item.roles.contains("技术") && !item.roles.contains("踝跖屈") else { return false }
            switch focus {
            case .lowerAnterior: return item.roles.contains { ["膝主导", "伸膝", "单腿"].contains($0) }
            case .lowerPosterior: return item.roles.contains { ["髋铰链", "髋伸", "屈膝", "后侧控制", "髋伸控制"].contains($0) }
            default: return (item.muscle.contains("腿") || item.muscle.contains("臀")) && !item.roles.contains("腹部")
            }
        }
        switch focus {
        case .chestShoulder:
            take(4, where: chest, priority: { alternatingMain($0, focus: "胸") ? 1 : 0 }); takeShoulders(4)
        case .backCore:
            take(4, where: back, priority: { alternatingMain($0, focus: "背") ? 1 : 0 }); take(3, where: core, priority: coreRank)
        case .upperCombined:
            take(2, where: chest, priority: { alternatingMain($0, focus: "胸") ? 1 : 0 })
            take(2, where: back, priority: { alternatingMain($0, focus: "背") ? 1 : 0 })
            takeShoulders(3); take(1, where: core, priority: coreRank)
        case .lowerAnterior, .lowerPosterior, .lowerCombined, .legs:
            let missing = max(0, 4 - priorCore.count)
            let coreCount = min(2, max(0, missing - futureStrengthDays * 2))
            take(1, where: { lower($0) && alternatingMain($0, focus: "腿") }, priority: { _ in 0 })
            if focus == .lowerCombined || focus == .legs {
                if !selected.contains(where: { $0.roles.contains { ["膝主导", "伸膝", "单腿"].contains($0) } }) {
                    take(1, where: { lower($0) && $0.roles.contains { ["膝主导", "伸膝", "单腿"].contains($0) } },
                         priority: { alternatingSpecial($0) ? 0 : 1 })
                }
                if !selected.contains(where: { $0.roles.contains { ["髋铰链", "髋伸", "屈膝", "后侧控制"].contains($0) } }) {
                    take(1, where: { lower($0) && $0.roles.contains { ["髋铰链", "髋伸", "屈膝", "后侧控制"].contains($0) } },
                         priority: { alternatingSpecial($0) ? 0 : 1 })
                }
            }
            take(max(0, 4 - selected.count), where: lower, priority: { alternatingSpecial($0) ? 0 : 1 })
            take(coreCount, where: core, priority: coreRank)
            take(max(0, 6 - selected.count), where: lower, priority: { alternatingSpecial($0) ? 0 : 1 })
        case .chest:
            take(4, where: chest, priority: { alternatingMain($0, focus: "胸") ? 1 : 0 })
            take(2, where: core, priority: coreRank)
        case .back:
            take(4, where: back, priority: { alternatingMain($0, focus: "背") ? 1 : 0 })
            take(2, where: core, priority: coreRank)
        case .shoulder:
            takeShoulders(4); take(2, where: core, priority: coreRank)
        }
        var movements = selected.map { item -> CoachWeekMovement in
            let special = alternatingSpecial(item)
            let major = item.roles.contains(where: compoundRoles.contains) || item.roles.contains("单腿")
            let label = major ? "重主项" : "轻负荷正式任务"
            let rest = major ? 90 : 50
            let step = major ? 5.0 : 2.5
            let history = input.history.filter { $0.exerciseID == item.id && $0.localDay < day && $0.unit == item.unit && $0.equipment == item.equipment }
                .sorted { $0.localDay > $1.localDay }
            let reference = history.first { prior in
                prior.classificationKnown == true && prior.feelingRaw != WorkoutFeeling.painful.rawValue
                    && prior.actual.filter { $0.completed && !$0.warmup && (1...8).contains($0.reps) }.count >= 4
            }
            let historicalReps = reference.map { Array($0.actual.filter { $0.completed && !$0.warmup && (1...8).contains($0.reps) }.prefix(4)).map(\.reps) }
            let reps = special ? (historicalReps ?? [6, 6, 6, 6]) : [14, 12, 10, 8]
            let technical = item.roles.contains("技术")
            let guidance = special
                ? "特殊动作逐组单独核对；设备、计量侧别和负重未知时现场校准，不强套加重步长。"
                : "首组重量 W、器械档位和计量侧别需现场核对；条件目标 W、W+\(step)、W+\(step * 2)、W+\(step * 3) kg。未知不换算，热身与动作质量优先。"
            let plans = reps.enumerated().map { index, count in
                WorkoutSetPlan(weight: 0, reps: count, weightSide: .unknown, repsSide: .unknown, actualDefaultPolicy: .blank,
                    prescription: WorkoutSetPrescription(label: technical ? "技术/速度" : label, repsLower: count, repsUpper: count,
                        rirLower: technical ? nil : (index == 0 ? 2 : 1), rirUpper: technical ? nil : (index == 0 ? 3 : 2), restLowerSeconds: rest, restUpperSeconds: rest,
                        effortCue: technical ? "只在动作和速度稳定时进行，不做力竭或递减。" : "热身校准；疼痛、动作失稳或恢复不足时停止或调整。"))
            }
            let note = special ? "特殊动作：下列次数是待逐组核对的候选；热身不计入四个工作组。" : "四个有效工作组；准备及热身组另计。"
            let exercise = ConfirmedDailyPlanExercise(catalogExerciseID: item.id, catalogName: item.name, equipment: item.equipment,
                volumeUnit: item.unit, displayName: item.name, loadGuidance: guidance, notes: note, plannedSets: plans,
                planPattern: special ? .fixed : .pyramidUp)
            return CoachWeekMovement(exercise: exercise, roles: item.roles, roleSource: item.roleSource,
                reason: "按\(goal.focus)任务及已确认动作角色选择；器械和恢复需本人核实。",
                evidence: history.prefix(3).map { "\($0.localDay)同一动作和器械有原始记录；未将计划当实际。" },
                unknowns: ["重量、侧别、当前器械档位和当天恢复待核。"],
                unilateral: item.roles.contains { ["单腿", "单侧", "侧向单腿"].contains($0) }, loadRole: technical ? "技术/速度" : label,
                specialPrescriptionReviewed: special ? (historicalReps != nil) : nil)
        }
        if let index = movements.firstIndex(where: { movement in
            guard let item = selected.first(where: { $0.id == movement.id }) else { return false }
            return alternatingDropEligible(item)
        }), let fourth = movements[index].exercise.plannedSets.last {
            movements[index].plannedDrop = CoachWeekDropSegment(fourthSetID: fourth.id, instruction: alternatingDropInstruction, estimatedSeconds: 90)
            movements[index].exercise.notes += " " + alternatingDropInstruction
            movements[index].exercise.plannedSets[3].prescription?.effortCue = alternatingDropInstruction
        }
        var rationale = [goal.reason, "估时包含一般热身与缓冲、每项专项准备和转场、每个工作组、组间休息、单侧换边及递减段；恢复不足时延长休息并调整内容。"]
        if !movements.contains(where: { $0.plannedDrop != nil }) {
            rationale.append("尚无可核实适合安全快速降重的重点器械；递减段待现场确认或省略，不强行安排。")
        }
        let result = CoachWeekDay(localDay: day, kind: .strength, title: goal.focus + "力量", focus: goal.focus,
            movements: movements, cardio: nil, estimatedSeconds: nil, rationale: rationale, blockers: [], existing: [])
        return revalidateAlternatingStrength(result, input: input)
    }

    private static func revalidateAlternatingStrength(_ day: CoachWeekDay, input: CoachWeekInput) -> CoachWeekDay {
        var result = day
        result.blockers.removeAll { $0.hasPrefix("轮换规则：") }
        guard let focus = alternatingFocus(day.focus) else {
            result.blockers.append("轮换规则：课型无法识别，请明确课型。")
            return result
        }
        var seen = Set<UUID>()
        var identities = CoreCoverage()
        var items: [CoachWeekCatalogItem] = []
        for movement in result.movements {
            guard let item = input.catalog.first(where: { $0.id == movement.id }), !item.archived,
                  item.name == movement.exercise.catalogName, item.equipment == movement.exercise.equipment,
                  item.unit == movement.exercise.volumeUnit, !item.roles.isEmpty,
                  movement.roles == item.roles, seen.insert(item.id).inserted,
                  !requiresAnkleAttachment(name: item.name, equipment: item.equipment) else {
                result.blockers.append("轮换规则：动作身份、角色或器械与来源不一致。"); continue
            }
            items.append(item)
            if identities.contains(name: item.name, canonicalID: item.approvedCanonicalID) {
                result.blockers.append("轮换规则：同名或已确认同一身份的动作不能重复计入配额。")
            }
            identities.add(name: item.name, canonicalID: item.approvedCanonicalID)
            let sets = movement.exercise.plannedSets
            if sets.count != 4 || sets.contains(where: { !$0.weight.isFinite || $0.weight < 0 || $0.reps <= 0 || $0.actualDefaultPolicy != .blank || $0.prescription?.isValid != true || $0.prescription?.repsLower != $0.reps }) {
                result.blockers.append("轮换规则：\(item.name)必须有4个有效工作组且实际记录留空。")
            }
            if alternatingSpecial(item) {
                if movement.specialPrescriptionReviewed != true {
                    result.blockers.append("轮换规则：\(item.name)是特殊动作，须逐组单独设定并勾选核对。")
                }
            } else if sets.map(\.reps) != [14, 12, 10, 8] || movement.exercise.planPattern != .pyramidUp {
                result.blockers.append("轮换规则：\(item.name)的常规四组次数应为14/12/10/8；特殊情况需明确处理。")
            }
            let minimumRest = item.roles.contains(where: compoundRoles.contains) || item.roles.contains("单腿") ? 80 : 50
            if sets.contains(where: { ($0.prescription?.restLowerSeconds ?? 0) < minimumRest }) {
                result.blockers.append("轮换规则：\(item.name)休息低于已确认的计划起点；恢复不足时需增加休息并重新估时。")
            }
            if item.equipment == "未知" || item.equipment == "未记录" { result.blockers.append("轮换规则：\(item.name)器械未核实。") }
            if let drop = movement.plannedDrop {
                if sets.count != 4 || sets.last?.id != drop.fourthSetID || drop.estimatedSeconds != 90
                    || drop.instruction != alternatingDropInstruction || !movement.exercise.notes.contains(drop.instruction)
                    || sets.last?.prescription?.effortCue != drop.instruction || !alternatingDropEligible(item) {
                    result.blockers.append("轮换规则：\(item.name)递减段与第四组或动作说明不一致，须重新设置。")
                }
            } else if movement.exercise.notes.contains(alternatingDropInstruction)
                        || sets.contains(where: { $0.prescription?.effortCue == alternatingDropInstruction }) {
                result.blockers.append("轮换规则：\(item.name)的递减说明缺少绑定，无法计入时间。")
            }
        }
        if result.movements.filter({ $0.plannedDrop != nil }).count > 1 { result.blockers.append("轮换规则：每课最多安排一个重点动作递减段。") }
        if !(6...8).contains(result.movements.count) { result.blockers.append("轮换规则：力量课需6–8个身份可核对动作。") }
        let chest = items.filter { $0.muscle.contains("胸") && !$0.roles.contains("腹部") }
        let back = items.filter { $0.muscle.contains("背") && !$0.roles.contains("腹部") }
        let shoulders = items.filter { $0.muscle.contains("肩") && !alternatingHeads($0).isEmpty }
        let core = items.filter { $0.roles.contains("腹部") }
        let lower = items.filter { item in
            switch focus {
            case .lowerAnterior: return item.roles.contains { ["膝主导", "伸膝", "单腿"].contains($0) }
            case .lowerPosterior: return item.roles.contains { ["髋铰链", "髋伸", "屈膝", "后侧控制", "髋伸控制"].contains($0) }
            default: return (item.muscle.contains("腿") || item.muscle.contains("臀")) && !item.roles.contains("踝跖屈") && !item.roles.contains("技术")
            }
        }
        switch focus {
        case .chestShoulder: if chest.count < 4 || shoulders.count < 4 { result.blockers.append("轮换规则：胸肩课需至少4个胸部和4个肩部动作。") }
        case .backCore: if back.count < 4 || core.count < 3 { result.blockers.append("轮换规则：背腹课需至少4个背部和3个腹部动作。") }
        case .upperCombined: if chest.count < 2 || back.count < 2 || shoulders.count < 3 || core.count < 1 { result.blockers.append("轮换规则：综合课按已确认例外需要胸2、背2、肩3、腹1。") }
        case .lowerAnterior, .lowerPosterior, .lowerCombined, .legs: if lower.count < 4 { result.blockers.append("轮换规则：下肢课主肌任务至少4个。") }
        case .chest: if chest.count < 4 { result.blockers.append("轮换规则：胸部动作不足4个。") }
        case .back: if back.count < 4 { result.blockers.append("轮换规则：背部动作不足4个。") }
        case .shoulder: if shoulders.count < 4 { result.blockers.append("轮换规则：肩部动作不足4个。") }
        }
        let needsChest = [.chestShoulder, .upperCombined, .chest].contains(focus)
        let needsBack = [.backCore, .upperCombined, .back].contains(focus)
        let needsLower = [.lowerAnterior, .lowerPosterior, .lowerCombined, .legs].contains(focus)
        func hasMain(_ group: [CoachWeekCatalogItem], _ label: String) -> Bool {
            group.contains { item in alternatingMain(item, focus: label) && result.movements.first(where: { $0.id == item.id })?.exercise.plannedSets.filter(knownWorkSet).count == 4 }
        }
        if needsChest && !hasMain(chest, "胸") { result.blockers.append("轮换规则：胸部缺少4工作组的已确认卧推。") }
        if needsBack && !hasMain(back, "背") { result.blockers.append("轮换规则：背部缺少4工作组的已确认划船或下拉。") }
        if needsLower && !hasMain(lower, "腿") { result.blockers.append("轮换规则：下肢缺少4工作组的已确认深蹲或硬拉。") }
        if [.chestShoulder, .upperCombined, .shoulder].contains(focus) {
            let heads = shoulders.reduce(into: Set<String>()) { $0.formUnion(alternatingHeads($1)) }
            let missing = Set(["前", "中", "后"]).subtracting(heads).sorted()
            if !missing.isEmpty { result.blockers.append("轮换规则：肩部缺少\(missing.joined(separator: "、"))束动作。") }
        }
        let seconds = 960 + result.movements.reduce(0) { total, movement in
            let sets = movement.exercise.plannedSets
            let unilateral = movement.unilateral || sets.contains { $0.repsSide == .single }
            let work = sets.reduce(0) { sum, set in
                sum + max(40, (set.prescription?.repsUpper ?? set.reps) * 3) * (unilateral ? 2 : 1) + (unilateral ? 30 : 0)
            }
            return total + work + sets.dropLast().reduce(0) { $0 + ($1.prescription?.restUpperSeconds ?? 0) }
                + 60 + 60 + (movement.plannedDrop?.estimatedSeconds ?? 0)
        }
        result.estimatedSeconds = seconds
        let maximum = min(90, input.preferences.first { $0.localDay == day.localDay }?.snapshot?.sessionMinutesUpper ?? 90)
        if seconds > maximum * 60 { result.blockers.append("轮换规则：完整估时\(seconds / 60)分钟超过\(maximum)分钟，须调整后重验。") }
        result.blockers = Array(Set(result.blockers)).sorted()
        return result
    }

    private static func alternatingShortfalls(_ days: [CoachWeekDay], input: CoachWeekInput, start: Date, zone: TimeZone) -> [String] {
        let defaults = defaultGoals(start: start, zone: zone, ruleMethod: alternatingMethodVersion)
        let exceptionGoals = defaults.compactMap { goal in input.exception.flatMap { exception in
            goal.localDay >= exception.startDay && goal.localDay <= exception.endDay ? exception.goals.first { $0.localDay == goal.localDay } : nil
        } }
        let goals = exceptionGoals.count == 7 ? exceptionGoals : defaults
        let expectedStrength = goals.filter { $0.kind == .strength }.count
        let expectedCardio = goals.filter { $0.kind == .cardio }.count
        let strengths = days.filter { strengthState($0, input: input) == true }.count
        let cardios = days.filter { day in day.cardio != nil || day.zone2 != nil || (day.kind == .preserved && day.existing.contains { preservedCardioMode($0, input: input) != nil }) }.count
        var result: [String] = []
        if strengths != expectedStrength { result.append("力量目标\(expectedStrength)次，当前可核对\(strengths)次；差额待决定。") }
        if cardios != expectedCardio { result.append("有氧总目标\(expectedCardio)次，当前可核对\(cardios)次；可选择跳绳、单车或椭圆机。") }
        if exceptionGoals.count != 7 {
            let expected = Set(defaults.filter { $0.kind == .strength }.map(\.focus))
            let actual = Set(days.filter { $0.kind == .strength }.map(\.focus))
            for focus in expected.subtracting(actual).sorted() { result.append("默认\(focus)课型未被明确覆盖；保留安排需核对，不能猜测组合课。") }
        }
        if days.contains(where: { strengthState($0, input: input) == nil }) { result.append("部分日期类型未知，不能视为零暴露或休息。") }
        let count = coreCoverage(days, input: input).count
        let permitted = input.coreException.map { exception in
            validCoreException(exception, days: defaults.map(\.localDay)) && days.count == 7
                && days.allSatisfy { day in exception.goals.first(where: { $0.localDay == day.localDay }).map { matchesConfirmedGoal(day, goal: $0, input: input) } == true }
        } == true
        if count < 4 && !permitted { result.append("腹部每周至少4个不同动作，当前可核对\(count)个；其余待决定。") }
        return result
    }

    private static func makeStrength(day: String, goal: CoachWeekGoal, input: CoachWeekInput, priorDays: [CoachWeekDay], futureStrengthDays: Int = 0) -> CoachWeekDay {
        let newPolicy = input.methodVersion == methodVersion
        let availableShoulder = input.catalog.filter { !$0.archived && $0.muscle.contains("肩") && !$0.roles.isEmpty }.count
        let lowerSpecialty = ["前链", "后链", "综合"].contains(where: goal.focus.contains)
        let desiredRoles: Set<String> = goal.focus.contains("前链") ? ["膝主导", "伸膝", "单腿"]
            : goal.focus.contains("后链") ? ["髋铰链", "髋伸", "屈膝", "后侧控制", "髋伸控制", "髋伸速度", "单腿"]
            : ["膝主导", "髋铰链", "髋伸", "屈膝", "伸膝", "单腿"]
        func main(_ item: CoachWeekCatalogItem) -> Bool {
            isMain(item, focus: goal.focus, method: input.methodVersion)
        }
        var coverage = coreCoverage(priorDays, input: input)
        let missingCore = newPolicy ? max(0, 4 - coverage.count) : 0
        let requestedCore = min(4, max(min(2, missingCore), missingCore - futureStrengthDays * 2))
        func coreScore(_ item: CoachWeekCatalogItem) -> Int {
            let weighted = item.unit == .kilogram && !["", "未知", "未记录", "自重"].contains(item.equipment)
            return (weighted ? 2 : 0) + (item.roles.contains("侧腹") ? 1 : 0)
        }
        let corePool = input.catalog.filter { !$0.archived && $0.roles.contains("腹部") && !$0.equipment.isEmpty }
            .sorted { lhs, rhs in
                let left = coreScore(lhs), right = coreScore(rhs)
                if left != right { return left > right }
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                return comparison == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
            }
        var reservedCore = Set<UUID>()
        for item in corePool where reservedCore.count < requestedCore {
            let duplicate = coverage.contains(name: item.name, canonicalID: item.approvedCanonicalID)
            coverage.add(name: item.name, canonicalID: item.approvedCanonicalID)
            guard !duplicate else { continue }
            reservedCore.insert(item.id)
        }
        let secondary: String? = !reservedCore.isEmpty ? nil : goal.focus.contains("胸") ? (goal.focus.contains("三头") || availableShoulder < 2 ? "手臂" : "肩") : goal.focus.contains("背") || goal.focus.contains("肩") ? "手臂" : nil
        let candidates = input.catalog.filter { item in
            !item.archived && (main(item) || reservedCore.contains(item.id) || (goal.focus.contains("后链") && item.roles.contains { ["髋伸速度", "单腿"].contains($0) }) || (secondary.map { group in item.muscle.contains(group) } ?? false))
                && (!lowerSpecialty || reservedCore.contains(item.id) || item.roles.contains(where: desiredRoles.contains))
                && !item.roles.isEmpty && !item.equipment.isEmpty
                && !requiresAnkleAttachment(name: item.name, equipment: item.equipment)
        }
        let zone = TimeZone(identifier: input.timeZone) ?? .current
        let targetDate = TrainingLocalDate.date(day, timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let recent = input.history.filter { actual in
            guard let targetDate, let actualDate = TrainingLocalDate.date(actual.localDay, timeZone: zone) else { return false }
            let difference = calendar.dateComponents([.day], from: actualDate, to: targetDate).day ?? 0
            return difference > 0 && difference <= 7 && actual.actual.contains { $0.completed }
        }
        let recentIDs = Set(recent.map(\.exerciseID))
        let scheduledIDs = Set(priorDays.flatMap { $0.movements.map { $0.exercise.catalogExerciseID } }
            + input.existing.filter { isActive($0) && $0.source != "实际训练" && $0.localDay != day }.flatMap { $0.exerciseIDs ?? [] })
        let exposure = taskExposure(on: day, input: input, priorDays: priorDays)
        let exposedRoles = exposure.actualRoles.union(exposure.scheduledRoles)
        var selected: [CoachWeekCatalogItem] = []
        var selectedIdentities = CoreCoverage()
        var used = Set<String>()
        var remaining = candidates
        let maximumMovements = newPolicy ? min(8, max(6, 4 + reservedCore.count)) : 6
        while !remaining.isEmpty && selected.count < maximumMovements {
            remaining.sort { lhs, rhs in
                let mainCount = selected.filter(main).count
                if newPolicy && selected.isEmpty {
                    let lhsPrimary = main(lhs) && (goal.focus.contains("肩") ? lhs.roles.contains("垂直推") : specifiedMain(lhs, focus: goal.focus))
                    let rhsPrimary = main(rhs) && (goal.focus.contains("肩") ? rhs.roles.contains("垂直推") : specifiedMain(rhs, focus: goal.focus))
                    if lhsPrimary != rhsPrimary { return lhsPrimary }
                }
                if selected.isEmpty && goal.focus.contains("后链") {
                    let lhsHinge = lhs.roles.contains("髋铰链"), rhsHinge = rhs.roles.contains("髋铰链")
                    if lhsHinge != rhsHinge { return lhsHinge }
                }
                let lhsMain = main(lhs)
                let rhsMain = main(rhs)
                if mainCount < 4 && lhsMain != rhsMain { return lhsMain }
                if newPolicy && goal.focus.contains("肩") && lhsMain && rhsMain && mainCount < 4 {
                    let covered = selected.reduce(into: Set<String>()) { $0.formUnion(shoulderHeads($1, focus: goal.focus)) }
                    let lhsMissing = shoulderHeads(lhs, focus: goal.focus).subtracting(covered).count
                    let rhsMissing = shoulderHeads(rhs, focus: goal.focus).subtracting(covered).count
                    if lhsMissing != rhsMissing { return lhsMissing > rhsMissing }
                }
                if newPolicy && mainCount >= 4 && reservedCore.contains(lhs.id) != reservedCore.contains(rhs.id) {
                    return reservedCore.contains(lhs.id)
                }
                if input.personalRuleVersion == overlapRuleVersion {
                    let lhsExact = recentIDs.contains(lhs.id) || scheduledIDs.contains(lhs.id)
                    let rhsExact = recentIDs.contains(rhs.id) || scheduledIDs.contains(rhs.id)
                    if lhsExact != rhsExact { return !lhsExact }
                }
                if goal.focus.contains("后链") {
                    let lhsSupplement = lhs.roles.contains("单腿")
                    let rhsSupplement = rhs.roles.contains("单腿")
                    if lhsSupplement != rhsSupplement { return !lhsSupplement }
                }
                let lhsNew = lhs.roles.contains { !used.contains($0) }
                let rhsNew = rhs.roles.contains { !used.contains($0) }
                if lhsNew != rhsNew { return lhsNew }
                let lhsOverlap = lhs.roles.filter { exposedRoles.contains($0) }.count
                let rhsOverlap = rhs.roles.filter { exposedRoles.contains($0) }.count
                if lhsOverlap != rhsOverlap { return lhsOverlap < rhsOverlap }
                let lhsDate = input.history.filter { $0.exerciseID == lhs.id }.map(\.localDay).max()
                let rhsDate = input.history.filter { $0.exerciseID == rhs.id }.map(\.localDay).max()
                if let lhsDate, let rhsDate, lhsDate != rhsDate { return lhsDate < rhsDate }
                if (lhsDate == nil) != (rhsDate == nil) { return lhsDate != nil }
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                return comparison == .orderedSame && newPolicy ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
            }
            let item = remaining.removeFirst()
            let duplicate = selectedIdentities.contains(name: item.name, canonicalID: item.approvedCanonicalID)
            selectedIdentities.add(name: item.name, canonicalID: item.approvedCanonicalID)
            if newPolicy && duplicate { continue }
            selected.append(item); used.formUnion(item.roles)
        }
        let preference = input.preferences.first { $0.localDay == day }?.snapshot
        let compoundRoles = ["水平推", "垂直推", "水平拉", "垂直拉", "髋铰链", "髋伸", "膝主导"]
        let primaryID = (newPolicy && !goal.focus.contains("肩") ? selected.first { item in
            main(item) && specifiedMain(item, focus: goal.focus) && compoundRoles.contains(where: item.roles.contains)
        } : nil)?.id ?? selected.first { item in
            main(item) && compoundRoles.contains(where: item.roles.contains)
        }?.id
        selected.sort { lhs, rhs in
            if lhs.roles.contains("技术") != rhs.roles.contains("技术") { return lhs.roles.contains("技术") }
            if (lhs.id == primaryID) != (rhs.id == primaryID) { return lhs.id == primaryID }
            return false
        }
        let hasCompoundAssistant = selected.contains { item in
            item.id != primaryID && !item.roles.contains("技术")
                && (item.roles.contains(where: compoundRoles.contains) || item.roles.contains("单腿"))
        }
        let isolationAssistantID: UUID? = !newPolicy || primaryID == nil || hasCompoundAssistant ? nil : (
            selected.first { $0.id != primaryID && !$0.roles.contains("技术") && main($0) }?.id
                ?? selected.first { $0.id != primaryID && !$0.roles.contains("技术") }?.id
        )
        let movements = selected.map { item -> CoachWeekMovement in
            let compound = item.id == primaryID
            let technical = item.roles.contains("技术")
            let loadRole = technical ? "技术/速度" : compound ? "重主项" : item.roles.contains(where: compoundRoles.contains) || item.roles.contains("单腿") || item.id == isolationAssistantID ? "中等辅助" : "轻负荷正式任务"
            let count = compound ? 4 : 3
            let rest = item.roles.contains(where: compoundRoles.contains) ? 180 : 90
            let history = input.history.filter { actual in
                guard actual.exerciseID == item.id, let targetDate,
                      let actualDate = TrainingLocalDate.date(actual.localDay, timeZone: zone) else { return false }
                let age = calendar.dateComponents([.day], from: actualDate, to: targetDate).day ?? 0
                return age > 0 && age <= 180
            }.sorted { $0.localDay > $1.localDay }
            var evidence = history.prefix(3).map { prior in
                let summary = prior.classificationKnown == true
                    ? "\(prior.actual.filter { $0.completed && !$0.warmup }.count) 条完成非热身记录"
                    : "\(prior.actual.filter { $0.completed }.count) 条完成原始记录，热身/工作组性质未知"
                return "\(prior.localDay) 原动作 \(prior.name)：\(summary)；器械\(prior.equipment ?? "未知")。"
            }
            if recentIDs.contains(item.id) { evidence.append("过去7天有同UUID已完成记录；工作组性质和恢复需另核。") }
            if scheduledIDs.contains(item.id) { evidence.append("本周其他候选或保留冻结处方已安排同UUID；需审阅重复理由。") }
            let overlap = item.roles.filter { exposedRoles.contains($0) }
            if !overlap.isEmpty {
                let actualOverlap = item.roles.filter { exposure.actualRoles.contains($0) }
                let scheduledOverlap = item.roles.filter { exposure.scheduledRoles.contains($0) }
                if !actualOverlap.isEmpty { evidence.append("近期已完成原始快照存在相同任务：\(actualOverlap.joined(separator: "、"))；不是自动禁止重复。") }
                if !scheduledOverlap.isEmpty { evidence.append("周内候选/保留冻结处方存在相同任务：\(scheduledOverlap.joined(separator: "、"))；计划不当完成。") }
            }
            let genericEquipment: Set<String> = ["", "器械", "机器", "其他", "未知"]
            let comparable = history.first { prior in
                guard item.unit == .kilogram, prior.unit == item.unit, prior.equipment == item.equipment,
                      !genericEquipment.contains(item.equipment), prior.feelingRaw != WorkoutFeeling.painful.rawValue,
                      let convention = prior.loadConvention, !convention.isEmpty, convention != "unknown" else { return false }
                let indexed = prior.actual.enumerated().filter { $0.element.completed && !$0.element.warmup }
                guard indexed.count >= count else { return false }
                return indexed.allSatisfy { index, set in
                    let number = prior.actualSetNumbers.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? (index + 1)
                    guard prior.plannedSets.indices.contains(number - 1) else { return false }
                    let plan = prior.plannedSets[number - 1]
                    guard let weight = set.weight else { return false }
                    return weight > 0 && set.reps > 0 && set.weightSide != .unknown && set.repsSide != .unknown
                        && set.weightSide == plan.weightSide && set.repsSide == plan.repsSide
                }
            }
            let actual = comparable?.actual.filter { $0.completed && !$0.warmup } ?? []
            let chosen = Array(actual.prefix(count))
            let ascending = zip(chosen, chosen.dropFirst()).allSatisfy { ($0.weight ?? 0) <= ($1.weight ?? 0) }
            let usable = chosen.count == count && (preference?.preferredSetPlanPattern != .pyramidUp || ascending)
            let age = comparable.flatMap { TrainingLocalDate.date($0.localDay, timeZone: zone) }.flatMap { date in
                targetDate.flatMap { calendar.dateComponents([.day], from: date, to: $0).day }
            }
            let freeWeight = ["杠铃", "哑铃", "壶铃", "自重"].contains(item.equipment)
            let settingsComparable = freeWeight || (item.machineIdentity != nil && item.machineSettings != nil
                && comparable?.machineIdentity == item.machineIdentity && comparable?.machineSettings == item.machineSettings)
            let automatic = usable && settingsComparable && (age ?? 181) <= 42 && comparable?.classificationKnown == true
                && chosen.allSatisfy { ($0.rir ?? -1) >= 2 }
            if let estimate = comparable?.supplementaryLastRIR, let lastID = comparable?.supplementaryLastSetID ?? comparable?.actual.last?.id,
               chosen.contains(where: { $0.id == lastID }) {
                evidence.append("本人练后对末条的估计 RIR \(estimate)；仅绑定该末条，不计入实时记录的自动资格。")
            }
            let guidance: String
            if automatic {
                guidance = "同UUID、同设备与计量口径，近42天逐组实际及真实余力满足资格；以下为起点，热身再校准，不自动加重。"
            } else if usable {
                guidance = "人工参考候选，非自动负重建议；同动作同设备与计量口径的历史逐组仅作低置信度起点，首组热身及实际余力核准，不把未知余力当作目标余力。"
            } else {
                guidance = "重量留空；同设备、计量、侧别或完整逐组证据不足，按当天热身校准。"
            }
            if let comparable, usable { evidence.append("\(comparable.localDay)同UUID及同设备逐组：\(automatic ? "自动资格通过" : "人工参考，资格未全部满足")；\(comparable.loadConvention ?? "口径未知")。") }
            let sets = (0..<count).map { index in
                let prior = usable ? chosen[index] : nil
                let reps = prior.map { min(max(1, $0.reps), item.name.contains("罗马尼亚") ? 8 : 12) } ?? (item.name.contains("罗马尼亚") ? 6 : 8)
                return WorkoutSetPlan(weight: prior?.weight ?? 0, reps: reps, weightSide: prior?.weightSide ?? .unknown,
                    repsSide: prior?.repsSide ?? .unknown, actualDefaultPolicy: .blank,
                    prescription: WorkoutSetPrescription(label: loadRole, repsLower: reps, repsUpper: max(reps, min(reps + 2, item.name.contains("罗马尼亚") ? 8 : 12)),
                        rirLower: technical ? nil : (index == 0 ? 2 : 1), rirUpper: technical ? nil : (index == 0 ? 3 : 2), restLowerSeconds: rest, restUpperSeconds: rest,
                        effortCue: technical ? "快髋、速度与接续稳定；变慢、甩腰或失稳即停，不以RIR评估技术质量" : "热身校准；疼痛、动作失稳或连续表现下降时停止受影响动作"))
            }
            let exercise = ConfirmedDailyPlanExercise(catalogExerciseID: item.id, catalogName: item.name, equipment: item.equipment,
                volumeUnit: item.unit, displayName: item.name, loadGuidance: guidance,
                notes: "\(item.roles.joined(separator: "、"))；准备组另计。", plannedSets: sets,
                planPattern: item.unit == .kilogram && !technical ? (preference?.preferredSetPlanPattern ?? .fixed) : .fixed)
            return CoachWeekMovement(exercise: exercise, roles: item.roles, roleSource: item.roleSource,
                reason: "\(loadRole)：承担\(item.roles.joined(separator: "、"))；专项任务优先，近期实际和周内冻结安排分开比较。", evidence: Array(evidence),
                unknowns: (history.isEmpty ? ["180天内未找到该动作的可见记录；不等于零暴露。"] : [])
                    + (item.equipment == "器械" ? ["具体机器身份未知，现场核对机器并校准，不能据此认定与历史同机。"] : [])
                    + (automatic ? [] : ["实际RIR、当前器械设置或完整负重资格未充分核实，需校准。"]), unilateral: item.roles.contains { ["侧向单腿", "单腿", "单侧"].contains($0) }, loadRole: loadRole)
        }
        let seconds = 600 + 300 + movements.reduce(0) { total, item in
            let count = item.exercise.plannedSets.count
            return total + count * 40 * (item.unilateral ? 2 : 1) + max(0, count - 1) * (item.exercise.plannedSets.first?.prescription?.restUpperSeconds ?? 90) + 90
        }
        var blockers: [String] = []
        if primaryID == nil { blockers.append("无法识别本课主肌群复合重点动作，须明确主项及其四组。") }
        if movements.count < 6 { blockers.append("仅有\(movements.count)个具备已确认角色的动作，正常课需6–8个；不要用名称猜补。") }
        if (lowerSpecialty || ["胸", "背", "腿"].contains(where: goal.focus.contains)) && selected.filter(main).count < 4 { blockers.append("主肌群不足4个适当抗阻动作。") }
        if seconds > 5400 { blockers.append("估时\(seconds / 60)分钟超过90分钟；须调整任务、剂量或明确例外。") }
        if movements.contains(where: { $0.exercise.equipment == "未知" }) { blockers.append("器械类型未知，须确认后再安排。") }
        let result = CoachWeekDay(localDay: day, kind: .strength, title: goal.focus + "力量", focus: goal.focus, movements: movements,
            cardio: nil, estimatedSeconds: seconds, rationale: [goal.reason, "晨练供能未知，不自动减重。仅当日本人明确仅咖啡/电解质且供能不足时，首个负重主项沿已确认例外下调5%–10%，目标RIR3–4并现场校准；不是长期默认。", "估时包含8分钟一般热身、8分钟缓冲、每项专项准备、逐组次数上限每次3秒（至少40秒）、双侧执行/换侧、休息上限及每项90秒转场。"], blockers: blockers, existing: [])
        var reviewed = result
        reviewed.rationale += exposure.unknowns
        return revalidateStrength(reviewed, input: input)
    }
}
