import SwiftData
import SwiftUI

enum CoachPresentation {
    static func load(_ item: CoachPlanItem) -> String {
        if item.exercise.volumeUnit == .bodyweight { return "自重" }
        let weights = item.exercise.plannedSets.map(\.weight)
        guard let first = weights.first else { return "待编排" }
        if weights.allSatisfy({ $0 == 0 }) { return "热身后现场校准" }
        let value = Set(weights).count == 1 ? first.formatted() : "\(first.formatted()) → \(weights.last!.formatted())"
        if item.exercise.loadGuidance.contains("显示") { return "同机显示 \(value)" }
        return "\(value) \(item.exercise.volumeUnit.symbol) · \(item.exercise.plannedSets.first?.weightSide.title ?? "口径待核")"
    }
    static func setLoad(_ plan: WorkoutSetPlan, item: CoachPlanItem) -> String {
        if item.exercise.volumeUnit == .bodyweight { return "自重" }
        if !item.exercise.volumeUnit.recordsNumericLoad { return item.exercise.volumeUnit.title }
        if plan.weight == 0 { return "现场校准" }
        if item.exercise.loadGuidance.contains("显示") { return "同机显示 \(plan.weight.formatted())" }
        return "\(plan.weight.formatted()) \(item.exercise.volumeUnit.symbol)"
    }
    static func dose(_ item: CoachPlanItem) -> String {
        let plans = item.exercise.plannedSets
        let ranges = Set(plans.map { "\($0.prescription?.repsLower ?? $0.reps)–\($0.prescription?.repsUpper ?? $0.reps)" })
        return ranges.count == 1 ? "\(plans.count) × \(ranges.first!)" : "\(plans.count)组 · 逐组目标"
    }
    static func effort(_ plan: WorkoutSetPlan) -> String {
        guard let target = plan.prescription else { return "目标待补" }
        let effort = target.rirLower.flatMap { lower in target.rirUpper.map { "RIR \(lower)–\($0)" } }
            ?? target.effortCue ?? "质量目标待核"
        return "\(effort) · 休\(target.restLowerSeconds)–\(target.restUpperSeconds)秒"
    }
    static func actual(_ set: CoachActualSet, unit: ExerciseVolumeUnit) -> String {
        if unit == .second || unit == .count { return "\(set.reps) \(unit.symbol) · \(set.rir.map { "RIR \($0)" } ?? "余力未知")" }
        if unit == .bodyweight { return "自重 × \(set.reps) · \(set.repsSide.title)" }
        let weight = set.weight.map { "\($0.formatted()) \(unit.symbol)" } ?? "重量未知"
        return "\(weight) × \(set.reps) · \(set.weightSide.title) · \(set.rir.map { "RIR \($0)" } ?? "RIR未知")"
    }
}

struct TrainingReviewView: View {
    private enum FeedbackStage: String, Identifiable {
        case after, morning
        var id: String { rawValue }
    }
    let sessionID: UUID
    var initialFeedbackStage: String? = nil
    @Environment(\.modelContext) private var context
    @State private var review: CoachReview?
    @State private var error: String?
    @State private var feedbackStage: FeedbackStage?
    @State private var initialStageUsed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let review {
                    SprintPageHeader(title: "训练总结", icon: "checklist", subtitle: review.localDay + " · " + review.name)
                    Text("已记录 \(review.completed)/\(review.total) 组 · 补充反馈单独保留")
                        .font(.caption).foregroundStyle(EditorialTheme.muted)
                    Button { feedbackStage = .morning } label: {
                        EditorialRow(title: review.morning.supportsNormalDose ? "次晨恢复已补" : "次晨恢复",
                            subtitle: TrainingLocalDate.key(.now) > review.localDay ? "关节腰背 · 日常活动 · 整体恢复" : "明早再补，不预填正常", icon: "moon")
                    }.accessibilityIdentifier("复盘-次晨恢复")
                    verdict(review)
                    SprintSectionHeading(title: "动作复盘", icon: "dumbbell")
                    ForEach(review.observations) { item in
                        DisclosureGroup {
                            if let feeling = item.feelingRaw.flatMap(WorkoutFeeling.init(rawValue:)) { Text("App动作感受：" + feeling.title).font(.caption) }
                            if !item.performanceNotes.isEmpty { Text("App动作反馈：" + item.performanceNotes).font(.caption) }
                            ForEach(item.working) { set in
                                Text(CoachPresentation.actual(set, unit: item.unit)).font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                            }
                            if let last = item.working.last, last.rir == nil,
                               let estimated = review.after.lastRIR[item.id.uuidString] {
                                Text("本人后来补充：末组余力约\(estimated)次；原始RIR仍保留未知。")
                                    .font(.caption).foregroundStyle(EditorialTheme.muted)
                            }
                            ForEach(item.previous) { previous in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("可比历史 · \(previous.localDay)").bold()
                                    ForEach(previous.actual) { set in Text(CoachPresentation.actual(set, unit: item.unit)) }
                                    if previous.actual.last?.rir == nil, let estimate = previous.supplementaryLastRIR {
                                        Text("当次后补的末组余力约\(estimate)次；其他组仍未知。")
                                    }
                                }.font(.caption).foregroundStyle(EditorialTheme.muted).padding(.vertical, 7)
                            }
                            if item.previous.isEmpty { Text("近42天可比历史不足，不跨器械换算。").font(.caption).foregroundStyle(EditorialTheme.muted) }
                            if !item.loadGuidance.isEmpty { Text(item.loadGuidance).font(.caption) }
                            if item.working.isEmpty { Text("没有已完成组记录，不据此认定没练。").font(.caption) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.subheadline.bold())
                                    Text(TrainingCoachService.insight(for: item, after: review.after)).lineLimit(2)
                                        .font(.caption).foregroundStyle(EditorialTheme.muted)
                                }
                                Spacer(minLength: 8)
                                if let last = item.working.last {
                                    Text(last.weight.map { $0.formatted() } ?? "—").font(.subheadline.bold())
                                }
                            }.padding(.vertical, 7)
                        }.cardSurface(padding: 14, cornerRadius: 20)
                    }
                    Button { feedbackStage = .after } label: {
                        EditorialRow(title: "练后反馈", subtitle: "只补缺项 · 可保留未知", icon: "text.bubble")
                    }.accessibilityIdentifier("复盘-补充练后反馈")
                    DisclosureGroup("已有反馈与依据") {
                        Text("练后不适：\(answer(review.after.pain))；次晨活动：\(answer(review.morning.function))；恢复：\(answer(review.morning.recovery))。")
                        if !review.after.note.isEmpty { Text(review.after.note) }
                        if !review.morning.note.isEmpty { Text(review.morning.note) }
                        ForEach(review.existingRecovery, id: \.self) { Text($0).padding(.top, 5) }
                        ForEach(review.coverage, id: \.self) { Text($0).padding(.top, 5) }
                        Text("偏好：\(review.preferenceCode.isEmpty ? "尚未取得" : review.preferenceCode)。只有可比记录支持选重；技术、热身和常规工作分开。")
                    }.font(.caption).foregroundStyle(EditorialTheme.muted)
                    NavigationLink { WorkoutDetailView(sessionID: sessionID).legacyTrainingScreen() } label: {
                        EditorialRow(title: "原始记录", icon: "list.bullet")
                    }
                } else if error == nil { ProgressView().frame(maxWidth: .infinity) }
                if let error { CoachInlineError(message: error) { reload() } }
            }.padding(24)
        }.sprintPage().buttonStyle(.plain).navigationTitle("训练总结").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if review != nil {
                    NavigationLink { TrainingCoachPlanView(sessionID: sessionID) } label: {
                        EditorialPrimary(title: "下次计划")
                    }.accessibilityIdentifier("复盘-下一次计划").buttonStyle(.plain).padding(.horizontal, 24).padding(.vertical, 10).background(EditorialTheme.paper)
                }
            }
            .sheet(item: $feedbackStage, onDismiss: reload) { stage in
                if let review { TrainingCoachFeedbackView(review: review, stage: stage.rawValue) }
            }
            .task {
                reload()
                if !initialStageUsed, let initialFeedbackStage,
                   let stage = FeedbackStage(rawValue: initialFeedbackStage), review != nil {
                    initialStageUsed = true; feedbackStage = stage
                }
            }
    }

    private func verdict(_ source: CoachReview) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("下一步", systemImage: "bolt.fill").font(.subheadline.bold())
            Text(source.morning.pain == "yes" || source.morning.function == "limited" || source.morning.recovery == "poor" ? "先核实恢复，\n再定正常剂量。" : "校准强度，保留容量。")
                .font(.title2.weight(.black)).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                metric(source.technicalCount, "技术记录"); Spacer()
                metric(source.completed - source.technicalCount, "常规记录"); Spacer()
                metric(max(0, source.total - source.completed), "未记录")
            }
        }.padding(20).background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 24))
    }
    private func metric(_ count: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text("\(count)").font(.title2.bold()); Text(label).font(.caption2).foregroundStyle(EditorialTheme.muted) }
    }
    private func answer(_ value: String) -> String {
        ["none": "无不适", "yes": "有不适", "normal": "正常", "limited": "受影响", "good": "良好", "ordinary": "一般", "poor": "疲劳明显"][value] ?? "未知"
    }
    private func reload() {
        do { review = try TrainingCoachService.review(sessionID: sessionID, in: context); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct CoachInlineError: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if let retry { Button("重新检查", action: retry).font(.subheadline.bold()).frame(minHeight: 44) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(EditorialTheme.sage, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CoachQuestion: Identifiable {
    var id: String
    var title: String
    var key: String
    var choices: [(String, String)] = []
    var observationID: String? = nil
}

struct TrainingCoachFeedbackView: View {
    let review: CoachReview
    let stage: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var feedback: CoachFeedback
    @State private var index = 0
    @State private var editAll = false
    @State private var error: String?

    init(review: CoachReview, stage: String) {
        self.review = review; self.stage = stage
        var initial = stage == "morning" ? review.morning : review.after
        if stage == "after", initial.pain == "unknown", review.observations.contains(where: { $0.feelingRaw == WorkoutFeeling.painful.rawValue }) {
            initial.pain = "yes"
            if initial.note.isEmpty { initial.note = "沿用App已有动作感受：不适/疼痛。" }
        }
        _feedback = State(initialValue: initial)
    }
    private var notDue: Bool { stage == "morning" && TrainingLocalDate.key(.now) <= review.localDay }
    private var questions: [CoachQuestion] {
        if stage == "morning" {
            return [CoachQuestion(id: "pain", title: "关节或腰背，\n有没有不适？", key: "pain", choices: [("none", "没有不适"), ("yes", "有不适"), ("unknown", "不清楚")]),
                    CoachQuestion(id: "function", title: "走路、楼梯和蹲起，\n和平时一样吗？", key: "function", choices: [("normal", "和平时一样"), ("limited", "有些受影响"), ("unknown", "不清楚")]),
                    CoachQuestion(id: "recovery", title: "整体恢复，\n现在感觉怎样？", key: "recovery", choices: [("good", "恢复不错"), ("ordinary", "一般，可以接受"), ("poor", "明显疲劳"), ("unknown", "还说不清")])]
        }
        var result: [CoachQuestion] = []
        if editAll || (review.after.pain == "unknown" && !review.observations.contains(where: { $0.feelingRaw == WorkoutFeeling.painful.rawValue })) {
            result.append(CoachQuestion(id: "pain", title: "练后关节或腰背，\n有没有不适？", key: "pain", choices: [("none", "没有不适"), ("yes", "有不适"), ("unknown", "不清楚")]))
        }
        for item in review.observations {
            if item.isTechnical && (editAll || review.after.quality[item.id.uuidString] == nil || review.after.quality[item.id.uuidString] == "unknown") {
                result.append(CoachQuestion(id: "quality:\(item.id)", title: "\(item.name)\n速度和动作稳定吗？", key: "quality", choices: [("stable", "动作稳定、速度可控"), ("unstable", "降速或动作不稳定"), ("unknown", "不清楚")], observationID: item.id.uuidString))
            } else if !item.isTechnical && item.working.last?.rir == nil && (editAll || review.after.lastRIR[item.id.uuidString] == nil), !item.working.isEmpty {
                result.append(CoachQuestion(id: "rir:\(item.id)", title: "\(item.name)末组，\n大概还剩几次余力？", key: "rir", observationID: item.id.uuidString))
            }
            if item.working.last?.repsSide == .unknown && (editAll || review.after.repsSides[item.id.uuidString] == nil || review.after.repsSides[item.id.uuidString] == .unknown) {
                result.append(CoachQuestion(id: "repsSide:\(item.id)", title: "\(item.name)\n次数按每侧还是一次动作记？", key: "repsSide", choices: [("single", "每侧分别记次"), ("bilateral", "一次双侧动作或合计次数"), ("unknown", "不清楚")], observationID: item.id.uuidString))
            }
            if item.unit.recordsNumericLoad && item.loadGuidance.isEmpty && (editAll || review.after.loadConventions[item.id.uuidString] == nil || review.after.loadConventions[item.id.uuidString] == "unknown") {
                result.append(CoachQuestion(id: "unit:\(item.id)", title: "\(item.name)\n这些数字怎样记重？", key: "unit",
                    choices: [("含杆总重", "含杆总重"), ("每侧加片，不含杆或空载", "每侧加片，不含杆/空载"), ("单手哑铃重量", "单手哑铃重量"), ("两手负重合计", "两手负重合计"), ("同机显示值，不换算外部负荷", "同机显示值"), ("unknown", "未知，稍后核对")], observationID: item.id.uuidString))
            }
        }
        if review.completed < review.total && (editAll || review.after.omission == "unknown") {
            result.append(CoachQuestion(id: "omission", title: "部分组没有完成记录，\n主要是什么原因？", key: "omission", choices: [("unrecorded", "做了，只是没记录"), ("time", "时间安排，省去了"), ("fatigue", "因为疲劳或不适省去"), ("adjusted", "临时调整了内容"), ("unknown", "不清楚")]))
        }
        return result
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    if notDue {
                        SprintPageHeader(title: "明早再补", icon: "moon", subtitle: review.localDay)
                        Text("次晨恢复明早填写，当前保留未知。").font(.subheadline).foregroundStyle(EditorialTheme.muted)
                    } else if questions.isEmpty {
                        SprintPageHeader(title: "反馈已沿用", icon: "checkmark.bubble", subtitle: review.localDay)
                        Text("已有信息无需重填，有变化时再修订。").font(.subheadline).foregroundStyle(EditorialTheme.muted)
                        Button { editAll = true; index = 0 } label: { EditorialPrimary(title: "修订已有反馈") }
                    } else {
                        let question = questions[min(index, questions.count - 1)]
                        HStack {
                            Text(String(format: "%02d / %02d", index + 1, questions.count)).font(.caption.monospacedDigit())
                            Spacer(); Text("可以保留未知").font(.caption)
                        }.foregroundStyle(EditorialTheme.muted).padding(.top, 12)
                        if index == 0 && !review.existingRecovery.isEmpty {
                            DisclosureGroup("已有体感与睡眠") { ForEach(review.existingRecovery, id: \.self) { Text($0) } }.font(.caption).foregroundStyle(EditorialTheme.muted)
                        }
                        SprintIcon(systemName: feedbackIcon(question), size: 64, prominent: true)
                        Text(question.title).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true).padding(.vertical, 10)
                        if question.key == "rir" {
                            let id = question.observationID!
                            Picker("末组余力估计", selection: Binding(get: { feedback.lastRIR[id] ?? -1 }, set: { feedback.lastRIR[id] = $0 < 0 ? nil : $0 })) {
                                Text("不清楚").tag(-1)
                                ForEach(0...10, id: \.self) { Text("约\($0)次").tag($0) }
                            }.pickerStyle(.wheel).frame(height: 180)
                            Text("只记录回忆估计；不需要加做一组验证。").font(.caption).foregroundStyle(EditorialTheme.muted)
                        } else {
                            ForEach(question.choices, id: \.0) { choice in
                                Button { setValue(choice.0, question) } label: {
                                    HStack {
                                        Text(choice.1); Spacer()
                                        Image(systemName: value(question) == choice.0 ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(value(question) == choice.0 ? AppTheme.ink : AppTheme.secondaryText)
                                    }.font(.subheadline).padding(16).frame(maxWidth: .infinity, minHeight: 56)
                                        .background(value(question) == choice.0 ? AppTheme.accent : AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(EditorialTheme.line))
                                }.buttonStyle(.plain)
                                    .accessibilityAddTraits(value(question) == choice.0 ? .isSelected : [])
                            }
                        }
                        if index == questions.count - 1 {
                            DisclosureGroup("补充说明或睡眠（可选）") {
                                TextField("不适部位、训练中断或其他说明", text: $feedback.note, axis: .vertical).lineLimit(3...6).padding(.vertical, 10)
                                if stage == "morning" {
                                    Picker("训练后当晚睡眠", selection: $feedback.sleep) {
                                        Text("未知").tag("unknown"); Text("良好").tag("good"); Text("一般").tag("ordinary"); Text("较差").tag("poor")
                                    }
                                }
                            }.font(.subheadline)
                        }
                    }
                    if let error { CoachInlineError(message: error) }
                }.padding(24)
            }.sprintPage().navigationTitle(stage == "morning" ? "次晨恢复" : "练后补充")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("稍后", role: .cancel) { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    if !notDue && !questions.isEmpty {
                        VStack(spacing: 7) {
                            Button { advance() } label: { EditorialPrimary(title: index == questions.count - 1 ? "保存反馈" : "下一步") }
                                .accessibilityIdentifier("反馈-下一步或保存")
                            if index > 0 { Button("上一步") { index -= 1 }.font(.caption).frame(minHeight: 44) }
                        }.buttonStyle(.plain).padding(.horizontal, 24).padding(.vertical, 10).background(EditorialTheme.paper)
                    }
                }
        }
    }
    private func feedbackIcon(_ question: CoachQuestion) -> String {
        switch question.key {
        case "pain": return "figure.arms.open"
        case "function": return "figure.walk"
        case "recovery": return "battery.100percent"
        case "rir": return "gauge.with.dots.needle.50percent"
        case "quality": return "figure.strengthtraining.traditional"
        case "unit", "repsSide": return "scalemass"
        default: return "checklist"
        }
    }
    private func value(_ q: CoachQuestion) -> String {
        switch q.key {
        case "pain": return feedback.pain
        case "function": return feedback.function
        case "recovery": return feedback.recovery
        case "omission": return feedback.omission
        case "quality": return feedback.quality[q.observationID!] ?? "unknown"
        case "unit": return feedback.loadConventions[q.observationID!] ?? "unknown"
        case "repsSide": return feedback.repsSides[q.observationID!]?.rawValue ?? "unknown"
        default: return "unknown"
        }
    }
    private func setValue(_ value: String, _ q: CoachQuestion) {
        switch q.key {
        case "pain": feedback.pain = value
        case "function": feedback.function = value
        case "recovery": feedback.recovery = value
        case "omission": feedback.omission = value
        case "quality": feedback.quality[q.observationID!] = value
        case "unit": feedback.loadConventions[q.observationID!] = value
        case "repsSide": feedback.repsSides[q.observationID!] = MeasurementSide(rawValue: value) ?? .unknown
        default: break
        }
    }
    private func advance() {
        if index < questions.count - 1 { index += 1; return }
        do { try TrainingCoachService.saveFeedback(feedback, sessionID: review.sessionID, in: context); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct CoachPlanItemSummary: View {
    let item: CoachPlanItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.exercise.displayName).font(.subheadline.bold()); Spacer(minLength: 6)
                Text(CoachPresentation.dose(item)).font(.caption.bold())
            }
            Text(CoachPresentation.load(item)).font(.subheadline)
            if let pattern = item.exercise.planPattern { Text(pattern.title).font(.caption) }
            if let first = item.exercise.plannedSets.first { Text(CoachPresentation.effort(first)).font(.caption).foregroundStyle(EditorialTheme.muted) }
            if !item.unitVerified { Text("器械或记重口径待核对").font(.caption).foregroundStyle(EditorialTheme.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 15)
            .overlay(alignment: .bottom) { EditorialTheme.line.frame(height: 0.5) }
    }
}

struct TrainingCoachPlanView: View {
    let sessionID: UUID
    @Environment(\.modelContext) private var context
    @State private var draft: CoachDraft?
    @State private var rows: [TrainingCoachRecord] = []
    @State private var error: String?
    @State private var showDate = false
    @State private var date = Date.now.addingDays(2)
    @State private var dateExplicit = false
    @State private var editing: CoachPlanItem?
    @State private var confirmation: CoachConfirmation?
    @State private var showRecovery = false
    @State private var source: CoachReview?
    @State private var reasons: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SprintPageHeader(title: "下次计划", icon: "calendar.badge.plus", subtitle: draft?.title)
                Label(draft.map { "V\($0.revision) 草案" } ?? "待生成", systemImage: "pencil.line")
                    .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(AppTheme.accent, in: Capsule())
                if let draft {
                    Text("\(draft.items.count)动作 · \(draft.items.reduce(0) { $0 + $1.exercise.plannedSets.count })个计划位置 · 热身另计")
                        .font(.caption).foregroundStyle(EditorialTheme.muted)
                    ForEach(draft.items) { item in
                        HStack(alignment: .top) {
                            Button { editing = item } label: { CoachPlanItemSummary(item: item) }.buttonStyle(.plain)
                                .accessibilityIdentifier("计划动作-\(item.exercise.displayName)")
                            ExerciseExplanationButton(exerciseID: item.exercise.catalogExerciseID, name: item.exercise.displayName,
                                equipment: item.exercise.equipment, lookupName: item.exercise.catalogName)
                        }
                        if let observation = source?.observations.first(where: { $0.exerciseID == item.id }) {
                            TrainingPlanHistoryComparison(history: .observed(observation,
                                date: source.flatMap { TrainingLocalDate.date($0.localDay, timeZone: .current) }),
                                plans: item.exercise.plannedSets, unit: item.exercise.volumeUnit,
                                exerciseName: item.exercise.displayName)
                        }
                    }
                    DisclosureGroup("依据、热身与当天调整") {
                        ForEach(draft.items) { item in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(item.exercise.displayName).bold(); Text(item.reason); Text(item.warmup); Text(item.adjustment)
                            }.padding(.vertical, 8)
                        }
                        ForEach(draft.coverage, id: \.self) { Text($0).padding(.top, 6) }
                        Text("偏好 \(draft.preferenceCode) · 方法 \(draft.method)").font(.caption2)
                    }.font(.caption).foregroundStyle(EditorialTheme.muted)
                    Button { showDate = true } label: {
                        EditorialRow(title: "训练日期", subtitle: draft.localDay ?? "尚未选择", icon: "calendar")
                    }.accessibilityIdentifier("计划-选择日期")
                    if !reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 6) { ForEach(reasons, id: \.self) { Text($0) } }
                            .font(.caption).foregroundStyle(EditorialTheme.muted)
                    }
                    Button { generate() } label: { EditorialRow(title: "更新草案", subtitle: "使用最新实际与反馈 · 保留旧版", icon: "arrow.clockwise") }
                } else {
                    Text("根据实际完成、可比负重与恢复编排，可逐项编辑。").font(.subheadline).foregroundStyle(EditorialTheme.muted).padding(.vertical, 20)
                    Button { generate() } label: { EditorialPrimary(title: "生成同类训练草案") }.accessibilityIdentifier("计划-生成草案")
                }
                if let source {
                    Button { showRecovery = true } label: {
                        EditorialRow(title: source.morning.supportsNormalDose ? "恢复反馈" : "补充次晨恢复", icon: "moon")
                    }
                }
                NavigationLink { TrainingReviewView(sessionID: sessionID, initialFeedbackStage: "after") } label: {
                    EditorialRow(title: "余力与动作质量", subtitle: "只补缺项 · 沿用已有记录", icon: "gauge.with.dots.needle.50percent")
                }
                let previous = (try? TrainingCoachService.confirmations(rows: rows)) ?? []
                if !previous.isEmpty {
                    SprintSectionHeading(title: "已确认版本", icon: "checkmark.seal").padding(.top, 10)
                    ForEach(previous.reversed()) { item in
                        NavigationLink { CoachConfirmedPlanView(confirmation: item) } label: {
                            EditorialRow(title: "\(item.preview.packet.localDay) · V\(item.draft.revision)",
                                subtitle: TrainingCoachService.isCancelled(item, rows: rows) ? "未保存请求已取消" : ((try? TrainingCoachService.hasReceipt(item, rows: rows)) == true ? "已保存 · 完整快照保留" : "保存结果待核对"))
                        }
                    }
                }
                if let error { CoachInlineError(message: error) }
            }.padding(24)
        }.sprintPage().buttonStyle(.plain).navigationTitle("下一次计划").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if draft != nil {
                    Button { prepare() } label: { EditorialPrimary(title: "审阅完整计划") }
                        .disabled(!reasons.isEmpty).opacity(reasons.isEmpty ? 1 : 0.45).accessibilityIdentifier("计划-审阅确认")
                        .padding(.horizontal, 24).padding(.vertical, 10).background(EditorialTheme.paper)
                }
            }
            .sheet(isPresented: $showDate) {
                NavigationStack {
                    DatePicker("训练日期", selection: $date, in: Date.now.startOfDay..., displayedComponents: .date)
                        .datePickerStyle(.graphical).padding(24)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("选定日期") { saveDate() } } }
                }.sprintPage()
            }
            .sheet(item: $editing) { item in
                CoachPlanItemEditor(item: item) { updated in
                    guard var current = draft, let index = current.items.firstIndex(where: { $0.id == updated.id }) else { return }
                    current.items[index] = updated
                    do { draft = try TrainingCoachService.revise(current, in: context); load() }
                    catch { self.error = error.localizedDescription }
                }
            }
            .sheet(item: $confirmation, onDismiss: load) { item in CoachConfirmationView(confirmation: item) }
            .sheet(isPresented: $showRecovery, onDismiss: load) {
                if let source { TrainingCoachFeedbackView(review: source, stage: "morning") }
            }
            .task { load() }
    }
    private func load() {
        do {
            rows = try TrainingCoachService.records(sessionID: sessionID, in: context)
            draft = try TrainingCoachService.latestDraft(rows: rows)
            let target = draft?.localDay.flatMap { TrainingLocalDate.date($0, timeZone: .current) }
            source = try TrainingCoachService.review(sessionID: sessionID, preferenceDate: target ?? .now, in: context)
            if let target { date = target; dateExplicit = true }
            reasons = try draft.map { try TrainingCoachService.blockingReasons($0, in: context) } ?? []
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func generate() {
        do { draft = try TrainingCoachService.makeDraft(sessionID: sessionID, date: dateExplicit ? date : nil, in: context); load() }
        catch { self.error = error.localizedDescription }
    }
    private func saveDate() {
        dateExplicit = true; showDate = false
        guard var current = draft else { return }
        if current.localDay == TrainingLocalDate.key(date) { return }
        current.localDay = TrainingLocalDate.key(date)
        do { draft = try TrainingCoachService.revise(current, in: context); load() }
        catch { self.error = error.localizedDescription }
    }
    private func prepare() {
        guard let draft else { return }
        do { confirmation = try TrainingCoachService.prepareConfirmation(draft, in: context); error = nil }
        catch { let message = error.localizedDescription; load(); self.error = message }
    }
}

struct CoachPlanItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: CoachPlanItem
    let onSave: (CoachPlanItem) -> Void
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("如每侧加片、不含杆 / 单手 / 同机显示", text: $item.exercise.loadGuidance, axis: .vertical)
                    Toggle("已核对同一器械与记重含义", isOn: $item.unitVerified)
                } header: {
                    Label("记重口径", systemImage: "scalemass")
                }
                Section {
                    if item.exercise.volumeUnit == .kilogram && !item.technical {
                        Picker("训练方式", selection: Binding(get: { item.exercise.planPattern ?? .fixed },
                            set: { item.exercise.planPattern = $0 })) {
                            ForEach(SetPlanPattern.allCases) { Text($0.title).tag($0) }
                        }
                        Text("逐组核对重量和目标；不自动换算器械档位。").font(.caption)
                    }
                    Stepper("\(item.exercise.plannedSets.count)组", value: Binding(get: { item.exercise.plannedSets.count }, set: { count in
                        while item.exercise.plannedSets.count < count { var set = item.exercise.plannedSets.last!; set.id = UUID(); item.exercise.plannedSets.append(set) }
                        while item.exercise.plannedSets.count > count { item.exercise.plannedSets.removeLast() }
                    }), in: 1...20)
                    if !item.technical && item.exercise.plannedSets.count < item.minimumSets {
                        TextField("说明本次减量原因", text: $item.exceptionReason, axis: .vertical)
                    }
                } header: {
                    Label("组数与减量", systemImage: "square.stack")
                }
                ForEach(item.exercise.plannedSets.indices, id: \.self) { index in
                    Section("第\(index + 1)组") {
                        if item.exercise.volumeUnit.recordsNumericLoad {
                            TextField("重量（原口径）", value: $item.exercise.plannedSets[index].weight, format: .number).keyboardType(.decimalPad)
                            Picker("重量侧别", selection: $item.exercise.plannedSets[index].weightSide) {
                                ForEach(MeasurementSide.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        Picker("次数侧别", selection: $item.exercise.plannedSets[index].repsSide) {
                            ForEach(MeasurementSide.allCases) { Text($0.title).tag($0) }
                        }
                        Stepper("次数下限 \(target(index).repsLower)", value: targetBinding(index, \.repsLower), in: 1...200)
                        Stepper("次数上限 \(target(index).repsUpper)", value: targetBinding(index, \.repsUpper), in: 1...200)
                        if !item.technical {
                            Picker("目标余力下限", selection: rirBinding(index, lower: true)) {
                                Text("按动作质量").tag(-1); ForEach(0...10, id: \.self) { Text("\($0)").tag($0) }
                            }
                            Picker("目标余力上限", selection: rirBinding(index, lower: false)) {
                                Text("按动作质量").tag(-1); ForEach(0...10, id: \.self) { Text("\($0)").tag($0) }
                            }
                        }
                        TextField("技术或质量目标", text: Binding(get: { target(index).effortCue ?? "" }, set: { item.exercise.plannedSets[index].prescription?.effortCue = $0 }))
                        Stepper("休息下限 \(target(index).restLowerSeconds)秒", value: targetBinding(index, \.restLowerSeconds), in: 0...900, step: 15)
                        Stepper("休息上限 \(target(index).restUpperSeconds)秒", value: targetBinding(index, \.restUpperSeconds), in: 0...900, step: 15)
                    }
                }
                Section("依据与当天调整") { Text(item.reason); Text(item.warmup); Text(item.adjustment) }.font(.caption)
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).sprintPage().navigationTitle(item.exercise.displayName).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存新版本") {
                            guard !item.exercise.loadGuidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  item.exercise.plannedSets.allSatisfy({ $0.weight.isFinite && $0.weight >= 0 && $0.prescription?.isValid == true }) else {
                                error = "请检查记重说明、次数/余力与休息范围。"; return
                            }
                            onSave(item); dismiss()
                        }
                    }
                }
        }
    }
    private func target(_ index: Int) -> WorkoutSetPrescription { item.exercise.plannedSets[index].prescription! }
    private func targetBinding(_ index: Int, _ path: WritableKeyPath<WorkoutSetPrescription, Int>) -> Binding<Int> {
        Binding(get: { target(index)[keyPath: path] }, set: {
            item.exercise.plannedSets[index].prescription?[keyPath: path] = $0
            item.exercise.plannedSets[index].reps = target(index).repsLower
        })
    }
    private func rirBinding(_ index: Int, lower: Bool) -> Binding<Int> {
        Binding(get: { (lower ? target(index).rirLower : target(index).rirUpper) ?? -1 }, set: { value in
            if value < 0 { item.exercise.plannedSets[index].prescription?.rirLower = nil; item.exercise.plannedSets[index].prescription?.rirUpper = nil }
            else if lower { item.exercise.plannedSets[index].prescription?.rirLower = value; if target(index).rirUpper == nil { item.exercise.plannedSets[index].prescription?.rirUpper = value } }
            else { item.exercise.plannedSets[index].prescription?.rirUpper = value; if target(index).rirLower == nil { item.exercise.plannedSets[index].prescription?.rirLower = value } }
        })
    }
}

struct CoachFullPlan: View {
    let draft: CoachDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SprintPageHeader(title: draft.title, icon: "list.clipboard", subtitle: "\(draft.localDay ?? "未选日期") · V\(draft.revision)")
            ForEach(draft.items) { item in
                CoachPlanItemSummary(item: item)
                Text(item.exercise.loadGuidance).font(.caption).foregroundStyle(EditorialTheme.muted)
                ForEach(Array(item.exercise.plannedSets.enumerated()), id: \.element.id) { index, set in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("第\(index + 1)组 · \(CoachPresentation.setLoad(set, item: item)) · \(set.weightSide.title)")
                        Text("\(set.prescription?.repsLower ?? set.reps)–\(set.prescription?.repsUpper ?? set.reps) · \(set.repsSide.title) · \(CoachPresentation.effort(set))")
                    }.font(.caption).padding(.vertical, 4)
                }
                DisclosureGroup("依据、热身与调整") { Text(item.reason); Text(item.warmup); Text(item.adjustment) }.font(.caption)
            }
            Text("偏好 \(draft.preferenceCode) · 热身另计").font(.caption2).foregroundStyle(EditorialTheme.muted)
        }
    }
}

struct CoachConfirmationView: View {
    let confirmation: CoachConfirmation
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var reviewed = false
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if saved {
                        SprintPageHeader(title: "已安排", icon: "checkmark.circle", subtitle: confirmation.preview.packet.localDay)
                        Text("完整版本已保存并核对，原始训练和旧安排保留。").font(.subheadline)
                        Button("完成") { dismiss() }.frame(minHeight: 44)
                    } else {
                        CoachFullPlan(draft: confirmation.draft)
                        Toggle("已核对这版动作、重量、组次、计量口径和日期", isOn: $reviewed)
                            .font(.subheadline).accessibilityIdentifier("确认-核对完整计划")
                    }
                    if let error { CoachInlineError(message: error) }
                }.padding(24)
            }.sprintPage().navigationTitle("确认完整计划").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(saved ? "关闭" : "返回") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    if !saved {
                        Button {
                            saving = true
                            defer { saving = false }
                            do { _ = try TrainingCoachService.confirm(confirmation, in: context); saved = true; error = nil }
                            catch { self.error = error.localizedDescription }
                        } label: { EditorialPrimary(title: saving ? "正在保存…" : "确认并安排") }
                            .disabled(!reviewed || saving).opacity(reviewed ? 1 : 0.45)
                            .accessibilityIdentifier("确认-保存安排")
                            .padding(.horizontal, 24).padding(.vertical, 10).background(EditorialTheme.paper)
                    }
                }
        }
    }
}

struct CoachConfirmedPlanView: View {
    let confirmation: CoachConfirmation
    @Environment(\.modelContext) private var context
    @State private var status = "已确认 · 正在核对保存结果"
    @State private var error: String?
    @State private var absent = false
    @State private var cancelled = false
    @State private var saved = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(status, systemImage: "lock.shield").font(.subheadline.bold()).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("确认快照-保存状态")
                CoachFullPlan(draft: confirmation.draft)
                if !saved && !cancelled {
                    Button { check() } label: { EditorialPrimary(title: "检查同一请求的保存结果") }
                    if absent {
                        Button("继续保存这个确认版本") {
                            do { _ = try TrainingCoachService.confirm(confirmation, in: context); check() }
                            catch { self.error = error.localizedDescription }
                        }.frame(minHeight: 44)
                        Button("取消这次未保存请求") {
                            do { try TrainingCoachService.cancelUnwritten(confirmation, in: context); check() }
                            catch { self.error = error.localizedDescription }
                        }.frame(minHeight: 44)
                    }
                }
                if let error { CoachInlineError(message: error) }
            }.padding(24)
        }.sprintPage().navigationTitle("已确认版本 · 只读").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).buttonStyle(.plain).task { check() }
    }
    private func check() {
        do {
            let rows = try TrainingCoachService.records(sessionID: confirmation.draft.sessionID, in: context)
            cancelled = TrainingCoachService.isCancelled(confirmation, rows: rows)
            if cancelled { status = "未保存请求已取消 · 原确认快照保留"; return }
            if try TrainingCoachService.reconcile(confirmation, in: context) != nil {
                status = "已保存安排 · 完整确认快照"; saved = true; absent = false
            } else { status = "暂未找到原安排 · 不重复创建"; absent = true }
            error = nil
        } catch { self.error = error.localizedDescription; status = "保存结果待核对" }
    }
}

struct CoachWeekView: View {
    private enum InputField: Hashable {
        case newExceptionReason, newCoreExceptionReason, confirmedExceptionReason, coreExceptionReason, customDay(Int)
    }
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingCoachRecord.createdAt, order: .reverse) private var records: [TrainingCoachRecord]
    @Query private var scheduledWorkouts: [ScheduledWorkout]
    @Query private var bodyCheckIns: [DailyBodyCheckIn]
    @State private var start = Date.now
    @State private var draft: CoachWeekDraft?
    @State private var error: String?
    @State private var lowerChainWeek = false
    @State private var customWeek = false
    @State private var newCoreException = false
    @State private var newCoreExceptionReason = ""
    @State private var reviewedCoreException = false
    @State private var coreExceptionReason = ""
    @State private var customKinds: [CoachWeekDayKind] = [.strength, .strength, .cardio, .strength, .strength, .rest, .rest]
    @State private var customFocus = ["胸", "背", "跳绳", "腿", "肩", "休息", "休息"]
    @State private var exceptionReason = ""
    @State private var request: CoachWeekConfirmation?
    @State private var receipt: String?
    @State private var receiptRequestID: UUID?
    @State private var awaitingReadback = false
    @State private var originalRequestSafelyAbsent = false
    @State private var reviewedAllDays = false
    @State private var reviewedBodyReports = false
    @State private var ruleNotice: String?
    @FocusState private var focusedInput: InputField?

    var body: some View {
        List {
            Section("生成整周候选") {
                DatePicker("开始日期", selection: $start, displayedComponents: .date)
                Toggle("本周前链／后链／综合专项", isOn: $lowerChainWeek)
                    .toggleStyle(.switch)
                    .onChange(of: lowerChainWeek) { _, enabled in
                        if enabled { customWeek = false }
                        newCoreException = false; newCoreExceptionReason = ""
                    }
                Toggle("本周自定七日目标例外", isOn: $customWeek)
                    .toggleStyle(.switch)
                    .onChange(of: customWeek) { _, enabled in
                        if enabled { lowerChainWeek = false }
                        newCoreException = false; newCoreExceptionReason = ""
                    }
                if lowerChainWeek || customWeek {
                    TextField("本周例外原因", text: $exceptionReason)
                        .focused($focusedInput, equals: .newExceptionReason)
                }
                Toggle("仅本周允许腹部少于4个动作", isOn: $newCoreException)
                    .accessibilityIdentifier("整周教练-生成时腹部例外")
                if newCoreException {
                    TextField("生成时腹部例外原因", text: $newCoreExceptionReason)
                        .focused($focusedInput, equals: .newCoreExceptionReason)
                    Text("只处理腹部目标，力量与有氧缺额仍分别保留；正式写入前仍需完整确认。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if lowerChainWeek {
                    Text("仅对所选七日有效：周一前链、周三后链、周五综合、周二及周六跳绳，周四及周日休息。它含周六跳绳，区别于长期默认的周末休息；须逐日审阅且完整确认后才写入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if customWeek {
                    Text("下方本周例外从周末休息开始；可逐日修改。只有本人选择并生成后才进入本次候选，不修改长期偏好。更改已保存草案的目标时须生成新的七日来源。")
                        .font(.footnote)
                    Button("仅本周加入周六跳绳和周日Zone 2") {
                        customKinds[5] = .cardio; customFocus[5] = "跳绳"
                        customKinds[6] = .cardio; customFocus[6] = "Zone 2"
                    }
                    ForEach(0..<7, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index])
                            Picker("类型", selection: $customKinds[index]) {
                                Text("力量").tag(CoachWeekDayKind.strength)
                                Text("有氧").tag(CoachWeekDayKind.cardio)
                                Text("休息").tag(CoachWeekDayKind.rest)
                            }
                            if customKinds[index] != .rest {
                                TextField("主肌群／跳绳／Zone 2", text: $customFocus[index])
                                    .focused($focusedInput, equals: .customDay(index))
                            }
                        }
                    }
                }
                Text("生成和编辑只保存草案，不创建正式日程。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let draft {
                Section("七日审阅 · 第\(draft.revision)版") {
                    Text("方法 \(draft.input.methodVersion) · 规则 \(draft.input.personalRuleVersion)")
                        .font(.footnote)
                    Text("项目编排来源：\(draft.input.sourceRuleVersions?.joined(separator: "、") ?? "来源版本待核")；适用起日 \(draft.input.supportedFromDay ?? "待核")。这些不是 App 偏好版本。")
                        .font(.caption)
                    ForEach(draft.input.preferences) { preference in
                        Text("\(preference.localDay) App生效偏好：\(preference.code ?? "缺失，待核")")
                            .font(.caption)
                    }
                    ForEach(draft.input.recovery, id: \.self) { Text("已记录恢复背景：" + $0).font(.caption) }
                    if let exception = draft.input.exception {
                        Text("本周例外 \(exception.startDay) 至 \(exception.endDay)：\(exception.reason)；到期不续排。")
                            .font(.caption)
                    } else {
                        Text("长期默认目标候选；仅覆盖本次所选七日。")
                            .font(.caption)
                    }
                    if let coreException = draft.input.coreException {
                        Text("本周腹部例外 \(coreException.startDay) 至 \(coreException.endDay)：\(coreException.reason)；长期目标不变。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text("原始来源：\(draft.input.startDay) · \(draft.sourceFingerprint.prefix(12))；草案版本仅供审阅")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("草案根 \(draft.rootID.uuidString)\(draft.parentDraftID.map { "；继承原草案 " + $0.uuidString } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(draft.input.unknowns, id: \.self) { Text("来源缺口：\($0)").font(.caption) }
                    ForEach(draft.weeklyShortfall ?? [], id: \.self) { Text($0).foregroundStyle(.red) }
                    if !(draft.weeklyShortfall ?? []).isEmpty {
                        Text("本周力量、有氧或腹部目标仍有缺额。可逐日主动调整，再重验完整七日；也可填写原因，确认仅对本周有效的目标例外。未解决缺额不能写正式日程，默认不把周末休息改成训练。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    TextField("本周腹部例外原因", text: $coreExceptionReason)
                        .focused($focusedInput, equals: .coreExceptionReason)
                    Toggle("本人确认本周腹部可少于4个动作", isOn: $reviewedCoreException)
                        .accessibilityIdentifier("整周教练-确认本周腹部例外")
                    Button("仅确认本周腹部例外") { confirmCurrentCoreException(draft) }
                        .disabled(!reviewedCoreException || coreExceptionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || awaitingReadback || request != nil)
                    Text("此项只处理本周腹部目标，力量与有氧缺额继续分别保留。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField(draft.input.exception == nil ? "本周目标例外原因" : "重新确认本周目标原因", text: $exceptionReason)
                        .focused($focusedInput, equals: .confirmedExceptionReason)
                    Text("确认当前七日目标会同时采用显示的力量、跳绳和 Zone 2 次数。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(draft.input.exception == nil
                           ? "将当前七日目标确认为仅本周例外"
                           : "重新确认当前七日为仅本周新例外") { confirmCurrentWeekException(draft) }
                        .disabled(exceptionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            awaitingReadback || request != nil)
                    Text(draft.input.exception == nil
                         ? "会先核对原始来源，保留已编辑的逐组处方，再以新来源和版本完整重验；旧草案继续留档。"
                         : "原本周例外仍保留在旧版；本人改动七日目标后，填写新原因并重新确认，才会以新 root 重验本周目标。正式日程仍需另行完整审阅和确认。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(draft.days) { day in
                        NavigationLink {
                            CoachWeekDayEditor(day: day, catalog: draft.input.catalog,
                                canEdit: !awaitingReadback && request == nil, saveGoal: { kind, focus, reason in
                                revise(day: day, kind: kind, focus: focus, reason: reason)
                            }, saveMovements: { movements, reason in
                                reviseMovements(day: day, movements: movements, reason: reason)
                            }, saveZone2: { id, reason in
                                reviseZone2(day: day, exerciseID: id, reason: reason)
                            }, savePreserved: { existingID, kind, focus, reason in
                                reviewPreserved(day: day, existingID: existingID, kind: kind, focus: focus, reason: reason)
                            })
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(day.localDay) · \(day.title)")
                                Text(day.estimatedSeconds.map { "完整预计 \(Int(ceil(Double($0) / 60))) 分钟" } ?? "完整时间待核")
                                    .font(.caption)
                                Text(day.blockers.isEmpty ? day.kind.title : day.blockers.joined(separator: "；"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("整周教练-日期-\(day.localDay)")
                    }
                }
                if !draft.edits.isEmpty {
                    Section("本人修改与原草案差异") {
                        ForEach(draft.edits) { edit in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(edit.day) · \(edit.field)").font(.headline)
                                Text("原：\(edit.before)")
                                Text("改：\(edit.after)")
                                Text("原因：\(edit.reason)")
                            }.font(.caption)
                        }
                    }
                }
                if let retainedReviews = draft.input.retainedReviews, !retainedReviews.isEmpty {
                    Section("本人核对的保留安排") {
                        ForEach(retainedReviews) { review in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(review.localDay) · 原安排 \(review.existingID.uuidString)")
                                Text("本周目标：\(review.kind.title)\(review.focus.isEmpty ? "" : " · " + review.focus)")
                                Text("本人核对原因：\(review.reason)")
                                Text("原来源摘要：\(review.sourceDigest.prefix(12))；不改原始记录。")
                            }.font(.caption)
                        }
                    }
                }
                if draft.ruleCandidates.isEmpty, let ruleNotice {
                    Section("规则回放") { Text(ruleNotice).font(.caption) }
                }
                if !draft.ruleCandidates.isEmpty {
                    Section("规则变化候选 · 尚未生效") {
                        ForEach(draft.ruleCandidates) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.originalRule + " → " + item.proposedChange)
                                Text("回放：" + item.replayResult)
                                Text("状态：" + item.status + "；长期偏好仍需本人另行确认")
                                ForEach(item.evidence, id: \.self) { Text("依据：" + $0) }
                                ForEach(item.unknowns, id: \.self) { Text("未知：" + $0) }
                                if item.executableVersion != nil {
                                    Button("本人确认该规则版本生效") { activate(item, draft: draft) }
                                        .accessibilityIdentifier("整周教练-规则生效-\(item.id.uuidString)")
                                } else {
                                    Text("此修改仅保留为人工差异；未通过可执行回放，不生成生效按钮。")
                                }
                            }.font(.caption)
                        }
                        if let ruleNotice { Text(ruleNotice).font(.caption) }
                        Button("回退上一生效规则版本") { rollbackRule() }
                    }
                }
                Section("确认状态") {
                    Text("当前草案版本：第\(draft.revision)版")
                    Text("七日草案和本人编辑只保存版本。正式安排须在完整审阅后明确确认。保存安排不代表本人接受训练效果；后续需分别记录实际训练与恢复。")
                        .font(.footnote)
                    Toggle("我已逐日审阅全部七日，包括保留安排、有氧、缺项、逐组目标和本人修改", isOn: $reviewedAllDays)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("整周教练-完整审阅")
                    let reports = relevantBodyReports(draft)
                    if !reports.isEmpty {
                        Text("以下本人自报体感影响本周候选；原记录未结构化，不能把它解释为恢复正常或具体诊断。")
                            .font(.footnote)
                        ForEach(reports, id: \.id) { report in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(report.localDay) · 记录 \(report.id.uuidString)")
                                Text("说明：\(report.note.isEmpty ? "未写说明" : report.note)\(report.hasBodyMarkers ? "；另有身体标记" : "")")
                                if let row = bodyCheckIns.first(where: { $0.id == report.id }) {
                                    NavigationLink("打开本人原始身体打卡") {
                                        DailyBodyCheckInEditor(checkIn: row, date: row.date)
                                    }
                                } else {
                                    Text("原始打卡当前不可读取，请重新生成核对来源。")
                                        .foregroundStyle(.orange)
                                }
                            }.font(.caption)
                        }
                        Toggle("我已核对以上具体体感；若有疼痛、功能受限或恢复差，先补训练反馈并重新生成", isOn: $reviewedBodyReports)
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("整周教练-体感核对")
                    }
                    let signals = relevantRecoverySignals(draft)
                    if !signals.isEmpty {
                        Text("训练反馈可从以下原场次核对；明确异常仍由规则阻断。反馈修改后须重新生成。")
                            .font(.footnote)
                        ForEach(signals, id: \.id) { signal in
                            NavigationLink("\(signal.trainingDay) · 训练反馈来源场次 \(signal.sessionID.uuidString)") {
                                TrainingReviewView(sessionID: signal.sessionID)
                            }
                        }
                    }
                    Button("确认并写入正式七日日程") { confirm() }
                        .disabled(!reviewedAllDays || (!reports.isEmpty && !reviewedBodyReports) ||
                            awaitingReadback || request != nil || !canConfirm(draft))
                        .accessibilityIdentifier("整周教练-确认")
                    if !canConfirm(draft) { Text("当前有缺项或规则阻断；先修改并重新验证。") .foregroundStyle(.red) }
                    if let receipt { Text(receipt).foregroundStyle(.green) }
                    if awaitingReadback, let request {
                        Text("原请求 \(request.id.uuidString) 保存结果待核；请使用下方原请求恢复，不重新生成。")
                            .foregroundStyle(.orange)
                        Button("核对原请求回读") { recover(request) }
                        if originalRequestSafelyAbsent {
                            Button("取消本机未发现写入的原请求，重新生成") { cancelSafelyAbsentRequest(request) }
                        }
                    }
                }
            }
            let saved = records.filter { $0.kind == "week_draft" }
            if !saved.isEmpty {
                Section("已保存草案") {
                    ForEach(saved) { row in
                        if let item = try? TrainingCoachService.decode(CoachWeekDraft.self, row) {
                            Button("\(item.input.startDay) · 第\(item.revision)版") {
                                draft = item; error = nil; reviewedAllDays = false; reviewedBodyReports = false
                                exceptionReason = ""
                            }
                        }
                    }
                }
            }
            let submitted = records.filter { $0.kind == "week_confirmation" }
            if !submitted.isEmpty {
                Section("已提交请求与回读") {
                    ForEach(submitted) { row in
                        if let item = try? TrainingCoachService.decode(CoachWeekConfirmation.self, row) {
                            Button("\(item.draft.input.startDay) · 第\(item.draft.revision)版 · 核对原请求") { recover(item) }
                            NavigationLink("回顾原草案、本人修改、实际与恢复") {
                                CoachWeekOutcomeReviewView(confirmation: item)
                            }
                            if receiptRequestID == item.id {
                                ForEach(item.ropes, id: \.id) { rope in
                                    if let currentDay = currentScheduledDay(id: rope.id) {
                                        NavigationLink("\(currentDay) · 跳绳实际记录入口") {
                                            TrainingDateMenuView(localDay: currentDay)
                                        }
                                    } else {
                                        Text("跳绳请求成员 \(rope.id.uuidString) 的当前日程待核")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                ForEach(item.members.filter { member in
                                    member.packet.title.hasPrefix("Zone 2") && item.draft.days.contains { day in
                                        day.localDay == member.packet.localDay &&
                                            day.zone2?.exerciseID == member.packet.exercises.first?.catalogExerciseID
                                    }
                                }, id: \.packet.id) { member in
                                    if let currentDay = currentScheduledDay(id: member.packet.id) {
                                        NavigationLink("\(currentDay) · Zone 2实际记录入口") {
                                            TrainingDateMenuView(localDay: currentDay)
                                        }
                                    } else {
                                        Text("Zone 2请求成员 \(member.packet.id.uuidString) 的当前日程待核")
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("生成") { focusedInput = nil; generate() }
                    .disabled(awaitingReadback)
                    .accessibilityLabel("生成七日候选")
                    .accessibilityIdentifier("整周教练-生成")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedInput = nil }
                    .accessibilityIdentifier("整周教练-收起键盘")
            }
        }
        .navigationTitle("整周训练教练")
        .onChange(of: start) { _, _ in newCoreException = false; newCoreExceptionReason = "" }
        .onChange(of: customKinds) { _, _ in newCoreException = false; newCoreExceptionReason = "" }
        .onChange(of: customFocus) { _, _ in newCoreException = false; newCoreExceptionReason = "" }
        .onChange(of: draft?.id) { _, _ in reviewedCoreException = false; coreExceptionReason = "" }
        .onAppear {
#if DEBUG
            guard CommandLine.arguments.contains(CoachWeekUITestFixture.argument) else { return }
            do {
                try CoachWeekUITestFixture.prepare(in: context)
                if draft == nil, CommandLine.arguments.contains("--ui-testing-coach-week-past-rest") {
                    var calendar = Calendar(identifier: .iso8601); calendar.timeZone = .current
                    if let week = calendar.dateInterval(of: .weekOfYear, for: .now)?.start {
                        start = calendar.isDateInToday(week) ? (calendar.date(byAdding: .day, value: -7, to: week) ?? week) : week
                    }
                } else if draft == nil, let date = TrainingLocalDate.date(CoachWeekUITestFixture.startDay, timeZone: .current) { start = date }
            } catch { self.error = error.localizedDescription }
#endif
        }
    }

    private func generate() {
        guard !awaitingReadback else { return }
        do {
            let coreSelected = newCoreException
            let coreReason = newCoreExceptionReason
            let zone = TimeZone.current
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = zone
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start else {
                throw TrainingCoachError.invalid("无法确定周一日期。")
            }
            start = weekStart
            #if DEBUG
            let method = CommandLine.arguments.contains(CoachWeekUITestFixture.argument)
                && !CommandLine.arguments.contains("--ui-testing-coach-week-alternating")
                ? CoachWeekService.methodVersion : CoachWeekService.alternatingMethodVersion
            #else
            let method = CoachWeekService.alternatingMethodVersion
            #endif
            let defaults = CoachWeekService.defaultGoals(start: weekStart, zone: zone, ruleMethod: method)
            let exception: CoachWeekException?
            if lowerChainWeek || customWeek {
                guard !exceptionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TrainingCoachError.invalid("专项周须说明原因。")
                }
                let focus = lowerChainWeek ? ["前链", "跳绳", "后链", "休息", "综合", "跳绳", "休息"] : customFocus
                let kinds: [CoachWeekDayKind] = lowerChainWeek
                    ? [.strength, .cardio, .strength, .rest, .strength, .cardio, .rest]
                    : customKinds
                guard focus.count == 7, kinds.count == 7,
                      zip(kinds, focus).allSatisfy({ kind, label in
                          kind == .rest || !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      }) else {
                    throw TrainingCoachError.invalid("本周七日目标须填写完整。")
                }
                let goals = defaults.enumerated().map { index, item in
                    CoachWeekGoal(localDay: item.localDay, kind: kinds[index],
                        focus: kinds[index] == .rest ? "休息" : focus[index], reason: exceptionReason)
                }
                exception = CoachWeekException(id: UUID(), startDay: goals[0].localDay, endDay: goals[6].localDay,
                    reason: exceptionReason, goals: goals, confirmation: "本人在整周教练中选择本周专项目标")
            } else { exception = nil }
            let goals = exception?.goals ?? defaults
            if coreSelected && coreReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw TrainingCoachError.invalid("本周腹部例外须填写原因。")
            }
            let coreException = coreSelected ? CoachWeekCoreException(startDay: goals[0].localDay, endDay: goals[6].localDay,
                reason: coreReason, confirmation: CoachWeekService.coreExceptionConsent, goals: goals) : nil
            let input = try CoachWeekService.capture(start: weekStart, exception: exception, coreException: coreException, ruleMethod: method, in: context)
            let result = try CoachWeekService.generate(input: input, goals: goals)
            try CoachWeekService.save(result, in: context)
            draft = result; error = nil; reviewedAllDays = false; reviewedBodyReports = false
            exceptionReason = ""; newCoreExceptionReason = ""; coreExceptionReason = ""; newCoreException = false; reviewedCoreException = false
            request = nil; receipt = nil; receiptRequestID = nil
            originalRequestSafelyAbsent = false
        } catch { self.error = error.localizedDescription }
    }

    private func canConfirm(_ draft: CoachWeekDraft) -> Bool {
        draft.days.count == 7 && draft.weeklyShortfall?.isEmpty == true &&
            draft.days.allSatisfy { $0.kind != .missing && $0.blockers.isEmpty }
    }

    private func relevantBodyReports(_ draft: CoachWeekDraft) -> [CoachWeekBodyReport] {
        guard let zone = TimeZone(identifier: draft.input.timeZone) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return (draft.input.bodyReports ?? []).filter { report in
            guard !report.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || report.hasBodyMarkers,
                  let source = TrainingLocalDate.date(report.localDay, timeZone: zone) else { return false }
            return draft.days.contains { day in
                guard day.kind == .strength || day.kind == .cardio || day.kind == .preserved ||
                        day.cardio != nil || day.zone2 != nil,
                      let target = TrainingLocalDate.date(day.localDay, timeZone: zone),
                      let gap = calendar.dateComponents([.day], from: source, to: target).day else { return false }
                return (0...7).contains(gap)
            }
        }
    }

    private func relevantRecoverySignals(_ draft: CoachWeekDraft) -> [CoachWeekRecoverySignal] {
        guard let zone = TimeZone(identifier: draft.input.timeZone) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return (draft.input.recoverySignals ?? []).filter { signal in
            guard let source = TrainingLocalDate.date(signal.trainingDay, timeZone: zone) else { return false }
            return draft.days.contains { day in
                guard day.kind == .strength || day.kind == .cardio || day.cardio != nil || day.zone2 != nil,
                      let target = TrainingLocalDate.date(day.localDay, timeZone: zone),
                      let gap = calendar.dateComponents([.day], from: source, to: target).day else { return false }
                return (0...7).contains(gap)
            }
        }
    }

    private func currentScheduledDay(id: UUID) -> String? {
        guard let schedule = scheduledWorkouts.first(where: { $0.id == id }) else { return nil }
        return TrainingScheduleDate.localDay(schedule)
    }

    private func confirmCurrentWeekException(_ original: CoachWeekDraft) {
        guard !awaitingReadback, request == nil else { return }
        do {
            draft = try CoachWeekService.confirmWeekException(original, reason: exceptionReason, in: context)
            reviewedAllDays = false; reviewedBodyReports = false; exceptionReason = ""
            reviewedCoreException = false
            request = nil; receipt = nil; receiptRequestID = nil; error = nil
            originalRequestSafelyAbsent = false
        } catch { self.error = error.localizedDescription }
    }

    private func confirmCurrentCoreException(_ original: CoachWeekDraft) {
        guard !awaitingReadback, request == nil, reviewedCoreException else { return }
        do {
            draft = try CoachWeekService.confirmCoreException(original, reason: coreExceptionReason, in: context)
            reviewedAllDays = false; reviewedBodyReports = false; coreExceptionReason = ""; reviewedCoreException = false
            request = nil; receipt = nil; receiptRequestID = nil; error = nil
            originalRequestSafelyAbsent = false
        } catch { self.error = error.localizedDescription }
    }

    private func confirm() {
        guard let draft, canConfirm(draft), reviewedAllDays,
              relevantBodyReports(draft).isEmpty || reviewedBodyReports else { return }
        do {
            let prepared = try CoachWeekService.prepareConfirmation(draft, in: context)
            request = prepared
            originalRequestSafelyAbsent = false
            try ConfirmedDailyTrainingPlanService.applyCoachWeek(prepared, in: context)
            receipt = "正式七日日程已保存并独立回读；请求 \(prepared.id.uuidString)。实际训练和恢复仍待记录。"
            receiptRequestID = prepared.id
            awaitingReadback = false; error = nil
        } catch {
            self.error = error.localizedDescription
            if let request { awaitingReadback = true; recover(request) }
        }
    }

    private func recover(_ original: CoachWeekConfirmation) {
        request = original
        switch ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(original, in: context) {
        case .committed:
            receipt = "原请求 \(original.id.uuidString) 已完整回读；未创建新请求。"
            receiptRequestID = original.id
            awaitingReadback = false; originalRequestSafelyAbsent = false; error = nil
        case .safelyAbsent:
            awaitingReadback = true; originalRequestSafelyAbsent = CloudSyncRuntime.isDisabled
            error = CloudSyncRuntime.isDisabled
                ? "本机独立回读未发现原请求 \(original.id.uuidString) 及成员写入；可明确取消本机请求后重新生成。"
                : "本机独立回读未发现原请求 \(original.id.uuidString) 及成员写入；云同步可能仍未决，须继续核对，暂不可新建。"
        case .unknown:
            awaitingReadback = true; originalRequestSafelyAbsent = false
            error = "原请求 \(original.id.uuidString) 有部分写入或读取不确定；保持原请求，停止新建。"
        }
    }

    private func cancelSafelyAbsentRequest(_ original: CoachWeekConfirmation) {
        guard CloudSyncRuntime.isDisabled,
              case .safelyAbsent = ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(original, in: context) else {
            recover(original)
            return
        }
        request = nil; awaitingReadback = false; originalRequestSafelyAbsent = false
        reviewedAllDays = false; reviewedBodyReports = false; receipt = nil; receiptRequestID = nil
        error = "本机独立回读未发现原请求及成员写入，原本机请求已取消；请重新生成并审阅。此结论不代表其它设备或云端状态。"
    }

    private func activate(_ candidate: CoachWeekRuleCandidate, draft: CoachWeekDraft) {
        do {
            ruleNotice = try CoachWeekService.activateRuleCandidate(candidate, draft: draft, in: context)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func rollbackRule() {
        do {
            ruleNotice = try CoachWeekService.rollbackRule(in: context)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func reviseMovements(day: CoachWeekDay, movements: [CoachWeekMovement], reason: String) {
        guard !awaitingReadback, request == nil else { return }
        guard let current = draft, let index = current.days.firstIndex(where: { $0.localDay == day.localDay }) else { return }
        do {
            var days = current.days
            days[index].movements = movements
            days = CoachWeekService.revalidateWeek(days, input: current.input)
            let edit = CoachWeekEdit(id: UUID(), day: day.localDay, field: "逐组处方",
                                     before: movementSummary(day.movements), after: movementSummary(movements), reason: reason)
            let candidate = candidateForEdit(current, days: days, edit: edit)
            draft = try CoachWeekService.revise(current, days: days, edits: [edit], candidates: candidate.map { [$0] } ?? [],
                                                weeklyShortfall: CoachWeekService.weeklyShortfalls(days, input: current.input), in: context)
            error = nil; reviewedAllDays = false; reviewedBodyReports = false; exceptionReason = ""
        } catch { self.error = error.localizedDescription }
    }

    private func revise(day: CoachWeekDay, kind: CoachWeekDayKind, focus: String, reason: String) {
        guard !awaitingReadback, request == nil else { return }
        guard let current = draft else { return }
        do {
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TrainingCoachError.invalid("修改时请填写原因。")
            }
            let goal = CoachWeekGoal(localDay: day.localDay, kind: kind, focus: focus, reason: reason)
            let days = CoachWeekService.revalidateWeek(try CoachWeekService.regenerateDay(current, goal: goal), input: current.input)
            guard let replacement = days.first(where: { $0.localDay == day.localDay }) else { return }
            let edit = CoachWeekEdit(id: UUID(), day: day.localDay, field: "日安排", before: day.title,
                                     after: replacement.title, reason: reason)
            let candidate = candidateForEdit(current, days: days, edit: edit)
            draft = try CoachWeekService.revise(current, days: days, edits: [edit], candidates: candidate.map { [$0] } ?? [],
                                                weeklyShortfall: CoachWeekService.weeklyShortfalls(days, input: current.input), in: context)
            error = nil; reviewedAllDays = false; reviewedBodyReports = false; exceptionReason = ""
        } catch { self.error = error.localizedDescription }
    }

    private func reviseZone2(day: CoachWeekDay, exerciseID: UUID, reason: String) {
        guard !awaitingReadback, request == nil else { return }
        guard let current = draft, let index = current.days.firstIndex(where: { $0.localDay == day.localDay }),
              let item = current.input.catalog.first(where: { $0.id == exerciseID }), day.zone2 != nil else { return }
        do {
            var days = current.days
            days[index].zone2?.exerciseID = exerciseID
            days[index].zone2?.mode = item.name
            days = CoachWeekService.revalidateWeek(days, input: current.input)
            let edit = CoachWeekEdit(id: UUID(), day: day.localDay, field: "Zone 2器械身份",
                before: day.zone2?.mode ?? "未知", after: item.name + " · " + item.id.uuidString, reason: reason)
            let candidate = candidateForEdit(current, days: days, edit: edit)
            draft = try CoachWeekService.revise(current, days: days, edits: [edit], candidates: candidate.map { [$0] } ?? [],
                weeklyShortfall: CoachWeekService.weeklyShortfalls(days, input: current.input), in: context)
            error = nil; reviewedAllDays = false; reviewedBodyReports = false
        } catch { self.error = error.localizedDescription }
    }

    private func reviewPreserved(day: CoachWeekDay, existingID: UUID, kind: CoachWeekDayKind,
                                 focus: String, reason: String) {
        guard !awaitingReadback, request == nil else { return }
        guard let current = draft, day.existing.contains(where: { $0.id == existingID }) else { return }
        do {
            draft = try CoachWeekService.reviewPreservedArrangement(current, existingID: existingID,
                kind: kind, focus: focus, reason: reason, in: context)
            reviewedAllDays = false; reviewedBodyReports = false
            request = nil; receipt = nil; receiptRequestID = nil; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func movementSummary(_ items: [CoachWeekMovement]) -> String {
        items.enumerated().map { index, item in
            let sets = item.exercise.plannedSets.map { set in
                let target = set.prescription
                return "\(set.weight.formatted())\(item.exercise.volumeUnit.symbol)×\(set.reps) RIR\(target?.rirLower.map(String.init) ?? "?")–\(target?.rirUpper.map(String.init) ?? "?") 休\(target?.restUpperSeconds ?? 0)秒"
            }.joined(separator: "/")
            return "\(index + 1).\(item.exercise.displayName)[\(sets)]"
        }.joined(separator: "；")
    }

    private func candidateForEdit(_ original: CoachWeekDraft, days: [CoachWeekDay], edit: CoachWeekEdit) -> CoachWeekRuleCandidate? {
        do { return try CoachWeekService.ruleCandidate(original: original, revisedDays: days, edits: [edit]) }
        catch {
            ruleNotice = "人工修改可保存；规则回放未形成：\(error.localizedDescription)"
            return nil
        }
    }
}

private struct CoachWeekOutcomeReviewView: View {
    let confirmation: CoachWeekConfirmation
    @Environment(\.modelContext) private var context
    @State private var outcome: CoachWeekOutcome?
    @State private var outcomeCandidate: CoachWeekRuleCandidate?
    @State private var savedCandidateDraft: CoachWeekDraft?
    @State private var ruleNotice: String?
    @State private var error: String?

    var body: some View {
        List {
            Section("已确认版本与来源") {
                Text("\(confirmation.draft.input.startDay) · 第\(confirmation.draft.revision)版")
                Text("方法 \(confirmation.draft.input.methodVersion) · 规则 \(confirmation.draft.input.personalRuleVersion)")
                Text("项目方法来源：\(confirmation.draft.input.sourceRuleVersions?.joined(separator: "、") ?? "待核")；适用起日 \(confirmation.draft.input.supportedFromDay ?? "待核")。")
                    .font(.caption)
                ForEach(confirmation.draft.input.preferences) { preference in
                    Text("\(preference.localDay) App偏好：\(preference.code ?? "缺失，待核")")
                        .font(.caption)
                }
                Text("请求 \(confirmation.id.uuidString)；保存记录与本人接受、真实效果分别核对。")
            }
            Section("本人修改前后") {
                if confirmation.draft.edits.isEmpty { Text("此版本没有本人逐项修改记录。") }
                ForEach(confirmation.draft.edits) { edit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(edit.day) · \(edit.field)").font(.headline)
                        Text("原：\(edit.before)")
                        Text("本人：\(edit.after)")
                        Text("原因：\(edit.reason)")
                    }.font(.caption)
                }
            }
            Section("本周保留安排与来源") {
                let preserved = confirmation.draft.days.filter { $0.kind == .preserved || !$0.existing.isEmpty }
                if preserved.isEmpty { Text("本周草案没有标记为保留的既有安排。") }
                ForEach(preserved) { day in
                    if day.existing.isEmpty {
                        Text("\(day.localDay)：保留安排来源未知；待核对原日程或实际训练。")
                            .foregroundStyle(.orange)
                    } else {
                        ForEach(day.existing) { item in
                            Text("\(day.localDay) · \(item.title) · \(item.status) · 来源 \(item.source) · ID \(item.id.uuidString)")
                        }
                    }
                }
                ForEach(confirmation.draft.input.retainedReviews ?? []) { review in
                    Text("本人核对 \(review.localDay) · \(review.existingID.uuidString)：\(review.kind.title)\(review.focus.isEmpty ? "" : " · " + review.focus)；原因 \(review.reason)；原来源摘要 \(review.sourceDigest.prefix(12))")
                        .font(.caption)
                }
                Text("新增周请求成员与保留安排分开归属，不按同日合并实际。")
                    .font(.caption)
            }
            Section("已归属的实际训练") {
                if let outcome {
                    if outcome.actual.isEmpty && outcome.ropeActual.isEmpty {
                        Text("暂无可按已确认日程 ID 归属的实际记录；是否训练未知。")
                    }
                    ForEach(outcome.actual) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.localDay) · \(item.name)").font(.headline)
                            Text("来源日程 \(item.scheduledWorkoutID?.uuidString ?? "未知")；" + (item.classificationKnown == true
                                ? "完成非热身 \(item.actual.filter { $0.completed && !$0.warmup }.count) 组"
                                : "完成 \(item.actual.filter(\.completed).count) 条；组别性质未知"))
                            ForEach(item.actual.filter(\.completed)) { set in
                                Text("\(set.weight.map { "\($0.formatted()) \(item.unit.symbol)" } ?? "重量未知") × \(set.reps)；RIR \(set.rir.map(String.init) ?? "未知")；\(item.classificationKnown == true ? (set.warmup ? "热身" : "工作组") : "组别性质未知")")
                            }
                        }.font(.caption)
                    }
                    ForEach(outcome.ropeActual, id: \.id) { rope in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("跳绳实际 · \(rope.date.formatted(date: .abbreviated, time: .omitted))").font(.headline)
                            Text("来源日程 \(rope.scheduleID.uuidString)；次数 \(rope.count.map(String.init) ?? "未知")；活动 \(rope.activeSeconds.map { "\($0)秒" } ?? "未知")；总时长 \(rope.elapsedSeconds.map { "\($0)秒" } ?? "未知")")
                        }.font(.caption)
                    }
                } else { Text("实际记录待读取。") }
            }
            Section("恢复观察与未知") {
                if let outcome {
                    if outcome.recovery.isEmpty { Text("暂无可核对的次晨恢复；状态未知。") }
                    ForEach(outcome.recovery, id: \.self) { Text($0) }
                    ForEach(outcome.provenance, id: \.self) { Text("归属依据：" + $0).font(.caption) }
                    ForEach(outcome.unknowns, id: \.self) { Text("未知：" + $0).foregroundStyle(.orange) }
                } else { Text("恢复状态待读取。") }
            }
            Section("规则候选与效果边界") {
                if confirmation.draft.ruleCandidates.isEmpty { Text("尚无可回放规则候选。") }
                ForEach(confirmation.draft.ruleCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(candidate.originalRule + " → " + candidate.proposedChange)
                        Text(candidate.replayResult)
                        Text("依据：" + candidate.evidence.joined(separator: "；"))
                        Text("边界：" + candidate.unknowns.joined(separator: "；"))
                    }.font(.caption)
                }
                Text("结构回放通过不表示真人接受或训练效果改善；候选须经明确应用才改变之后的生成规则。")
                    .font(.caption)
                Button("按已确认版本回顾并预览规则候选") { previewOutcomeCandidate() }
                if let outcomeCandidate {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("原规则：" + outcomeCandidate.originalRule)
                        Text("建议：" + outcomeCandidate.proposedChange)
                        Text("同一冻结输入回放：" + outcomeCandidate.replayResult)
                        Text("状态：" + outcomeCandidate.status)
                        ForEach(outcomeCandidate.evidence, id: \.self) { Text("依据：" + $0) }
                        ForEach(outcomeCandidate.unknowns, id: \.self) { Text("未知或反证：" + $0) }
                        Text("预览未保存或生效；真实效果仍需未来同口径训练与恢复观察。")
                    }.font(.caption)
                    if savedCandidateDraft == nil {
                        Button("保存该结果规则候选为新草案版本") { saveOutcomeCandidate(outcomeCandidate) }
                    }
                }
                if let savedCandidateDraft, let saved = savedCandidateDraft.ruleCandidates.last {
                    Text("结果候选已保存为第\(savedCandidateDraft.revision)版；确认版处方与实际记录未改。")
                        .font(.caption)
                    if saved.executableVersion != nil {
                        Button("本人确认使该回放规则生效") { activateOutcomeCandidate(saved, draft: savedCandidateDraft) }
                    } else {
                        Text("该候选仅记录差异和观察，未通过生效条件。")
                    }
                }
                if let ruleNotice { Text(ruleNotice).font(.caption) }
            }
            if let error { Section("读取错误") { Text(error).foregroundStyle(.red) } }
            Button("刷新实际与恢复") { load() }
        }
        .navigationTitle("整周训练回顾")
        .task { load() }
    }

    private func load() {
        do { outcome = try CoachWeekService.evaluateOutcome(confirmation.draft, in: context); error = nil }
        catch { outcome = nil; self.error = error.localizedDescription }
    }

    private func previewOutcomeCandidate() {
        do {
            let candidate = try CoachWeekService.ruleCandidateFromOutcome(confirmation.draft, in: context)
            guard candidate.outcome?.draftID == confirmation.draft.id else {
                throw TrainingCoachError.invalid("结果观察没有绑定此已确认草案版本。")
            }
            outcomeCandidate = candidate; savedCandidateDraft = nil; ruleNotice = nil; error = nil
        } catch { outcomeCandidate = nil; self.error = error.localizedDescription }
    }

    private func saveOutcomeCandidate(_ candidate: CoachWeekRuleCandidate) {
        do {
            savedCandidateDraft = try CoachWeekService.saveOutcomeRuleCandidate(confirmation.draft,
                candidate: candidate, in: context)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func activateOutcomeCandidate(_ candidate: CoachWeekRuleCandidate, draft: CoachWeekDraft) {
        do { ruleNotice = try CoachWeekService.activateRuleCandidate(candidate, draft: draft, in: context); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct CoachWeekDayEditor: View {
    private enum InputField: Hashable {
        case movementReason, goalReason, goalFocus, retainedReason, zone2Reason, weight(UUID)
    }
    let day: CoachWeekDay
    let catalog: [CoachWeekCatalogItem]
    let canEdit: Bool
    let saveGoal: (CoachWeekDayKind, String, String) -> Void
    let saveMovements: ([CoachWeekMovement], String) -> Void
    let saveZone2: (UUID, String) -> Void
    let savePreserved: (UUID, CoachWeekDayKind, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CoachWeekDayKind
    @State private var focus: String
    @State private var reason = ""
    @State private var movements: [CoachWeekMovement]
    @State private var zone2ExerciseID: UUID?
    @State private var preservedID: UUID?
    @State private var preservedKind: CoachWeekDayKind = .strength
    @State private var preservedFocus = "胸"
    @FocusState private var focusedInput: InputField?

    init(day: CoachWeekDay, catalog: [CoachWeekCatalogItem], canEdit: Bool,
         saveGoal: @escaping (CoachWeekDayKind, String, String) -> Void,
         saveMovements: @escaping ([CoachWeekMovement], String) -> Void,
         saveZone2: @escaping (UUID, String) -> Void,
         savePreserved: @escaping (UUID, CoachWeekDayKind, String, String) -> Void) {
        self.day = day; self.catalog = catalog; self.canEdit = canEdit
        self.saveGoal = saveGoal; self.saveMovements = saveMovements
        self.saveZone2 = saveZone2
        self.savePreserved = savePreserved
        _kind = State(initialValue: day.kind)
        _focus = State(initialValue: day.focus)
        _movements = State(initialValue: day.movements)
        _zone2ExerciseID = State(initialValue: day.zone2?.exerciseID)
        _preservedID = State(initialValue: day.existing.first?.id)
    }

    var body: some View {
        Form {
            if !canEdit {
                Section("原请求待核对") {
                    Text("可继续查看七日原草案；原确认请求未核清前不可修改或生成新版。")
                }
            }
            if day.kind != .preserved && day.blockers.contains(where: { $0.hasPrefix("过去日期") }) {
                Section("核对过去日期") {
                    TextField("过去日期核对原因", text: $reason)
                        .focused($focusedInput, equals: .goalReason)
                    Button("本人确认当天休息") { focusedInput = nil; saveGoal(.rest, "", reason); dismiss() }
                        .disabled(!canEdit || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if day.kind != .preserved {
                Section("修改当日目标") {
                    Picker("类型", selection: $kind) {
                        Text("力量").tag(CoachWeekDayKind.strength)
                        Text("有氧").tag(CoachWeekDayKind.cardio)
                        Text("休息").tag(CoachWeekDayKind.rest)
                    }
                    .accessibilityIdentifier("整周教练-当日类型")
                    TextField("肌群或有氧类型", text: $focus)
                        .focused($focusedInput, equals: .goalFocus)
                        .accessibilityIdentifier("整周教练-当日目标")
                    TextField("修改原因", text: $reason)
                        .focused($focusedInput, equals: .goalReason)
                        .accessibilityIdentifier("整周教练-目标修改原因")
                    Button("保存新版本") { saveGoal(kind, focus, reason); dismiss() }
                        .disabled(!canEdit || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("现有安排") {
                Text("\(day.kind.title) · \(day.focus.isEmpty ? day.title : day.focus)")
                if day.blockers.contains(where: { $0.hasPrefix("过去日期") }) {
                    Text("若你确认当天休息，可在下方选择休息并填写核对原因；不会新增历史训练记录。")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(day.estimatedSeconds.map { "完整预计 \(Int(ceil(Double($0) / 60))) 分钟（含热身、组间休息、换器械及缓冲）" } ?? "完整时间待核")
                    .font(.caption)
                ForEach(day.existing) { item in
                    Text("保留：\(item.title) · \(item.status) · \(item.source) · ID \(item.id.uuidString)")
                    if item.frozenExercises?.isEmpty != false {
                        Text("原安排没有可核验的逐组快照；本人注记不补写历史组数。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                ForEach(day.rationale, id: \.self) { Text($0) }
                ForEach(day.blockers, id: \.self) { Text("待解决：" + $0).foregroundStyle(.red) }
            }
            if day.kind == .strength {
                Section("保存逐组修改") {
                    TextField("修改原因", text: $reason)
                        .focused($focusedInput, equals: .movementReason)
                        .accessibilityIdentifier("整周教练-逐组修改原因")
                    Button("保存逐组新版本") { saveMovements(movements, reason); dismiss() }
                        .disabled(!canEdit || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || movements == day.movements)
                }
            }
            if let cardio = day.cardio {
                Section("跳绳 · 独立有氧") {
                    Text(cardio.summary)
                    Text(cardio.notes)
                    Text("预计总时长 \(cardio.elapsedSeconds.map { "\($0 / 60) 分钟" } ?? "待核")；实际跳绳由当天跳绳菜单记录。")
                }
            }
            if let zone2 = day.zone2 {
                Section("Zone 2 · 独立有氧") {
                    Text("\(zone2.mode) · 目标 \(zone2.durationSeconds / 60) 分钟")
                    Text(zone2.guidance)
                    Text(zone2.exerciseID == nil ? "记录动作身份待确认；当前不可写正式安排。" : "已关联记录动作；正式保存后在当天有氧页面记录实际时长。")
                }
                let compatible = catalog.filter { !$0.archived && $0.unit == .second &&
                    (CardioWorkoutPresentation.symbol(name: $0.name, muscle: $0.muscle,
                        equipment: $0.equipment, unit: $0.unit) != nil) }
                if !compatible.isEmpty {
                    Section("确认 Zone 2 记录器械") {
                        Picker("可记录动作", selection: $zone2ExerciseID) {
                            Text("请选择").tag(UUID?.none)
                            ForEach(compatible) { item in
                                Text("\(item.name) · \(item.equipment)").tag(Optional(item.id))
                            }
                        }
                        TextField("选择或变更原因", text: $reason)
                            .focused($focusedInput, equals: .zone2Reason)
                        Button("保存器械身份并重验整周") {
                            if let zone2ExerciseID { saveZone2(zone2ExerciseID, reason); dismiss() }
                        }.disabled(!canEdit || zone2ExerciseID == nil || zone2ExerciseID == day.zone2?.exerciseID ||
                            reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Section("器械信息缺口") {
                        Text("动作库中没有可识别、按秒记录的单车或椭圆机。请先核对器械名称、类型与单位，再重新生成整周草案。")
                            .foregroundStyle(.red)
                        NavigationLink("打开动作库核对器械") { PlanView().legacyTrainingScreen() }
                    }
                }
            }
            if day.kind == .preserved {
                Section("核对具体保留安排") {
                    Text("仅为原日程/实际的本周目标补充本人注记；原记录、历史快照和其他天处方不改。未知任务仍会阻断确认。")
                        .font(.footnote)
                    Picker("原安排身份", selection: $preservedID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(day.existing) { item in
                            Text("\(item.title) · \(item.source) · \(item.id.uuidString.prefix(8))")
                                .tag(Optional(item.id))
                        }
                    }
                    Picker("本人核对类型", selection: $preservedKind) {
                        Text("力量").tag(CoachWeekDayKind.strength)
                        Text("有氧").tag(CoachWeekDayKind.cardio)
                        Text("休息").tag(CoachWeekDayKind.rest)
                    }
                    .onChange(of: preservedKind) { _, newValue in
                        preservedFocus = newValue == .cardio ? "跳绳" : (newValue == .rest ? "休息" : "胸")
                    }
                    if preservedKind != .rest {
                        Picker("本人核对任务", selection: $preservedFocus) {
                            ForEach(preservedKind == .strength ? ["胸", "背", "腿", "肩"] : ["跳绳", "Zone 2"], id: \.self) { value in
                                Text(value).tag(value)
                            }
                        }
                    }
                    TextField("核对原因", text: $reason)
                        .focused($focusedInput, equals: .retainedReason)
                    Button("保存保留安排注记并重验整周") {
                        if let preservedID {
                            savePreserved(preservedID, preservedKind, preservedKind == .rest ? "" : preservedFocus, reason)
                            dismiss()
                        }
                    }.disabled(!canEdit || preservedID == nil || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            ForEach($movements) { $movement in
                Section {
                    Text("任务：\(movement.roles.joined(separator: "、")) · 来源：\(movement.roleSource)")
                    Picker("正式任务强度", selection: Binding(
                        get: { movement.exercise.plannedSets.first?.prescription?.label ?? "中等辅助" },
                        set: { role in
                            for index in movement.exercise.plannedSets.indices {
                                movement.exercise.plannedSets[index].prescription?.label = role
                            }
                        })) {
                        ForEach(allowedLoadRoles(for: movement), id: \.self) { role in Text(role).tag(role) }
                    }
                    Text("当前规则角色：\(movement.loadRole ?? "待重验")；保存后按动作身份、组数和完整时间重新验证。")
                        .font(.caption)
                    Text("编排理由：\(movement.reason)")
                    Text("器械：\(movement.exercise.equipment) · 单位：\(movement.exercise.volumeUnit.symbol)")
                    Text("负重依据／校准：\(movement.exercise.loadGuidance)")
                    if !movement.exercise.notes.isEmpty { Text("热身及停止条件：\(movement.exercise.notes)") }
                    if movement.specialPrescriptionReviewed != nil {
                        Toggle("已单独核对本特殊动作的逐组次数与负荷", isOn: Binding(
                            get: { movement.specialPrescriptionReviewed == true },
                            set: { movement.specialPrescriptionReviewed = $0 }))
                        Text("根据本人的可比记录和当天情况逐组设置；未知负荷需现场校准。")
                            .font(.caption)
                    }
                    ForEach($movement.exercise.plannedSets) { $set in
                        VStack(alignment: .leading) {
                            Text("\(set.prescription?.label ?? "组别待核")")
                                .font(.subheadline.weight(.semibold))
                            HStack {
                                TextField("重量（\(movement.exercise.volumeUnit.symbol)）", value: $set.weight, format: .number)
                                    .keyboardType(.decimalPad)
                                    .focused($focusedInput, equals: .weight(set.id))
                                Stepper("\(set.reps) 次", value: Binding(get: { set.reps }, set: { value in
                                    set.reps = value
                                    set.prescription?.repsLower = value
                                    if let upper = set.prescription?.repsUpper, upper < value { set.prescription?.repsUpper = value }
                                }), in: 1...100)
                            }
                            Text(set.prescription?.effortCue ?? "努力程度待核").font(.footnote)
                            if let target = set.prescription {
                                Text("目标次数 \(target.repsLower)–\(target.repsUpper) · RIR \(target.rirLower.map(String.init) ?? "?")–\(target.rirUpper.map(String.init) ?? "?") · 休息 \(target.restLowerSeconds)–\(target.restUpperSeconds) 秒")
                                    .font(.caption)
                            }
                            if set.prescription != nil {
                                Stepper("目标余力下限 \(set.prescription?.rirLower ?? 0)", value: Binding(
                                    get: { set.prescription?.rirLower ?? 0 }, set: { set.prescription?.rirLower = $0 }), in: 0...10)
                                Stepper("目标余力上限 \(set.prescription?.rirUpper ?? 0)", value: Binding(
                                    get: { set.prescription?.rirUpper ?? 0 }, set: { set.prescription?.rirUpper = $0 }), in: 0...10)
                                Stepper("休息下限 \(set.prescription?.restLowerSeconds ?? 0)秒", value: Binding(
                                    get: { set.prescription?.restLowerSeconds ?? 0 }, set: { set.prescription?.restLowerSeconds = $0 }), in: 0...600, step: 15)
                                Stepper("休息上限 \(set.prescription?.restUpperSeconds ?? 0)秒", value: Binding(
                                    get: { set.prescription?.restUpperSeconds ?? 0 }, set: { set.prescription?.restUpperSeconds = $0 }), in: 0...600, step: 15)
                            }
                        }
                    }
                    .onDelete { offsets in movement.exercise.plannedSets.remove(atOffsets: offsets) }
                    Button("添加工作组") {
                        var next = movement.exercise.plannedSets.last ?? WorkoutSetPlan(
                            weight: 0, reps: 8, weightSide: .unknown, repsSide: .unknown,
                            actualDefaultPolicy: .blank,
                            prescription: WorkoutSetPrescription(label: "中等辅助", repsLower: 8, repsUpper: 12,
                                rirLower: 2, rirUpper: 3, restLowerSeconds: 90, restUpperSeconds: 120,
                                effortCue: "热身校准；疼痛或动作失稳时停止"))
                        next.id = UUID()
                        movement.exercise.plannedSets.append(next)
                    }
                    Text("向左滑动逐组删除；热身组不计工作组。保存后会重算主项／一般组数和整课时间。")
                        .font(.caption)
                    ForEach(movement.evidence, id: \.self) { Text("历史／来源：" + $0).font(.footnote) }
                    ForEach(movement.unknowns, id: \.self) { Text("待校准：" + $0).font(.footnote) }
                } header: {
                    ExerciseExplanationButton(exerciseID: movement.exercise.catalogExerciseID,
                        name: movement.exercise.displayName, equipment: movement.exercise.equipment, showsName: true,
                        lookupName: movement.exercise.catalogName)
                }
            }
            .onMove { movements.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { movements.remove(atOffsets: $0) }
            if day.kind == .strength {
                Section("添加或替换动作") {
                    Menu("添加动作") {
                        ForEach(catalog.filter { !$0.archived && !$0.roles.isEmpty && !$0.equipment.isEmpty && !CoachWeekService.requiresAnkleAttachment(name: $0.name, equipment: $0.equipment) && !movements.map(\.id).contains($0.id) }) { item in
                            Button(item.name) { addMovement(item) }
                        }
                    }
                    Text("删除原动作再添加候选可替换；顺序可拖动。新增动作的负重与实际余力均未知。")
                        .font(.footnote)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(day.localDay)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedInput = nil }
                    .accessibilityIdentifier("整周教练-编辑收起键盘")
            }
        }
    }

    private func addMovement(_ item: CoachWeekCatalogItem) {
        let technical = item.roles.contains("技术")
        let sets = (0..<3).map { _ in
            WorkoutSetPlan(weight: 0, reps: 8, weightSide: .unknown, repsSide: .unknown, actualDefaultPolicy: .blank,
                prescription: WorkoutSetPrescription(label: technical ? "技术/速度" : "中等辅助", repsLower: 8, repsUpper: 12,
                    rirLower: technical ? nil : 2, rirUpper: technical ? nil : 3, restLowerSeconds: 90, restUpperSeconds: 120,
                    effortCue: "热身校准；出现不适或动作失稳时停止"))
        }
        let exercise = ConfirmedDailyPlanExercise(catalogExerciseID: item.id, catalogName: item.name,
            equipment: item.equipment, volumeUnit: item.unit, displayName: item.name,
            loadGuidance: "未有可比负重，需本人核实并现场校准。", notes: "手动添加", plannedSets: sets,
            planPattern: technical ? .fixed : nil)
        movements.append(CoachWeekMovement(exercise: exercise, roles: item.roles, roleSource: item.roleSource,
            reason: "本人手动添加", evidence: [], unknowns: ["实际余力、器械和可比负重待核。"], unilateral: false,
            loadRole: technical ? "技术/速度" : "中等辅助"))
    }

    private func allowedLoadRoles(for movement: CoachWeekMovement) -> [String] {
        movement.loadRole == "技术/速度" ? ["技术/速度"] : ["重主项", "中等辅助", "轻负荷正式任务"]
    }
}
