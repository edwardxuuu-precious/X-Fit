import Foundation
import SwiftData

enum TrainingSplitStyle: String, Codable, CaseIterable {
    case bodyPartSplit
    case upperLowerAlternating

    var title: String {
        switch self {
        case .bodyPartSplit: return "四日部位分化"
        case .upperLowerAlternating: return "上下肢周交替"
        }
    }
}

struct TrainingPreferenceSnapshot: Codable, Hashable {
    var revisionCode: String
    var splitStyle: TrainingSplitStyle
    var strengthDaysPerWeek: Int
    var maxFocusAreasPerSession: Int
    var sessionMinutesLower: Int
    var sessionMinutesUpper: Int
    var preferredTrainingTime: String
    var preferredLocations: [String]
    var avoidsRunning: Bool
    var jumpRopeSessionsPerWeek: Int
    var zone2SessionsPerWeek: Int
    var zone2Minutes: Int
    var foundationalMuscleGroups: [String]
    var extraVolumeMuscleGroups: [String]
    var constraints: [String]
    /// Missing in legacy snapshots; their original fixed-weight behavior remains unchanged.
    var preferredSetPlanPattern: SetPlanPattern? = nil
    /// Nil retains the historical separately counted cardio goals.
    var totalCardioSessionsPerWeek: Int? = nil

    func defaultPattern(for exercise: Exercise) -> SetPlanPattern {
        let name = exercise.name.lowercased()
        guard exercise.volumeUnit == .kilogram,
              !["高翻", "抓举", "power clean"].contains(where: name.contains) else { return .fixed }
        return preferredSetPlanPattern ?? .fixed
    }

    static let confirmed = TrainingPreferenceSnapshot(
        revisionCode: "TP-20260908-01",
        splitStyle: .bodyPartSplit,
        strengthDaysPerWeek: 4,
        maxFocusAreasPerSession: 2,
        sessionMinutesLower: 60,
        sessionMinutesUpper: 90,
        preferredTrainingTime: "早晨",
        preferredLocations: ["商业健身房", "家中"],
        avoidsRunning: true,
        jumpRopeSessionsPerWeek: 2,
        zone2SessionsPerWeek: 1,
        zone2Minutes: 30,
        foundationalMuscleGroups: ["胸部", "背部", "腿部", "臀部"],
        extraVolumeMuscleGroups: ["肩部", "手臂"],
        constraints: [
            "每次聚焦 1–2 个肌群，避免全身混合训练",
            "大肌群优先保留力量与有效训练量，肩部和手臂安排额外组数",
            "早晨只有咖啡和电解质饮料时，首个主项按上次工作重量下调 5%–10%，保留 3–4 RIR",
            "不跑步；跳绳出现足踝或膝部不适时改为低冲击有氧",
            "肌酐偏高且医生要求控制肉量；训练编排不得推导高蛋白或营养处方"
        ]
    )

    static let weekdayFocused: TrainingPreferenceSnapshot = {
        var snapshot = confirmed
        snapshot.revisionCode = "TP-20260908-02"
        snapshot.constraints = [
            "每次只聚焦 1 个主肌群与 1 个辅助肌群，不采用全身混合训练",
            "工作日完成全部核心力量训练；周末默认休息，短有氧仅在本人主动选择时安排",
            "胸部单次 14–16 个有效组、背部单次 16–18 个有效组；肩臂专门日 24–28 个有效组",
            "复合动作主组保留 1–2 RIR，随后完成 2–3 个减重组；孤立动作最后一组可到 0–1 RIR",
            "热身和递增组不计入有效容量；连续两个动作表现下降超过约 10% 或训练达到 90 分钟时停止追加孤立组",
            "早晨只有咖啡和电解质饮料时，首个主项按上次工作重量下调 5%–10%，保留 3–4 RIR",
            "不跑步；跳绳出现足踝或膝部不适时改为低冲击有氧",
            "Notes 重量口径尚未明确，不把其中数字自动换算为公斤、总重、单边、单只或一对",
            "肌酐偏高且医生要求控制肉量；训练编排不得推导高蛋白或营养处方"
        ]
        return snapshot
    }()

    static let lowerBodySpecialtyWeek: TrainingPreferenceSnapshot = {
        var snapshot = weekdayFocused
        snapshot.revisionCode = "TP-20260914-03"
        snapshot.strengthDaysPerWeek = 3
        snapshot.jumpRopeSessionsPerWeek = 2
        snapshot.zone2SessionsPerWeek = 0
        snapshot.foundationalMuscleGroups = ["腿部", "臀部", "小腿"]
        snapshot.extraVolumeMuscleGroups = []
        snapshot.constraints = [
            "仅用于 2026-09-14 至 2026-09-20 的下肢专项周；9 月 21 日后不自动生成计划",
            "三次力量分别覆盖前链、后链和前后链整合，并在每次加入踝背屈活动度与小腿/跟腱刚性训练",
            "高消耗来自复合动作、单侧动作和短间歇收尾，不以动作变形或疼痛换取消耗",
            "农夫走按 6×30 米记录距离，总距离 180 米；负重在备注中按每只哑铃记录",
            "跳绳主训练保持 RPE 6–7，即呼吸加快但仍能说短句、结束后感觉还能继续约 3–4 分钟",
            "当前足踝、膝和腰背无异常；出现新发疼痛、肿胀或落地不稳时立即停止跳跃并改低冲击有氧",
            "Notes 重量口径不明确时保留原值和器械类别，不自动换算",
            "肌酐偏高且医生要求控制肉量；训练编排不得推导高蛋白或营养处方"
        ]
        return snapshot
    }()

    static let upperBodyTravelWeek: TrainingPreferenceSnapshot = {
        var snapshot = weekdayFocused
        snapshot.revisionCode = "TP-20260921-04"
        snapshot.sessionMinutesLower = 45
        snapshot.sessionMinutesUpper = 75
        snapshot.preferredLocations = ["商业健身房", "酒店健身房"]
        snapshot.jumpRopeSessionsPerWeek = 0
        snapshot.zone2SessionsPerWeek = 2
        snapshot.foundationalMuscleGroups = ["胸部", "背部", "核心"]
        snapshot.extraVolumeMuscleGroups = ["肩部", "手臂"]
        snapshot.constraints = [
            "仅用于 2026-09-21 至 2026-09-27 澳大利亚旅行周；临时允许周一至周三连续力量，周三减量45–60分钟，不排重腿，不自动续排",
            "周一胸肩15组、周二背腹16组、周三胸肩12组、周六酒店背腹16组；手臂穿插，热身不计工作组",
            "左肘个别动作轻微不适超过两周、尚未评估；不作确诊，建议出发前运动医学或物理治疗评估",
            "首个工作组 RIR 3，其余 RIR 2–3；不做力竭、递减组或重握力收尾；负重留空待当天热身确定，不自动套用历史重量",
            "疼痛、逐组加重或代偿时停止动作；弯举、下压可以省去不补组；次晨更不舒服时取消下一次直接手臂训练，并减少或暂停诱发不适的推拉动作",
            "明显无力、麻木、肿热或活动受限时先评估；低能量或旅途疲劳时减量或休息，不追纪录",
            "周四、周五轻松单车或椭圆机20–30分钟，周四最多30分钟且可休息；能说完整句子，不用力拉推椭圆机把手",
            "酒店无有氧器械且左肘足踝无不适时可选8–10轮跳30秒／步行休60秒；非30分钟单车等量替代，不能代替背部力量；转腕不适改步行",
            "不跑步；医学营养限制沿用既有偏好，不推导高蛋白目标或营养处方"
        ]
        return snapshot
    }()

    static let postTravelRestoration: TrainingPreferenceSnapshot = {
        var snapshot = weekdayFocused
        snapshot.revisionCode = "TP-20260928-05"
        return snapshot
    }()

    var isValid: Bool {
        !revisionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...7).contains(strengthDaysPerWeek) && (1...(splitStyle == .upperLowerAlternating ? 3 : 2)).contains(maxFocusAreasPerSession)
            && (15...180).contains(sessionMinutesLower) && (sessionMinutesLower...240).contains(sessionMinutesUpper)
            && (0...7).contains(jumpRopeSessionsPerWeek) && (0...7).contains(zone2SessionsPerWeek)
            && (totalCardioSessionsPerWeek.map { (0...7).contains($0) } ?? true)
            && (5...120).contains(zone2Minutes)
    }

    func defaultSetCount(for muscleGroup: String) -> Int {
        (foundationalMuscleGroups + extraVolumeMuscleGroups).contains(muscleGroup) ? 4 : 3
    }
}

struct ProgramCardioDraft: Codable, Hashable, Identifiable {
    var code: String
    var title: String
    var weekday: Int
    var timing: String
    var activeSeconds: Int?
    var elapsedSeconds: Int?
    var intervals: String
    var guidance: String
    var catalogExerciseID: UUID? = nil
    var activeSecondsUpper: Int? = nil
    var id: String { code }
}

struct TrainingProgramSnapshot: Codable, Hashable {
    var code: String
    var title: String
    var preferenceRevisionCode: String
    var strengthWorkouts: [ProgramWorkoutDraft]
    var cardioWorkouts: [ProgramCardioDraft]
    var progressionRule: String
    var lowEnergyRule: String
    var confirmedImport: ConfirmedTrainingPlanSource? = nil

    var isValid: Bool {
        !code.isEmpty && !title.isEmpty && !preferenceRevisionCode.isEmpty
            && (1...7).contains(strengthWorkouts.count) && cardioWorkouts.count <= 14
            && Set(strengthWorkouts.map(\.code)).count == strengthWorkouts.count
            && Set(strengthWorkouts.map(\.weekday)).count == strengthWorkouts.count
            && Set(cardioWorkouts.map(\.code)).count == cardioWorkouts.count
            && strengthWorkouts.allSatisfy { workout in
                !workout.code.isEmpty && !workout.title.isEmpty && (1...7).contains(workout.weekday)
                    && (1...30).contains(workout.exercises.count)
                    && workout.exercises.allSatisfy {
                        !$0.name.isEmpty && (1...20).contains($0.sets)
                            && (1...10000).contains($0.repsLower) && ($0.repsLower...10000).contains($0.repsUpper)
                            && (0...3600).contains($0.restSeconds)
                            && ExerciseVolumeUnit(rawValue: $0.volumeUnitRaw) != nil
                    }
            }
            && cardioWorkouts.allSatisfy { cardio in
                !cardio.code.isEmpty && !cardio.title.isEmpty && (1...7).contains(cardio.weekday)
                    && (cardio.activeSeconds.map { (1...86400).contains($0) } ?? true)
                    && (cardio.elapsedSeconds.map { (1...86400).contains($0) } ?? true)
                    && (cardio.activeSecondsUpper.map { upper in
                        guard let lower = cardio.activeSeconds else { return false }
                        return (lower...86400).contains(upper)
                    } ?? true)
                    && JumpRopeDurationValidation.isValid(active: cardio.activeSeconds, elapsed: cardio.elapsedSeconds)
            }
    }
}

@Model
final class TrainingPreferenceRevision {
    var id: UUID = UUID()
    var revisionCode: String = ""
    var revision: Int = 1
    var effectiveAt: Date = Date.now
    var createdAt: Date = Date.now
    var reason: String = ""
    var snapshotJSON: String = ""

    init(
        id: UUID = UUID(),
        snapshot: TrainingPreferenceSnapshot,
        revision: Int,
        effectiveAt: Date,
        reason: String
    ) throws {
        self.id = id
        self.revisionCode = snapshot.revisionCode
        self.revision = revision
        self.effectiveAt = effectiveAt
        self.createdAt = .now
        self.reason = reason
        self.snapshotJSON = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    }

    init(
        id: UUID,
        revisionCode: String,
        revision: Int,
        effectiveAt: Date,
        createdAt: Date,
        reason: String,
        snapshotJSON: String
    ) {
        self.id = id
        self.revisionCode = revisionCode
        self.revision = revision
        self.effectiveAt = effectiveAt
        self.createdAt = createdAt
        self.reason = reason
        self.snapshotJSON = snapshotJSON
    }

    var snapshot: TrainingPreferenceSnapshot? {
        try? JSONDecoder().decode(TrainingPreferenceSnapshot.self, from: Data(snapshotJSON.utf8))
    }
}

@Model
final class TrainingProgramRevision {
    var id: UUID = UUID()
    var programID: UUID?
    var preferenceRevisionID: UUID = UUID()
    var preferenceRevisionCode: String = ""
    var revision: Int = 1
    var effectiveDate: Date = Date.now
    var createdAt: Date = Date.now
    var reason: String = ""
    var snapshotJSON: String = ""

    init(
        id: UUID = UUID(),
        programID: UUID?,
        preferenceRevision: TrainingPreferenceRevision,
        snapshot: TrainingProgramSnapshot,
        revision: Int,
        effectiveDate: Date,
        reason: String
    ) throws {
        self.id = id
        self.programID = programID
        self.preferenceRevisionID = preferenceRevision.id
        self.preferenceRevisionCode = preferenceRevision.revisionCode
        self.revision = revision
        self.effectiveDate = FatLossCalendar.day(effectiveDate)
        self.createdAt = .now
        self.reason = reason
        self.snapshotJSON = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    }

    init(
        id: UUID,
        programID: UUID?,
        preferenceRevisionID: UUID,
        preferenceRevisionCode: String,
        revision: Int,
        effectiveDate: Date,
        createdAt: Date,
        reason: String,
        snapshotJSON: String
    ) {
        self.id = id
        self.programID = programID
        self.preferenceRevisionID = preferenceRevisionID
        self.preferenceRevisionCode = preferenceRevisionCode
        self.revision = revision
        self.effectiveDate = effectiveDate
        self.createdAt = createdAt
        self.reason = reason
        self.snapshotJSON = snapshotJSON
    }

    var snapshot: TrainingProgramSnapshot? {
        try? JSONDecoder().decode(TrainingProgramSnapshot.self, from: Data(snapshotJSON.utf8))
    }
}

@MainActor
enum TrainingPreferenceService {
    /// Appends the owner's confirmed defaults once, leaving every historical revision intact.
    @discardableResult
    static func ensureAlternatingPreference(in context: ModelContext) throws -> TrainingPreferenceRevision? {
        let code = "TP-20261030-07"
        let effectiveAt = FatLossCalendar.date(2026, 10, 30)
        guard isRegistered(in: context) else { return nil }
        let all = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>())
        if let existing = all.first(where: { $0.revisionCode == code }) { return existing }
        guard let previous = effective(all, on: effectiveAt), var snapshot = previous.snapshot else { return nil }
        snapshot.revisionCode = code
        snapshot.splitStyle = .upperLowerAlternating
        snapshot.strengthDaysPerWeek = 3
        snapshot.maxFocusAreasPerSession = 3
        snapshot.jumpRopeSessionsPerWeek = 0
        snapshot.zone2SessionsPerWeek = 0
        snapshot.totalCardioSessionsPerWeek = 2
        snapshot.preferredSetPlanPattern = .pyramidUp
        let superseded = ["每次只聚焦 1 个主肌群", "工作日完成全部核心力量训练", "胸部单次 14–16", "正常胸背腿课主肌群至少4个动作"]
        let retainedConstraints = snapshot.constraints.filter { constraint in
            !superseded.contains(where: constraint.contains)
        }
        snapshot.constraints = [
            "2026-11-02 上肢周为锚点，上肢与下肢自然周交替；每周三次力量、两次有氧，工作日优先，周末休息且每天不分课。",
            "上肢周胸肩、背腹、胸背肩综合；综合课按胸2、背2、肩3、腹1的本人确认例外编排。",
            "每周至少4个不同腹部动作，优先负重和侧腹；例外须说明并确认。肩部覆盖前中后束。",
            "常规动作四个有效工作组14/12/10/8；主要复合动作每组增加5 kg，小肌群2.5 kg，设备和计量口径需现场校准。",
            "特殊动作单独设定；优先一项适合的重点动作在末组后立即降重继续，不将其作为实际已完成记录。",
            "胸背腿日保留至少4个工作组的指定卧推、划船/下拉或深蹲/硬拉；训练及完整估时不超过90分钟。",
            "不跑步；疼痛或恢复欠佳时停止受影响动作并调整。体能、设备及重量口径未知时保持未知。",
            "肌酐偏高且医生要求控制肉量；训练编排不得推导高蛋白或营养处方。"
        ] + retainedConstraints
        return try append(snapshot: snapshot, effectiveAt: effectiveAt,
            reason: "REQ-20261030-151014：本人确认上下肢周交替、三力量两有氧与工作组规则；旧版本保留。", in: context)
    }
    /// Owner-confirmed default only; does not regenerate a program or touch existing plans.
    @discardableResult
    static func ensurePyramidPreference(in context: ModelContext, on date: Date = .now) throws -> TrainingPreferenceRevision? {
        let code = "TP-20261021-06"
        let effectiveAt = FatLossCalendar.date(2026, 10, 21)
        guard date >= effectiveAt, isRegistered(in: context),
              let current = try current(in: context, on: date), var snapshot = current.snapshot else { return nil }
        let all = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>())
        guard !all.contains(where: { $0.revisionCode == code }) else { return current }
        snapshot.revisionCode = code
        snapshot.preferredSetPlanPattern = .pyramidUp
        snapshot.constraints = snapshot.constraints.map {
            $0.replacingOccurrences(of: "随后完成 2–3 个减重组", with: "新建默认递增金字塔，逐组目标单独核对")
                .replacingOccurrences(of: "热身和递增组不计入有效容量", with: "热身不计入工作容量；递增工作组计入工作容量")
        }
        snapshot.constraints += [
            "新建常规抗阻默认递增金字塔，允许逐动作调整；技术、自重及时间距离动作保留专用规则",
            "递增工作组计入工作容量，递增热身单独统计；旧Notes性质不明的记录不倒推为工作组",
            "正常胸背腿课主肌群至少4个动作；常规抗阻至少3工作组、重点复合至少4组，异常恢复按既有例外处理"
        ]
        return try append(snapshot: snapshot, effectiveAt: max(effectiveAt, current.effectiveAt),
                          reason: "REQ-20261021-103533：本人确认递增金字塔默认及历史衔接；原处方和实际保留", in: context)
    }
    static func isRegistered(in context: ModelContext) -> Bool {
        context.container.schema.entities.contains {
            $0.name == String(describing: TrainingPreferenceRevision.self)
        }
    }

    static func effective(_ revisions: [TrainingPreferenceRevision], on date: Date = .now) -> TrainingPreferenceRevision? {
        revisions.filter { $0.effectiveAt <= date }.sorted {
            if $0.effectiveAt == $1.effectiveAt { return $0.revision > $1.revision }
            return $0.effectiveAt > $1.effectiveAt
        }.first
    }

    static func current(in context: ModelContext, on date: Date = .now) throws -> TrainingPreferenceRevision? {
        guard isRegistered(in: context) else { return nil }
        let model = effective(try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()), on: date)
        if let model, model.snapshot?.isValid != true {
            throw FatLossError.invalidInput("当前训练偏好无法读取，请保留原数据并检查备份。")
        }
        return model
    }

    @discardableResult
    static func ensureConfirmedProfile(in context: ModelContext) throws -> TrainingPreferenceRevision? {
        guard isRegistered(in: context) else { return nil }
        var all = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>())
        if all.isEmpty {
            let model = try TrainingPreferenceRevision(
                id: UUID(uuidString: "D86CFE65-98BA-5DD4-ABCD-202609080002")!,
                snapshot: .weekdayFocused, revision: 1,
                effectiveAt: FatLossCalendar.date(2026, 9, 8),
                reason: "用户确认工作日优先、上肢高集中高容量与周末家庭时间；Notes 重量口径保持未知"
            )
            context.insert(model)
            try context.save()
            return model
        }
        let hasLegacyConfirmed = all.contains { $0.revisionCode == TrainingPreferenceSnapshot.confirmed.revisionCode }
        if hasLegacyConfirmed && !all.contains(where: { $0.revisionCode == TrainingPreferenceSnapshot.weekdayFocused.revisionCode }) {
            let model = try TrainingPreferenceRevision(
                id: UUID(uuidString: "D86CFE65-98BA-5DD4-ABCD-202609080002")!,
                snapshot: .weekdayFocused,
                revision: (all.map(\.revision).max() ?? 0) + 1,
                effectiveAt: FatLossCalendar.date(2026, 9, 8),
                reason: "用户确认工作日优先、上肢高集中高容量与周末家庭时间；Notes 重量口径保持未知"
            )
            context.insert(model)
            try context.save()
            all.append(model)
        }
        return try current(in: context)
    }

    @discardableResult
    static func append(snapshot: TrainingPreferenceSnapshot, effectiveAt: Date, reason: String,
                       in context: ModelContext) throws -> TrainingPreferenceRevision {
        let all = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>())
        guard snapshot.isValid, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !all.contains(where: { $0.revisionCode == snapshot.revisionCode }) else {
            throw FatLossError.invalidInput("训练偏好数值、版本号或修改原因无效；请使用新的版本号。")
        }
        let model = try TrainingPreferenceRevision(snapshot: snapshot,
            revision: (all.map(\.revision).max() ?? 0) + 1, effectiveAt: FatLossCalendar.day(effectiveAt), reason: reason)
        context.insert(model)
        try context.save()
        return model
    }

    static func effectiveProgram(_ revisions: [TrainingProgramRevision], programID: UUID?, on date: Date) -> TrainingProgramRevision? {
        let day = FatLossCalendar.day(date)
        // A confirmed draft covers one week. Further weeks need an explicit new revision.
        return revisions.filter {
            $0.programID == programID && $0.effectiveDate <= day && day < FatLossCalendar.adding(7, to: $0.effectiveDate)
        }.sorted {
            if $0.effectiveDate == $1.effectiveDate { return $0.revision > $1.revision }
            return $0.effectiveDate > $1.effectiveDate
        }.first
    }

    /// Seed the approved first week once. Reading the app must not generate a new plan after a preference change.
    @discardableResult
    static func ensureProgramRevision(programID: UUID?, effectiveDate: Date,
                                      in context: ModelContext) throws -> TrainingProgramRevision? {
        guard isRegistered(in: context), FatLossBackupService.isRegistered(TrainingProgramRevision.self, in: context) else { return nil }
        guard let preference = try ensureConfirmedProfile(in: context), let snapshot = preference.snapshot else { return nil }
        let existing = try context.fetch(FetchDescriptor<TrainingProgramRevision>()).filter { $0.programID == programID }
        if snapshot.revisionCode == TrainingPreferenceSnapshot.weekdayFocused.revisionCode {
            if let confirmed = existing.first(where: { $0.preferenceRevisionID == preference.id && $0.snapshot?.code == "CUT-4D-20260908-R2" }) {
                return confirmed
            }
        } else if let latest = existing.max(by: { $0.revision < $1.revision }) {
            return latest
        }
        if snapshot.splitStyle == .upperLowerAlternating { return nil }
        guard snapshot.strengthDaysPerWeek == 4, snapshot.jumpRopeSessionsPerWeek <= 2, snapshot.zone2SessionsPerWeek <= 1 else {
            throw FatLossError.invalidInput("新偏好需要重新确认一周编排，不能直接套用旧目录。")
        }
        return try appendProgram(snapshot: FatLossCatalog.trainingProgram(preference: snapshot),
            preference: preference, programID: programID,
            effectiveDate: max(FatLossCalendar.day(effectiveDate), preference.effectiveAt),
            reason: "用户确认的首周编排；只保存快照，不自动创建日程", in: context)
    }

    @discardableResult
    static func appendProgram(snapshot: TrainingProgramSnapshot, preference: TrainingPreferenceRevision,
                              programID: UUID?, effectiveDate: Date, reason: String,
                              in context: ModelContext) throws -> TrainingProgramRevision {
        let day = FatLossCalendar.day(effectiveDate)
        guard snapshot.isValid, snapshot.preferenceRevisionCode == preference.revisionCode,
              snapshot.strengthWorkouts.count == preference.snapshot?.strengthDaysPerWeek,
              try current(in: context, on: day)?.id == preference.id,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FatLossError.invalidInput("编排内容、关联偏好、生效日期或调整原因无效。")
        }
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>()).filter { $0.programID == programID }
        let model = try TrainingProgramRevision(programID: programID, preferenceRevision: preference,
            snapshot: snapshot, revision: (revisions.map(\.revision).max() ?? 0) + 1,
            effectiveDate: day, reason: reason)
        context.insert(model)
        try context.save()
        return model
    }

    /// Appends (or returns) the user-confirmed one-week lower-body preference and program snapshots.
    /// This only saves versioned snapshots; schedule creation remains an explicit preview/import step.
    static func activateLowerBodySpecialtyWeek(
        programID: UUID?,
        effectiveDate: Date,
        in context: ModelContext
    ) throws -> TrainingProgramRevision {
        let preferenceSnapshot = TrainingPreferenceSnapshot.lowerBodySpecialtyWeek
        let preferences = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>())
        let preference: TrainingPreferenceRevision
        if let existing = preferences.first(where: { $0.revisionCode == preferenceSnapshot.revisionCode }) {
            guard existing.snapshot == preferenceSnapshot,
                  FatLossCalendar.sameDay(existing.effectiveAt, effectiveDate) else {
                throw FatLossError.invalidInput("下肢专项周偏好版本已存在但内容或生效日期不一致。")
            }
            preference = existing
        } else {
            preference = try append(
                snapshot: preferenceSnapshot,
                effectiveAt: effectiveDate,
                reason: "用户确认 2026-09-14 起仅一周三次下肢力量、两次跳绳，并在每次力量加入足踝活动度与刚性训练",
                in: context
            )
        }

        let programSnapshot = FatLossCatalog.trainingProgram(preference: preferenceSnapshot)
        let programs = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
        if let existing = programs.first(where: {
            $0.programID == programID && $0.snapshot?.code == programSnapshot.code
        }) {
            guard existing.snapshot == programSnapshot,
                  FatLossCalendar.sameDay(existing.effectiveDate, effectiveDate),
                  existing.preferenceRevisionID == preference.id else {
                throw FatLossError.invalidInput("下肢专项周编排版本已存在但内容、日期或关联偏好不一致。")
            }
            return existing
        }
        return try appendProgram(
            snapshot: programSnapshot,
            preference: preference,
            programID: programID,
            effectiveDate: effectiveDate,
            reason: "用户确认的 2026-09-14 至 2026-09-20 下肢专项周",
            in: context
        )
    }

    /// The approved trip is one week only. Append an explicit baseline restoration,
    /// never overwrite the permanent preference or generate the following week's plan.
    static func activateUpperBodyTravelWeek(
        programID: UUID?, effectiveDate: Date, in context: ModelContext
    ) throws -> TrainingProgramRevision {
        let start = FatLossCalendar.date(2026, 9, 21)
        guard FatLossCalendar.sameDay(effectiveDate, start) else {
            throw FatLossError.invalidInput("已确认旅行周只从 2026-09-21 开始。")
        }
        func preference(_ snapshot: TrainingPreferenceSnapshot, date: Date, reason: String) throws -> TrainingPreferenceRevision {
            let matches = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).filter { $0.revisionCode == snapshot.revisionCode }
            guard matches.count <= 1 else { throw FatLossError.invalidInput("训练偏好版本重复，请先核对。") }
            if let existing = matches.first {
                guard existing.snapshot == snapshot, FatLossCalendar.sameDay(existing.effectiveAt, date) else {
                    throw FatLossError.invalidInput("旅行周偏好版本已存在，但内容或日期不一致。")
                }
                return existing
            }
            return try append(snapshot: snapshot, effectiveAt: date, reason: reason, in: context)
        }
        let travel = try preference(.upperBodyTravelWeek, date: start,
            reason: "用户确认 9/21–27 旅行上肢周；连续三天为单周例外，左肘不适下保守容量")
        let snapshot = FatLossCatalog.trainingProgram(preference: .upperBodyTravelWeek)
        let matches = try context.fetch(FetchDescriptor<TrainingProgramRevision>()).filter {
            $0.programID == programID && $0.snapshot?.code == snapshot.code
        }
        guard matches.count <= 1 else { throw FatLossError.invalidInput("旅行周编排版本重复，请先核对。") }
        let revision: TrainingProgramRevision
        if let existing = matches.first {
            guard existing.snapshot == snapshot, existing.preferenceRevisionID == travel.id,
                  FatLossCalendar.sameDay(existing.effectiveDate, start) else {
                throw FatLossError.invalidInput("旅行周编排已存在，但内容、日期或关联不一致。")
            }
            revision = existing
        } else {
            revision = try appendProgram(snapshot: snapshot, preference: travel, programID: programID,
                effectiveDate: start, reason: "用户确认的 2026-09-21 至 2026-09-27 上肢旅行周", in: context)
        }
        _ = try preference(.postTravelRestoration, date: FatLossCalendar.adding(7, to: start),
            reason: "旅行单周例外到期，恢复 TP-20260908-02 长期偏好；不生成新编排或日程")
        return revision
    }
}
