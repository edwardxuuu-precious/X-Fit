import SwiftData
import SwiftUI

struct FatLossDailyEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var logs: [ProgramDailyLog]
    let program: FatLossProgram
    let date: Date
    @State private var steps = ""
    @State private var sleep = ""
    @State private var bloating = -1
    @State private var noWorkout = false
    @State private var notes = ""
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Section(header: SprintSectionHeading(title: FatLossCalendar.label(date), icon: "figure.walk")) {
                HStack { Text("步数"); TextField("未记录", text: $steps).frame(minHeight: 44).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("睡眠小时"); TextField("未记录", text: $sleep).frame(minHeight: 44).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("腹胀程度", selection: $bloating) {
                    Text("未记录").tag(-1); Text("无").tag(0); Text("轻微").tag(1); Text("明显").tag(2); Text("严重").tag(3)
                }
                Toggle("今天明确没有训练", isOn: $noWorkout)
                TextField("饮食反应、诱因或其他备注", text: $notes, axis: .vertical).frame(minHeight: 44)
            }
            Section {
                Text("留空表示未知。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }.scrollContentBackground(.hidden).sprintPage().fatLossCalendar().fatLossInput().navigationTitle("日常记录").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.semibold).frame(minHeight: 44)
                        .disabled(FatLossCalendar.day(date) > FatLossCalendar.day(.now))
                        .accessibilityIdentifier("保存减脂日记录")
                }
            }
            .onAppear {
                if let log = logs.first(where: { $0.programID == program.id && FatLossCalendar.sameDay($0.date, date) }) {
                    steps = log.steps.map(String.init) ?? ""; sleep = log.sleepHours.map { String($0) } ?? ""
                    bloating = log.bloatingScore ?? -1; noWorkout = log.explicitlyNoWorkout; notes = log.notes
                }
            }.fatLossError($errorMessage)
    }
    private func save() {
        guard steps.isEmpty || (Int(steps).map { $0 >= 0 } ?? false),
              sleep.isEmpty || (Double(sleep).map { $0.isFinite && $0 >= 0 && $0 <= 24 } ?? false) else {
            errorMessage = "步数请填写非负整数，睡眠填写 0–24 小时；也可留空。"; return
        }
        let log = ProgramDailyLog(programID: program.id, date: date)
        log.steps = Int(steps); log.sleepHours = Double(sleep); log.bloatingScore = bloating < 0 ? nil : bloating
        log.explicitlyNoWorkout = noWorkout; log.notes = notes
        do { try FatLossService.saveDailyLog(log, in: context); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct FatLossTargetsView: View {
    @Query(sort: \ProgramTargetRevision.effectiveDate, order: .reverse) private var targets: [ProgramTargetRevision]
    @Query(sort: \ProgramHealthRecord.createdAt, order: .reverse) private var records: [ProgramHealthRecord]
    let program: FatLossProgram
    var body: some View {
        List {
            Section {
                NavigationLink(destination: FatLossTargetEditor(program: program)) {
                    Label("新增目标版本", systemImage: "scope")
                }
                    .accessibilityIdentifier("新增减脂目标版本")
                NavigationLink(destination: FatLossHealthEditor(program: program)) {
                    Label("补充健康记录", systemImage: "heart.text.clipboard")
                }
            }
            Section(header: SprintSectionHeading(title: "目标历史", icon: "clock.arrow.circlepath")) {
                ForEach(targets.filter { $0.programID == program.id }) { target in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(FatLossCalendar.label(target.effectiveDate)) 起").font(.headline)
                        Text(target.reason).font(.subheadline)
                        Text(target.isNutritionConfirmed ? "营养目标已确认" : "营养目标待确认")
                            .font(.caption).foregroundStyle(target.isNutritionConfirmed ? AppTheme.ink : AppTheme.orange)
                        Text("体重 \(target.targetWeightKg.map { "\($0) kg" } ?? "未设置") · 步数 \(target.steps.map(String.init) ?? "未设置")")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        if target.isNutritionConfirmed {
                            Text("热量 \(target.calories.map { "\($0) kcal" } ?? "未设置") · 蛋白质 \(target.proteinGrams.map { "\($0) g" } ?? "未设置")")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        if !target.sourceNote.isEmpty { Text(target.sourceNote).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                    }.padding(.vertical, 5)
                }
            }
            Section(header: SprintSectionHeading(title: "健康记录", icon: "heart.text.clipboard")) {
                ForEach(records.filter { $0.programID == program.id }) { record in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(record.metric).font(.headline)
                        HStack {
                            Text(record.value.map { String($0) } ?? "数值未知")
                            Text(record.unit ?? "单位未知")
                        }.font(.subheadline)
                        Text(record.measuredAt.map(FatLossCalendar.label) ?? "检测日期未知")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        if !record.notes.isEmpty { Text(record.notes).font(.subheadline) }
                        Text(record.source).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }.padding(.vertical, 5)
                }
            }
        }.scrollContentBackground(.hidden).sprintPage().fatLossCalendar().fatLossInput().navigationTitle("目标与健康档案").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}

private struct FatLossTargetEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let program: FatLossProgram
    @State private var effectiveDate = Date.now
    @State private var reason = ""
    @State private var source = ""
    @State private var weight = ""
    @State private var steps = ""
    @State private var nutritionConfirmed = false
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Section(header: SprintSectionHeading(title: "新版本", icon: "scope")) {
                DatePicker("生效日期", selection: $effectiveDate, in: program.startDate...program.endDate, displayedComponents: .date)
                TextField("调整原因（必填）", text: $reason, axis: .vertical).frame(minHeight: 44)
                field("期望体重 kg", $weight, decimal: true)
                field("每日步数", $steps)
                Text("留空表示待确定，已有版本保留。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Section(header: SprintSectionHeading(title: "营养目标", icon: "fork.knife")) {
                Toggle("已取得并确认适用的营养建议", isOn: $nutritionConfirmed)
                TextField("医生 / 营养师建议来源与日期", text: $source, axis: .vertical).frame(minHeight: 44)
                if nutritionConfirmed {
                    field("热量 kcal", $calories)
                    field("蛋白质 g", $protein)
                    field("碳水 g", $carbs)
                    field("脂肪 g", $fat)
                } else { Text("营养目标待确认") }
            }
        }.scrollContentBackground(.hidden).sprintPage().fatLossCalendar().fatLossInput().navigationTitle("调整目标").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.semibold).frame(minHeight: 44)
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("保存减脂目标版本")
                }
            }
            .onAppear {
                effectiveDate = min(max(FatLossCalendar.day(.now), program.startDate), program.endDate)
                do {
                    if let current = try FatLossService.target(program: program, on: effectiveDate, in: context) {
                        weight = current.targetWeightKg.map { String($0) } ?? ""
                        steps = current.steps.map(String.init) ?? ""
                        nutritionConfirmed = current.isNutritionConfirmed
                        source = current.sourceNote
                        calories = current.calories.map(String.init) ?? ""
                        protein = current.proteinGrams.map(String.init) ?? ""
                        carbs = current.carbsGrams.map(String.init) ?? ""
                        fat = current.fatGrams.map(String.init) ?? ""
                    }
                } catch { errorMessage = error.localizedDescription }
            }
            .fatLossError($errorMessage)
    }
    private func field(_ name: String, _ value: Binding<String>, decimal: Bool = false) -> some View {
        HStack { Text(name); TextField("未确定", text: value).frame(minHeight: 44).multilineTextAlignment(.trailing).keyboardType(decimal ? .decimalPad : .numberPad) }
    }
    private func save() {
        let integers = [steps] + (nutritionConfirmed ? [calories, protein, carbs, fat] : [])
        guard integers.allSatisfy({ $0.isEmpty || (Int($0).map { $0 >= 0 } ?? false) }),
              weight.isEmpty || (Double(weight).map { $0.isFinite && $0 > 0 } ?? false) else {
            errorMessage = "请检查数字；未知项目可留空。"; return
        }
        guard !nutritionConfirmed || !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请记录营养建议的来源与日期。"; return
        }
        let target = ProgramTargetRevision(programID: program.id, effectiveDate: effectiveDate, reason: reason)
        target.targetWeightKg = Double(weight); target.steps = Int(steps); target.sourceNote = source
        target.isNutritionConfirmed = nutritionConfirmed
        if nutritionConfirmed {
            target.calories = Int(calories); target.proteinGrams = Int(protein); target.carbsGrams = Int(carbs); target.fatGrams = Int(fat)
        }
        do { try FatLossService.saveTarget(target, in: context); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct FatLossHealthEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let program: FatLossProgram
    @State private var metric = "尿酸"
    @State private var value = ""
    @State private var unit = ""
    @State private var dateKnown = false
    @State private var measuredDate = Date.now
    @State private var source = "本人记录"
    @State private var notes = ""
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Section(header: SprintSectionHeading(title: "记录内容", icon: "heart.text.clipboard")) {
                Picker("项目", selection: $metric) {
                    ForEach(["尿酸", "肌酐", "eGFR", "尿蛋白", "医生饮食建议", "用药自述", "其他"], id: \.self) { Text($0).tag($0) }
                }
                TextField("数值（未知可留空）", text: $value).keyboardType(.decimalPad).frame(minHeight: 44)
                TextField("单位（按报告填写）", text: $unit).frame(minHeight: 44)
                Toggle("知道检测 / 建议日期", isOn: $dateKnown)
                if dateKnown { DatePicker("日期", selection: $measuredDate, in: ...Date.now, displayedComponents: .date) }
                TextField("来源", text: $source).frame(minHeight: 44)
                TextField("报告、医生建议或用药自述", text: $notes, axis: .vertical).frame(minHeight: 44)
            }
            Section {
                Text("未知可留空；用药按本人实际情况记录。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)

            }
        }.scrollContentBackground(.hidden).sprintPage().fatLossCalendar().fatLossInput().navigationTitle("补充健康记录").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveHealth).fontWeight(.semibold).frame(minHeight: 44)
                        .accessibilityIdentifier("保存减脂健康记录")
                }
            }
            .fatLossError($errorMessage)
    }
    private func saveHealth() {
        guard value.isEmpty || (Double(value).map { $0.isFinite && $0 >= 0 } ?? false) else {
            errorMessage = "请检查数值，未知可留空。"; return
        }
        let record = ProgramHealthRecord(programID: program.id, metric: metric)
        record.value = Double(value); record.unit = unit.isEmpty ? nil : unit
        record.measuredAt = dateKnown ? measuredDate : nil; record.notes = notes; record.source = source
        do { try FatLossService.saveHealthRecord(record, in: context); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }

}

struct FatLossReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \ProgramWeeklyReview.createdAt, order: .reverse) private var reviews: [ProgramWeeklyReview]
    @Query private var meals: [MealEntry]
    let program: FatLossProgram
    @State private var endDate = Date.now
    @State private var notes = ""
    @State private var nextAction = ""
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var timeline: [FatLossDaySummary] = []
    @State private var hasInitializedDate = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    SprintPageHeader(title: "周复盘", icon: "arrow.triangle.2.circlepath")
                    DatePicker("截至日期", selection: $endDate, in: program.startDate...program.endDate, displayedComponents: .date)
                        .font(.subheadline).tint(AppTheme.ink)
                }
                weekSummary
                VStack(alignment: .leading, spacing: 16) {
                    SprintSectionHeading(title: "本周感受", icon: "square.and.pencil")
                    TextField("本周体重、饥饿、腹胀与训练表现", text: $notes, axis: .vertical)
                        .lineLimit(3...6).padding(16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    SprintSectionHeading(title: "下一步", icon: "arrow.up.right")
                    TextField("下一步（如维持观察、换菜、复查）", text: $nextAction, axis: .vertical)
                        .lineLimit(2...5).padding(16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    if saved {
                        Text("已保存。后续补记不会修改这个快照。")
                            .font(.caption).foregroundStyle(AppTheme.ink)
                    }
                    DisclosureGroup("参考记录建议") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(suggestion).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                                Button("填入草稿") {
                                    if !nextAction.contains(suggestion) {
                                        nextAction += (nextAction.isEmpty ? "" : "\n") + suggestion
                                    }
                                }.font(.subheadline.bold()).frame(minHeight: 44)
                            }.padding(.vertical, 8)
                        }
                    }
                    Text("保存形成复盘快照；调整目标和换菜仍需分别确认。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                VStack(spacing: 0) {
                    NavigationLink(destination: FatLossTargetEditor(program: program)) {
                        FatLossNavigationRow(title: "审核并新增目标版本", icon: "scope")
                    }
                    Divider()
                    NavigationLink(destination: FatLossMealsView(program: program,
                        initialDate: min(FatLossCalendar.adding(1, to: endDate), FatLossCalendar.adding(-1, to: program.endDate)))) {
                        FatLossNavigationRow(title: "查看下一天餐单并换菜", icon: "fork.knife")
                    }
                }.padding(.horizontal, 16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                DisclosureGroup("历史复盘 · \(reviews.filter { $0.programID == program.id }.count) 份") {
                    ForEach(reviews.filter { $0.programID == program.id }) { review in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(FatLossCalendar.label(review.weekStart)) — \(FatLossCalendar.label(review.weekEnd))").font(.headline)
                            if review.previousReviewID != nil { Text("补充版本 · 原版保留").font(.caption).foregroundStyle(AppTheme.ink) }
                            Text(review.notes)
                            if !review.nextAction.isEmpty { Text("下一步：\(review.nextAction)").font(.subheadline) }
                            if let days = try? JSONDecoder().decode([FatLossDaySummary].self, from: Data(review.snapshotJSON.utf8)) {
                                Text("实测体重 \(days.filter { $0.weightKg != nil }.count) 天 · 餐食 \(days.reduce(0) { $0 + $1.loggedMeals }) 次 · 训练 \(days.reduce(0) { $0 + $1.completedWorkouts }) 次")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            Text("保存于 \(review.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                        }.padding(.vertical, 12)
                    }
                }.accessibilityIdentifier("复盘-历史")
            }.padding(20)
        }.sprintPage().fatLossCalendar().fatLossInput().navigationTitle("每周复盘").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: saveReview) { Text("保存本周复盘").neonButtonStyle() }
                    .disabled(FatLossCalendar.day(endDate) > FatLossCalendar.day(.now))
                    .accessibilityIdentifier("复盘-底部保存")
                    .padding(.horizontal, 20).padding(.vertical, 12).background(AppTheme.background)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveReview).fontWeight(.semibold).frame(minHeight: 44)
                        .disabled(FatLossCalendar.day(endDate) > FatLossCalendar.day(.now))
                        .accessibilityIdentifier("保存减脂周复盘")
                }
            }
            .onAppear {
                if !hasInitializedDate {
                    endDate = min(max(FatLossCalendar.day(.now), program.startDate), program.endDate)
                    hasInitializedDate = true
                }
                refreshTimeline()
            }
            .fatLossError($errorMessage)
    }
    private var weekDays: [FatLossDaySummary] {
        let start = FatLossCalendar.adding(-6, to: endDate)
        return timeline.filter { $0.date >= start && $0.date <= FatLossCalendar.day(endDate) }
    }
    private var previousDays: [FatLossDaySummary] {
        let start = FatLossCalendar.adding(-13, to: endDate)
        let end = FatLossCalendar.adding(-7, to: endDate)
        return timeline.filter { $0.date >= start && $0.date <= end }
    }
    private var feedbackMeals: [MealEntry] {
        let start = FatLossCalendar.adding(-6, to: endDate)
        return meals.filter { $0.isActiveMeal && $0.programID == program.id
            && FatLossCalendar.day($0.date) >= start && FatLossCalendar.day($0.date) <= FatLossCalendar.day(endDate) }
    }
    private var weekSummary: some View {
        let weights = weekDays.compactMap(\.weightKg)
        let priorWeights = previousDays.compactMap(\.weightKg)
        let mean = weights.count >= 3 ? weights.reduce(0, +) / Double(weights.count) : nil
        let priorMean = priorWeights.count >= 3 ? priorWeights.reduce(0, +) / Double(priorWeights.count) : nil
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("近 7 天平均体重").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                Text(mean.map { String(format: "%.1f", $0) } ?? "数据不足")
                    .font(.system(size: mean == nil ? 30 : 58, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(AppTheme.ink).accessibilityIdentifier("复盘-均重")
                Text("\(mean == nil ? "" : "kg · ")称重 \(weights.count)/7 天")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                if let mean, let priorMean {
                    Text(String(format: "较前 7 天 %+.1f kg", mean - priorMean))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                } else {
                    Text("两周各满 3 个称重日，再比较变化。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                reviewMetric("训练完成", "\(weekDays.reduce(0) { $0 + $1.completedWorkouts }) 次", "计划 \(weekDays.reduce(0) { $0 + $1.plannedWorkouts }) 次")
                reviewMetric("实吃记录", "\(weekDays.reduce(0) { $0 + $1.loggedMeals }) 餐", "仅统计实际记录")
            }
            VStack(spacing: 14) {
                summaryLine("腰围", weekDays.compactMap(\.waistCm).last.map { "\($0) cm" } ?? "未记录")
                summaryLine("餐后腹胀", feedbackMeals.contains(where: { $0.bloatingScore != nil }) ? "\(feedbackMeals.filter { ($0.bloatingScore ?? 0) > 0 }.count) / \(feedbackMeals.filter { $0.bloatingScore != nil }.count) 餐" : "未评价")
                summaryLine("日常腹胀", "已记录 \(weekDays.filter { ($0.bloatingScore ?? 0) > 0 }.count) 天有腹胀")
                Text("餐后比例仅含已评价餐食").font(.caption).foregroundStyle(AppTheme.secondaryText).frame(maxWidth: .infinity, alignment: .leading)
                DisclosureGroup("力量与训练详情") {
                    NavigationLink("力量与训练表现", destination: StatsView()).frame(minHeight: 44)
                    NavigationLink("逐次训练历史", destination: HistoryView()).frame(minHeight: 44)
                }
            }
        }
    }
    private func reviewMetric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.title2.bold()).foregroundStyle(AppTheme.ink)
            Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func summaryLine(_ title: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: 16)
                Text(value).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(AppTheme.secondaryText)
                Text(value).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.subheadline)
    }
    private func saveReview() {
        do {
            _ = try FatLossService.saveReview(program: program, endingOn: endDate, notes: notes, nextAction: nextAction, in: context)
            notes = ""; nextAction = ""; saved = true
        } catch { errorMessage = error.localizedDescription }
    }

    private var suggestions: [String] {
        var result: [String] = []
        if endDate > FatLossCalendar.day(.now) { return ["周期开始后记录晨起体重、实际餐食与训练，先建立基线。"] }
        let weightDays = weekDays.filter { $0.weightKg != nil }.count
        if weightDays < 3 {
            result.append("本周只有 \(weightDays) 天实测体重。接下来先按一致的晨起条件记录，不用单日变化调整饮食。")
        } else {
            result.append("继续记录体重与腰围，结合训练表现复盘。是否调整目标由你确认，不自动降低热量。")
        }
        if feedbackMeals.contains(where: { ($0.bloatingScore ?? 0) > 0 }) || weekDays.contains(where: { ($0.bloatingScore ?? 0) > 0 }) {
            result.append("打开出现腹胀的餐食，核对份量、做法和备注；选择需要替换的未来餐次，每次保存换菜原因。")
        }
        if weekDays.contains(where: { $0.loggedMeals + $0.skippedMeals < $0.plannedMeals }) {
            result.append("先补充漏记餐次或明确未吃；餐单不等于实吃，记录不完整时不据此判断热量缺口。")
        }
        return result
    }
    private func refreshTimeline() {
        do { timeline = try FatLossService.timeline(program: program, in: context) }
        catch { errorMessage = error.localizedDescription }
    }
}
