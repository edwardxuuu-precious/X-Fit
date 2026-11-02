import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum TrainingPlanPresentation {
    struct Window: Equatable {
        let startLocalDay: String
        let endLocalDay: String
        let timeZone: TimeZone

        var startDate: Date { TrainingLocalDate.date(startLocalDay, timeZone: timeZone)! }
        var endDate: Date { TrainingLocalDate.date(endLocalDay, timeZone: timeZone)! }
        var label: String { "\(startLocalDay) 至 \(endLocalDay)" }

        func status(on now: Date = .now) -> String {
            let today = TrainingLocalDate.key(now, timeZone: timeZone)
            if today < startLocalDay { return "待生效编排" }
            if today > endLocalDay { return "历史编排" }
            return "当前编排"
        }
    }

    static func window(for revision: TrainingProgramRevision) -> Window {
        if let source = revision.snapshot?.confirmedImport,
           let zone = TimeZone(identifier: source.timeZoneIdentifier),
           TrainingLocalDate.date(source.startLocalDay, timeZone: zone) != nil,
           TrainingLocalDate.date(source.endLocalDay, timeZone: zone) != nil,
           source.startLocalDay <= source.endLocalDay {
            return Window(startLocalDay: source.startLocalDay, endLocalDay: source.endLocalDay, timeZone: zone)
        }
        return Window(startLocalDay: FatLossCalendar.label(revision.effectiveDate),
            endLocalDay: FatLossCalendar.label(FatLossCalendar.adding(6, to: revision.effectiveDate)),
            timeZone: FatLossCalendar.calendar.timeZone)
    }

    static func cardioDraft(scheduleID: UUID, links: [ProgramWorkoutLink],
                            revisions: [TrainingProgramRevision]) -> ProgramCardioDraft? {
        guard let link = links.first(where: { $0.scheduledWorkoutID == scheduleID }),
              let revisionID = link.trainingProgramRevisionID,
              let revision = revisions.first(where: { $0.id == revisionID }) else { return nil }
        return revision.snapshot?.cardioWorkouts.first { $0.code == link.templateCode }
    }

    static func isJumpRope(_ cardio: ProgramCardioDraft, exercises: [Exercise]) -> Bool {
        if let exerciseID = cardio.catalogExerciseID {
            guard let exercise = exercises.first(where: { $0.id == exerciseID }) else { return false }
            return exercise.equipment == "跳绳" && exercise.volumeUnit == .second
        }
        return cardio.code.hasPrefix("ROPE_")
    }

    static func firstScheduledLocalDay(snapshot: TrainingProgramSnapshot, source: ConfirmedTrainingPlanSource) -> String {
        let zone = TimeZone(identifier: source.timeZoneIdentifier) ?? .current
        guard let start = MealLocalDay.date(source.startLocalDay, timeZone: zone),
              let firstOffset = (snapshot.strengthWorkouts.map(\.weekday) + snapshot.cardioWorkouts.map(\.weekday))
                .map({ ($0 + 5) % 7 }).min() else { return source.startLocalDay }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return TrainingLocalDate.key(calendar.date(byAdding: .day, value: firstOffset, to: start)!, timeZone: zone)
    }
    static func selectedRevision(in revisions: [TrainingProgramRevision], selectedID: UUID?, now: Date = .now) -> TrainingProgramRevision? {
        if let selected = revisions.first(where: { $0.id == selectedID }) { return selected }
        let today = FatLossCalendar.day(now)
        let ordered = revisions.sorted {
            if $0.effectiveDate == $1.effectiveDate { return $0.revision > $1.revision }
            return $0.effectiveDate > $1.effectiveDate
        }
        if let current = ordered.first(where: { $0.effectiveDate <= today }) { return current }
        guard let firstFutureDate = ordered.last?.effectiveDate else { return nil }
        return ordered.first { $0.effectiveDate == firstFutureDate }
    }

    static func initialActualDate(selectedDate: Date, now: Date = .now) -> Date {
        min(selectedDate, now)
    }

    static func requiredRoundCount(for cardio: ProgramCardioDraft) -> Int {
        let requiredIntervals = cardio.intervals.components(separatedBy: "；状态良好可加").first ?? cardio.intervals
        return requiredIntervals
            .split(separator: "轮", omittingEmptySubsequences: false)
            .dropLast()
            .compactMap { segment in
                segment.split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
            }
            .reduce(0, +)
    }

    static func roundedElapsedMinutes(for cardio: ProgramCardioDraft) -> Int {
        let seconds = cardio.elapsedSeconds ?? cardio.activeSeconds ?? 0
        return (seconds + 59) / 60
    }

    static func cardioVolumeSummary(_ cardio: ProgramCardioDraft, separator: String = " / ") -> String {
        let rounds = requiredRoundCount(for: cardio)
        if rounds > 0 {
            return "\(rounds) 轮\(separator)约 \(roundedElapsedMinutes(for: cardio)) 分钟"
        }
        if cardio.elapsedSeconds == nil,
           let lower = cardio.activeSeconds, let upper = cardio.activeSecondsUpper, upper > lower {
            return "\((lower + 59) / 60)–\((upper + 59) / 60) 分钟"
        }
        return "约 \(roundedElapsedMinutes(for: cardio)) 分钟"
    }
}

private struct TrainingImportPresentation: Identifiable {
    let id = UUID()
    let preview: [ProgramImportPreview]
    let cardioPreview: [ProgramCardioImportPreview]
    let startDate: Date
    let days: Int
    let lowEnergyMorning: Bool
}

struct FatLossTrainingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingProgramRevision.effectiveDate, order: .reverse)
    private var programRevisions: [TrainingProgramRevision]
    let program: FatLossProgram
    @State private var selectedRevisionID: UUID?
    @State private var startDate = Date.now
    @State private var lowEnergyMorning = true
    @State private var importPresentation: TrainingImportPresentation?
    @State private var showsRope = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var showsConfirmedPlanFile = false
    @State private var confirmedPlanPreview: ConfirmedTrainingPlanPreview?

    private var revisions: [TrainingProgramRevision] {
        programRevisions.filter { $0.programID == program.id }.sorted {
            if $0.effectiveDate == $1.effectiveDate { return $0.revision > $1.revision }
            return $0.effectiveDate > $1.effectiveDate
        }
    }
    private var selectedRevision: TrainingProgramRevision? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-lower-body-week"),
           let lowerBodyWeek = revisions.first(where: {
               $0.snapshot?.code == "CUT-LB3-20260914-R1"
           }) {
            return lowerBodyWeek
        }
        #endif
        return TrainingPlanPresentation.selectedRevision(in: revisions, selectedID: selectedRevisionID)
    }
    private var remainingDays: Int {
        guard let revision = selectedRevision else { return 1 }
        return max(1, min(7, FatLossCalendar.calendar.dateComponents([.day], from: FatLossCalendar.day(startDate),
            to: FatLossCalendar.adding(7, to: revision.effectiveDate)).day ?? 1))
    }

    var body: some View {
        List {
            if !revisions.isEmpty {
                Section(header: SprintSectionHeading(title: "编排版本", icon: "clock.arrow.circlepath")) {
                    Picker("选择编排", selection: Binding(
                        get: { selectedRevision?.id },
                        set: { selectedRevisionID = $0 }
                    )) {
                        ForEach(revisions) { item in
                            let window = TrainingPlanPresentation.window(for: item)
                            Text("\(window.startLocalDay) · 第 \(item.revision) 版 · \(window.status())").tag(Optional(item.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("训练编排-版本")
                }
            }
            if let revision = selectedRevision, let snapshot = revision.snapshot, snapshot.isValid {
                let window = TrainingPlanPresentation.window(for: revision)
                Section {
                    Label(snapshot.title, systemImage: "dumbbell")
                        .font(.headline).foregroundStyle(AppTheme.ink)
                    Text(snapshot.code).font(.caption.monospaced())
                    Text(window.status()).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("训练编排-时段状态")
                    Text(window.label).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        .accessibilityIdentifier("训练编排-日期范围")
                    Text("日期时区 · " + window.timeZone.identifier).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Text(snapshot.preferenceRevisionCode).font(.caption.monospaced()).foregroundStyle(AppTheme.secondaryText)
                    if window.status() == "待生效编排" {
                        Text("尚未生效，可提前查看与预览。").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    } else if window.status() == "历史编排" {
                        Text("保留原编排日期，不会自动移到今天。").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Text("一周编排 · 按完成反馈调整").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    if let source = snapshot.confirmedImport {
                        Text("已确认并导入：\(source.startLocalDay) — \(source.endLocalDay) · \(source.confirmationReference)")
                            .font(.caption).foregroundStyle(AppTheme.ink)
                        let firstDay = TrainingPlanPresentation.firstScheduledLocalDay(snapshot: snapshot, source: source)
                        NavigationLink {
                            TrainingDateMenuView(localDay: firstDay)
                                .onAppear { TrainingDateSelection.shared.select(localDay: firstDay) }
                        } label: {
                            Text("查看首日训练")
                        }.accessibilityIdentifier("已确认计划-查看首日")
                        DisclosureGroup("完整原方案与替代规则") {
                            Text("原文是提案存档；本次确认状态以此处的导入来源为准。")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            Text(source.sourceMarkdown).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                Section(header: SprintSectionHeading(title: "力量", icon: "dumbbell")) {
                    ForEach(snapshot.strengthWorkouts) { workout in
                        DisclosureGroup {
                            DisclosureGroup("训练说明") {
                                Text(workout.guidance).font(.caption).foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(workout.exercises) { exercise in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(exercise.name).font(.subheadline.weight(.semibold))
                                    Text(exerciseSummary(exercise)).font(.caption).foregroundStyle(AppTheme.secondaryText)
                                    ForEach(Array((exercise.plannedSets ?? []).enumerated()), id: \.offset) { index, plan in
                                        if let prescription = plan.prescription {
                                            HStack(alignment: .top) {
                                                Text("\(index + 1)").frame(width: 24)
                                                Text(TrainingWorkoutPresentation.planValue(plan, unit: ExerciseVolumeUnit(rawValue: exercise.volumeUnitRaw) ?? .kilogram))
                                                Spacer(minLength: 8)
                                                Text(TrainingWorkoutPresentation.target(prescription))
                                                    .foregroundStyle(AppTheme.secondaryText)
                                            }.font(.caption).frame(minHeight: 44)
                                        }
                                    }
                                    DisclosureGroup("计划详情与依据") {
                                        ForEach(Array((exercise.plannedSets ?? []).enumerated()), id: \.offset) { index, plan in
                                            if let prescription = plan.prescription {
                                                Text("第 \(index + 1) 组 · \(prescription.summary)")
                                                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    if !exercise.note.isEmpty {
                                        Text(exercise.note).font(.caption).foregroundStyle(AppTheme.secondaryText)
                                    }
                                    }.font(.caption)
                                }.padding(.vertical, 4)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(weekdayTitle(workout.weekday)) · \(TrainingWorkoutPresentation.title(workout.title))").font(.subheadline.weight(.semibold))
                                Text(volumeSummary(workout))
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }.padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("训练编排-力量-\(workout.code)")
                    }
                }
                Section(header: SprintSectionHeading(title: "有氧", icon: "figure.run")) {
                    ForEach(snapshot.cardioWorkouts) { cardio in
                        DisclosureGroup {
                            Text("\(cardio.timing) · \(cardio.intervals)")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            Text(cardio.guidance).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(weekdayTitle(cardio.weekday)) · \(cardio.title)").font(.subheadline.weight(.semibold))
                                Text(TrainingPlanPresentation.cardioVolumeSummary(cardio, separator: " · "))
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }.padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("训练编排-有氧-\(cardio.code)")
                    }
                    Button("记录实际跳绳") { showsRope = true }
                        .accessibilityIdentifier("训练编排-记录跳绳")
                }
                Section {
                    DisclosureGroup("重量、进阶与恢复") {
                        Text(snapshot.progressionRule).font(.subheadline)
                        Text(snapshot.lowEnergyRule).font(.caption).foregroundStyle(AppTheme.orange)
                        Text("重量仅参考同动作、同器械、单位明确且保留余力的完成组；缺少可靠记录时，热身后手动定重。单侧与双侧分别保留。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        Text("腿日容量较多，可能超过 90 分钟；到时先停在已完成部分，记录恢复情况供下一周调整。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                if snapshot.confirmedImport == nil { Section(header: SprintSectionHeading(title: "导入这一周", icon: "calendar.badge.plus")) {
                    DatePicker("开始日期", selection: $startDate,
                               in: revision.effectiveDate...FatLossCalendar.adding(6, to: revision.effectiveDate), displayedComponents: .date)
                    Toggle("晨练前仅咖啡和电解质", isOn: $lowEnergyMorning)
                    Text("开启时，有可靠历史重量的首个负重主项下调 10%；其他动作热身后按余力调整。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Button("预览训练日程") {
                        do {
                            let days = remainingDays
                            let generated = try FatLossService.importPreview(program: program, from: startDate, days: days,
                                lowEnergyMorning: lowEnergyMorning, in: context)
                            let generatedCardio = try FatLossService.cardioImportPreview(
                                program: program,
                                from: startDate,
                                days: days,
                                in: context
                            )
                            if generated.isEmpty && generatedCardio.isEmpty { notice = "所选日期没有已确认的训练安排。" }
                            else {
                                notice = nil
                                importPresentation = TrainingImportPresentation(
                                    preview: generated,
                                    cardioPreview: generatedCardio,
                                    startDate: startDate, days: days, lowEnergyMorning: lowEnergyMorning)
                            }
                        } catch { errorMessage = error.localizedDescription }
                    }.accessibilityIdentifier("预览减脂训练导入")
                } }
            } else {
                Text(revisions.isEmpty ? "尚无已确认编排。" : "该编排暂时无法读取，可切换其他版本；原数据保持不变。")
                    .font(.subheadline)
            }
        }
        .scrollContentBackground(.hidden).sprintPage().fatLossCalendar()
        .navigationTitle("训练编排").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("导入已确认计划", systemImage: "square.and.arrow.down") { chooseConfirmedPlan() }
                    .accessibilityIdentifier("已确认计划-导入")
            }
        }
        .onAppear { selectWeek() }
        .onChange(of: selectedRevisionID) { _, _ in selectWeek() }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let notice {
                // A successful import must be visible even when the list is scrolled
                // to the preview entry. Keep the user's plan and scroll position.
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(AppTheme.surface)
                    .accessibilityIdentifier("已确认计划-结果")
            }
        }
        .sheet(item: $importPresentation) { importSheet($0).sprintPage() }
        .sheet(item: $confirmedPlanPreview) { preview in
            ConfirmedTrainingPlanImportSheet(preview: preview) { result in
                selectedRevisionID = result.readback.revisionID
                notice = result.newScheduleCount == 0 ? "已核验现有完整计划，新增 0 项日程。"
                    : "已加入 \(result.newScheduleCount) 项日程；历史记录保持不变，所有新组均未完成。"
            }.sprintPage()
        }
        .fileImporter(isPresented: $showsConfirmedPlanFile, allowedContentTypes: [.json]) { result in
            do { try loadConfirmedPlan(from: result.get()) }
            catch { errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showsRope) {
            JumpRopeQuickEntrySheet(initialDate: TrainingPlanPresentation.initialActualDate(selectedDate: startDate)) { input in
                do { _ = try WellnessToolService.recordJumpRope(count: input.count, activeDurationSeconds: input.activeDurationSeconds,
                    elapsedDurationSeconds: input.elapsedDurationSeconds, at: input.date, totalSetCount: input.totalSetCount,
                    recordedTimeKnown: input.recordedTimeKnown, in: context) }
                catch { errorMessage = error.localizedDescription }
            }
        }
        .fatLossError($errorMessage)
    }

    private func chooseConfirmedPlan() {
        #if DEBUG
        if ConfirmedTrainingPlanUITestFixture.isEnabled {
            do { try loadConfirmedPlan(from: ConfirmedTrainingPlanUITestFixture.fileURL) }
            catch { errorMessage = error.localizedDescription }
            return
        }
        #endif
        showsConfirmedPlanFile = true
    }

    private func loadConfirmedPlan(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 2_097_152 else { throw ConfirmedTrainingPlanError.invalidPacket("文件过大") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let packet = try decoder.decode(ConfirmedTrainingPlanPacket.self, from: Data(contentsOf: url))
        guard packet.programID == program.id else { throw ConfirmedTrainingPlanError.invalidPacket("不是当前训练周期") }
        confirmedPlanPreview = try ConfirmedTrainingPlanService.preview(packet, in: context)
    }

    private func selectWeek() {
        guard let revision = selectedRevision else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-lower-body-week") {
            startDate = revision.effectiveDate
            return
        }
        #endif
        if revision.snapshot?.confirmedImport == nil {
            startDate = min(max(FatLossCalendar.day(.now), revision.effectiveDate), FatLossCalendar.adding(6, to: revision.effectiveDate))
            return
        }
        let window = TrainingPlanPresentation.window(for: revision)
        let today = TrainingLocalDate.date(TrainingLocalDate.key(.now, timeZone: window.timeZone), timeZone: window.timeZone)!
        startDate = min(max(today, window.startDate), window.endDate)
    }
    private func volumeSummary(_ workout: ProgramWorkoutDraft) -> String {
        let jumps = workout.exercises.filter { $0.name == "箱跳" }.reduce(0) { $0 + $1.sets }
        let resistance = workout.exercises.reduce(0) { $0 + $1.sets } - jumps
        return jumps > 0 ? "\(resistance) 个抗阻组＋\(jumps) 组箱跳" : "\(resistance) 个工作组"
    }
    private func weekdayTitle(_ weekday: Int) -> String {
        [1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"][weekday] ?? ""
    }
    private func exerciseSummary(_ exercise: ProgramExerciseDraft) -> String {
        let reps = exercise.repsLower == exercise.repsUpper ? "\(exercise.repsLower)" : "\(exercise.repsLower)–\(exercise.repsUpper)"
        let side = exercise.unilateral ? "每侧 " : ""
        let unitSuffix: String
        switch ExerciseVolumeUnit(rawValue: exercise.volumeUnitRaw) {
        case .meter: unitSuffix = "米"
        case .second: unitSuffix = "秒"
        default: unitSuffix = ""
        }
        return "\(exercise.sets) 组 × \(side)\(reps)\(unitSuffix) · 休息 \(exercise.restSeconds) 秒"
    }
    private func importSheet(_ presentation: TrainingImportPresentation) -> some View {
        let preview = presentation.preview
        let importSummary = ProgramImportSummary(preview: preview)
        let cardioImportable = presentation.cardioPreview.filter {
            !$0.alreadyImported && $0.conflictingNames.isEmpty
        }.count
        let cardioConflicts = presentation.cardioPreview.filter {
            !$0.alreadyImported && !$0.conflictingNames.isEmpty
        }.count
        let cardioImported = presentation.cardioPreview.filter(\.alreadyImported).count
        let importableCount = importSummary.importableCount + cardioImportable
        let conflictCount = importSummary.conflictCount + cardioConflicts
        let alreadyImportedCount = importSummary.alreadyImportedCount + cardioImported
        let canImport = importableCount > 0
        let actionTitle = canImport
            ? ((conflictCount > 0 || alreadyImportedCount > 0)
                ? "导入其余 \(importableCount) 条日程"
                : "导入 \(importableCount) 条训练日程")
            : "没有可导入的训练"
        return NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        importCount(importableCount, title: "可导入", color: AppTheme.accent)
                        Divider().frame(height: 38)
                        importCount(conflictCount, title: "已有训练", color: AppTheme.orange)
                        Divider().frame(height: 38)
                        importCount(alreadyImportedCount, title: "已导入", color: AppTheme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("训练导入-摘要")
                    Text("已有训练按日期保留；本次只导入没有冲突的日期，不覆盖、不删除。").font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                ForEach(preview) { item in
                    Section("\(FatLossCalendar.label(item.date)) · \(item.workout.title)") {
                        if item.alreadyImported {
                            Label("已经导入 · 无需重复操作", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        else if !item.conflictingNames.isEmpty {
                            Label("保留当天已有训练", systemImage: "shield.checkered")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.orange)
                                .accessibilityIdentifier("训练导入-保留冲突-\(item.id)")
                            Text(item.conflictingNames.joined(separator: "、")).font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Label("准备导入", systemImage: "calendar.badge.plus")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            ForEach(item.workout.exercises) { exercise in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name).font(.subheadline)
                                    Text(exerciseSummary(exercise)).font(.caption)
                                    if let plan = item.loadPlans[exercise.name] {
                                        Text("起始参考 \(plan.weight.formatted()) kg · \(plan.weightSide.title)")
                                            .font(.caption).foregroundStyle(AppTheme.ink)
                                    } else if exercise.volumeUnitRaw == ExerciseVolumeUnit.kilogram.rawValue {
                                        Text("重量待热身后确定").font(.caption).foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }
                ForEach(presentation.cardioPreview) { item in
                    Section("\(FatLossCalendar.label(item.date)) · \(item.cardio.title)") {
                        if item.alreadyImported {
                            Label("已经导入 · 无需重复操作", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.secondaryText)
                        } else if !item.conflictingNames.isEmpty {
                            Label("保留当天已有训练", systemImage: "shield.checkered")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.orange)
                            Text(item.conflictingNames.joined(separator: "、"))
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Label("准备加入跳绳日程", systemImage: "figure.jumprope")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            Text(item.cardio.intervals).font(.caption)
                            Text(item.cardio.guidance).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .sprintPage()
            .fatLossCalendar()
            .navigationTitle("导入前预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { importPresentation = nil } }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !canImport {
                        let reason = conflictCount > 0
                            ? "所选日期都有现有训练；将保留现有记录，不会覆盖。"
                            : "这些训练已经导入，无需重复操作。"
                        Text(reason).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    Button(actionTitle) { confirmImport(presentation) }
                        .disabled(!canImport)
                        .neonButtonStyle()
                        .opacity(canImport ? 1 : 0.45)
                        .accessibilityIdentifier("确认导入减脂训练")
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                .background(AppTheme.background.opacity(0.98))
            }
        }
    }

    private func importCount(_ value: Int, title: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }.frame(maxWidth: .infinity)
    }

    private func confirmImport(_ presentation: TrainingImportPresentation) {
        do {
            let count = try FatLossService.importWorkouts(program: program, from: presentation.startDate, days: presentation.days,
                conflictPolicy: .skipConflicts, lowEnergyMorning: presentation.lowEnergyMorning,
                expectedPreview: presentation.preview,
                expectedCardioPreview: presentation.cardioPreview,
                in: context)
            notice = "已导入 \(count) 条训练日程；已有训练保持不变。跳绳完成后从当日日程记录实际次数与时长。"
            importPresentation = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
