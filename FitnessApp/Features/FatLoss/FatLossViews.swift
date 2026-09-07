import Charts
import SwiftData
import SwiftUI

struct FatLossHomeSummary: View {
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query private var meals: [PlannedMeal]
    @Query private var targetRevisions: [ProgramTargetRevision]
    private var program: FatLossProgram? { programs.first { $0.statusRaw == "active" } }
    var body: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: FatLossDashboardView()) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(program == nil ? "开启 13 周减脂" : "我的减脂周期", systemImage: "leaf.fill")
                            .font(.headline).foregroundStyle(AppTheme.accent)
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(AppTheme.secondaryText)
                    }
                    if let program {
                        let values = BodyMeasurementService.dailyRepresentativeWeights(from: measurements)
                            .filter { program.contains($0.date) }
                        HStack {
                            FatLossMetric(value: values.last.map { String(format: "%.1f", $0.weightKg) } ?? "—", label: "最近实测 kg")
                            FatLossMetric(value: targetWeight(program).map { String(format: "%.1f", $0) } ?? "—", label: "期望目标 kg")
                            FatLossMetric(value: Date.now < program.startDate ? "待开始" : (FatLossCalendar.day(.now) > program.endDate ? "已结束" : "第 \(program.weekNumber(on: .now)) 周"), label: "共 13 周")
                        }
                    } else {
                        Text("家常餐单、力量训练与每一天的变化")
                            .font(.subheadline).foregroundStyle(.white)
                        Text("9 月 6 日 — 12 月 6 日 · 先查看完整计划")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }.cardSurface(padding: 18, cornerRadius: 22)
            }.buttonStyle(.plain).accessibilityIdentifier("首页减脂周期")
            if let program {
                NavigationLink(destination: FatLossMealsView(program: program)) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "fork.knife").foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("今日餐单").font(.headline).foregroundStyle(.white)
                            let today = meals.filter { $0.programID == program.id && $0.isCurrent && FatLossCalendar.sameDay($0.date, .now) }
                            Text(today.isEmpty ? "查看餐单与明日备餐" : today.sorted { $0.mealTypeRaw < $1.mealTypeRaw }.map(\.title).joined(separator: " · "))
                                .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(AppTheme.secondaryText)
                    }.cardSurface()
                }.buttonStyle(.plain).accessibilityIdentifier("首页今日餐单")
            }
        }
    }
    private func targetWeight(_ program: FatLossProgram) -> Double? {
        let applicable = targetRevisions.filter {
            $0.programID == program.id && $0.effectiveDate <= max(FatLossCalendar.day(.now), program.startDate)
        }.sorted {
            $0.effectiveDate == $1.effectiveDate ? $0.createdAt > $1.createdAt : $0.effectiveDate > $1.effectiveDate
        }
        if let revision = applicable.first { return revision.targetWeightKg }
        return program.targetWeightKg
    }
}

struct FatLossQuickRecordLinks: View {
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    var body: some View {
        if let program = programs.first(where: { $0.statusRaw == "active" }) {
            HStack(spacing: 12) {
                NavigationLink(destination: FatLossDailyEditor(program: program, date: min(max(FatLossCalendar.day(.now), program.startDate), program.endDate))) {
                    Label("步数 · 睡眠", systemImage: "moon.zzz.fill").font(.caption.bold())
                        .frame(maxWidth: .infinity).cardSurface()
                }
                NavigationLink(destination: ToolsView()) {
                    Label("跳绳 · 饮水", systemImage: "figure.jumprope").font(.caption.bold())
                        .frame(maxWidth: .infinity).cardSurface()
                }
            }.foregroundStyle(AppTheme.accent).buttonStyle(.plain)
        }
    }
}

struct FatLossDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @State private var errorMessage: String?
    @State private var exportURL: URL?
    private var program: FatLossProgram? { programs.first { $0.statusRaw == "active" } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let program {
                    summary(program)
                    NavigationLink(destination: FatLossMealsView(program: program)) {
                        route("餐单与备餐", "14 天轮换 · 明日采购 · 实吃反馈", icon: "fork.knife")
                    }.accessibilityIdentifier("餐单与备餐")
                    NavigationLink(destination: FatLossTrainingView(program: program)) {
                        route("全身训练计划", "A / B / C · 先预览，再导入", icon: "dumbbell.fill")
                    }
                    NavigationLink(destination: FatLossTimelineView(program: program)) {
                        route("完整周期记录", "每一天的计划、实际与漏记", icon: "calendar")
                    }
                    NavigationLink(destination: FatLossReviewView(program: program)) {
                        route("每周复盘", "保留当时快照和调整原因", icon: "arrow.triangle.2.circlepath")
                    }.accessibilityIdentifier("减脂每周复盘")
                    NavigationLink(destination: FatLossTargetsView(program: program)) {
                        route("目标与健康档案", "营养待确认 · 检测与目标历史", icon: "heart.text.clipboard")
                    }.accessibilityIdentifier("目标与健康档案")
                    NavigationLink(destination: HistoryView()) {
                        route("训练历史", "继续查看已有训练记录", icon: "clock.arrow.circlepath")
                    }
                    HStack {
                        Button("生成周期 CSV") {
                            do { exportURL = try FatLossService.exportCSV(program: program, in: context) }
                            catch { errorMessage = error.localizedDescription }
                        }.buttonStyle(.bordered)
                        if let exportURL { ShareLink(item: exportURL) { Label("分享", systemImage: "square.and.arrow.up") } }
                    }
                } else {
                    FatLossIntroductionView {
                        _ = try FatLossService.createProgram(in: context)
                    }
                }
            }.padding(20).buttonStyle(.plain)
        }
        .screenBackground().fatLossCalendar().navigationTitle("减脂周期").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .fatLossError($errorMessage)
    }
    private func route(_ title: String, _ detail: String, icon: String) -> some View {
        FatLossNavigationRow(title: title, icon: icon)
    }
    private func summary(_ program: FatLossProgram) -> some View {
        let values = BodyMeasurementService.dailyRepresentativeWeights(from: measurements).filter { program.contains($0.date) }
        let average = FatLossService.average(endingOn: .now, values: values)
        return VStack(alignment: .leading, spacing: 15) {
            Text("\(FatLossCalendar.label(program.startDate)) — \(FatLossCalendar.label(program.endDate))")
                .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.accent)
            Text(phaseFocus(program)).font(.subheadline.bold()).foregroundStyle(.white)
            HStack {
                FatLossMetric(value: String(format: "%.1f", program.reportedStartWeightKg), label: "自述起点 kg")
                FatLossMetric(value: values.first.map { String(format: "%.1f", $0.weightKg) } ?? "—", label: "首次实测 kg")
                FatLossMetric(value: average.value.map { String(format: "%.1f", $0) } ?? "—", label: "近 7 天均重 · \(average.recordedDays)/7")
            }
            if !values.isEmpty {
                Chart(values) { value in
                    LineMark(x: .value("日期", value.date), y: .value("体重", value.weightKg))
                        .foregroundStyle(AppTheme.accent)
                    PointMark(x: .value("日期", value.date), y: .value("体重", value.weightKg))
                        .foregroundStyle(AppTheme.accent)
                }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 150)
            }
            NavigationLink(destination: BodyMeasurementsView()) {
                Label("记录体重与腰围", systemImage: "scalemass.fill").font(.subheadline.bold())
            }.foregroundStyle(AppTheme.accent)
        }.cardSurface(padding: 18, cornerRadius: 22)
    }
    private func phaseFocus(_ program: FatLossProgram) -> String {
        switch program.weekNumber(on: .now) {
        case 1...2: return "第 1–2 周 · 建立体重、腹胀与训练基线"
        case 3...6: return "第 3–6 周 · 参考连续两周记录，再确认调整"
        case 7...10: return "第 7–10 周 · 按反馈换菜，关注训练恢复"
        default: return "第 11–13 周 · 稳定执行，准备收尾复盘"
        }
    }
}

struct FatLossTimelineView: View {
    @Environment(\.modelContext) private var context
    let program: FatLossProgram
    @State private var days: [FatLossDaySummary] = []
    @State private var errorMessage: String?
    @State private var selectedDate: Date?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 3)], spacing: 8) {
                    ForEach(days) { day in
                        Button { selectedDate = day.date } label: {
                            VStack(spacing: 5) {
                                Text(day.date, format: .dateTime.month().day()).font(.caption2.monospacedDigit())
                                Circle().fill(day.hasRecords ? AppTheme.accent : AppTheme.secondaryText.opacity(0.2)).frame(width: 6, height: 6)
                            }.frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 4)
                                .background(FatLossCalendar.sameDay(day.date, selectedDate ?? .distantPast) ? AppTheme.accent.opacity(0.18) : AppTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                        }.foregroundStyle(.white).accessibilityLabel("\(FatLossCalendar.label(day.date)) \(day.status(relativeTo: .now))")
                    }
                }
                ForEach(days.filter { selectedDate == nil || FatLossCalendar.sameDay($0.date, selectedDate!) }) { day in
                    NavigationLink(destination: FatLossDayDetailView(program: program, day: day)) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(FatLossCalendar.label(day.date)).font(.subheadline.bold())
                                Spacer()
                                Text(day.status(relativeTo: .now)).font(.caption).foregroundStyle(day.hasRecords ? AppTheme.accent : AppTheme.secondaryText)
                            }
                            Text("体重 \(day.weightKg.map { String(format: "%.1f kg", $0) } ?? "—")  ·  餐食 \(day.loggedMeals)/\(day.plannedMeals)  ·  训练 \(day.completedWorkouts)")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }.padding(.vertical, 10)
                    }.foregroundStyle(.white).buttonStyle(.plain)
                }
                if selectedDate != nil { Button("显示全部日期") { selectedDate = nil } }
            }.padding(20)
        }.screenBackground().fatLossCalendar().navigationTitle("完整周期记录").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onAppear { do { days = try FatLossService.timeline(program: program, in: context) } catch { errorMessage = error.localizedDescription } }
            .fatLossError($errorMessage)
    }
}

private struct FatLossDayDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var bodyCheckIns: [DailyBodyCheckIn]
    let program: FatLossProgram
    @State var day: FatLossDaySummary
    @State private var showsBody = false
    @State private var showsJump = false
    @State private var errorMessage: String?
    private var bodyCheckIn: DailyBodyCheckIn? {
        bodyCheckIns.first { FatLossCalendar.sameDay($0.date, day.date) }
    }
    var body: some View {
        List {
            Section("计划与实际") {
                LabeledContent("餐食", value: "实记 \(day.loggedMeals) · 计划 \(day.plannedMeals) · 明确未吃 \(day.skippedMeals)")
                LabeledContent("训练", value: "完成 \(day.completedWorkouts) · 计划 \(day.plannedWorkouts)")
                LabeledContent("营养", value: day.loggedMeals == 0 ? "未记录" : (day.knownCalorieMeals == 0 ? "营养待核算" : (day.unknownNutritionMeals > 0 ? "\(day.knownCalories) kcal 已知 · \(day.unknownNutritionMeals) 餐营养不完整" : "\(day.knownCalories) kcal 已记录")))
            }
            Section("身体与活动") {
                LabeledContent("腰围", value: day.waistCm.map { "\($0) cm" } ?? "未记录")
                LabeledContent("步数", value: day.steps.map(String.init) ?? "未记录")
                LabeledContent("睡眠", value: day.sleepHours.map { "\($0) 小时" } ?? "未记录")
                LabeledContent("跳绳个数", value: day.jumpCount > 0 ? "\(day.jumpCount)" : "未记录")
                LabeledContent("实际跳跃", value: day.jumpActiveSeconds.map { "\($0 / 60) 分钟" } ?? "未记录")
                LabeledContent("含休息总时长", value: day.jumpElapsedSeconds.map { "\($0 / 60) 分钟" } ?? "未记录")
                LabeledContent("饮水记录", value: day.waterMilliliters > 0 ? "\(day.waterMilliliters) ml" : "未记录")
                LabeledContent("腹胀", value: day.bloatingScore.map { "\($0) / 3" } ?? "未记录")
                LabeledContent("全身体感", value: day.bodyFeeling ?? bodyCheckIn.map { "\($0.conditionScore) / 5" } ?? "未记录")
                if let notes = day.workoutNotes, !notes.isEmpty {
                    ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                }
            }
            Section {
                NavigationLink("查看餐单与实际", destination: FatLossMealsView(program: program, initialDate: day.date))
                NavigationLink("步数、睡眠与腹胀", destination: FatLossDailyEditor(program: program, date: day.date))
                Button("记录这一天的跳绳") { showsJump = true }
                    .disabled(day.date > FatLossCalendar.day(.now))
                Button("记录这一天的全身体感") { showsBody = true }
                    .disabled(day.date > FatLossCalendar.day(.now))
                NavigationLink("身体数据", destination: BodyMeasurementsView())
            }
        }.scrollContentBackground(.hidden).screenBackground().fatLossCalendar()
            .navigationTitle(FatLossCalendar.label(day.date)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onAppear(perform: refresh)
            .sheet(isPresented: $showsBody, onDismiss: refresh) {
                NavigationStack { DailyBodyCheckInEditor(checkIn: bodyCheckIn, date: day.date) }
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showsJump, onDismiss: refresh) {
                JumpRopeQuickEntrySheet(initialDate: day.date) { count, active, elapsed, date in
                    do {
                        _ = try WellnessToolService.recordJumpRope(count: count, activeDurationSeconds: active,
                            elapsedDurationSeconds: elapsed, at: date, in: context)
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            .fatLossError($errorMessage)
    }
    private func refresh() {
        do {
            if let current = try FatLossService.timeline(program: program, in: context).first(where: { FatLossCalendar.sameDay($0.date, day.date) }) {
                day = current
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
