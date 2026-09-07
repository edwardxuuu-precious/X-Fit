import Charts
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledWorkout.plannedDate) private var schedules: [ScheduledWorkout]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var exercises: [Exercise]
    @Query private var templates: [WorkoutTemplate]
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var selectedDate = Date.now.startOfDay
    @State private var workoutSessionID: UUID?
    @State private var showWorkout = false
    @State private var showRope = false
    @State private var starting = false
    @State private var errorMessage: String?

    private var activeSession: WorkoutSession? { sessions.first { $0.status == .inProgress } }
    private var daySchedules: [ScheduledWorkout] {
        schedules.filter { $0.plannedDate.isSameDay(as: selectedDate) && $0.status != .skipped }.sorted { left, right in
            let leftManual = templates.first { $0.id == left.templateID }?.isOneOff == true
            let rightManual = templates.first { $0.id == right.templateID }?.isOneOff == true
            if leftManual != rightManual { return leftManual }
            if left.status != right.status { return left.status == .planned }
            return left.createdAt > right.createdAt
        }
    }
    private var weekDays: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: Date.now)?.start ?? Date.now.startOfDay
        return (0..<7).map { start.addingDays($0) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    ScreenHeader(eyebrow: "X-FIT / TRAINING", title: "今天，练得更强")
                    NavigationLink(destination: ScheduleView()) {
                        Image(systemName: "calendar").frame(width: 44, height: 44)
                            .background(AppTheme.elevatedSurface, in: Circle())
                    }.accessibilityLabel("训练日程")
                }
                HStack(spacing: 2) {
                    ForEach(weekDays, id: \.self) { day in
                        let selected = day.isSameDay(as: selectedDate)
                        Button { selectedDate = day } label: {
                            VStack(spacing: 5) {
                                Text(day, format: .dateTime.weekday(.narrow)).font(.caption)
                                Text("\(Calendar.current.component(.day, from: day))").font(.body.bold().monospacedDigit())
                                Circle().fill(schedules.contains { $0.plannedDate.isSameDay(as: day) && $0.status != .skipped } ? (selected ? Color.black : AppTheme.accent) : .clear).frame(width: 4, height: 4)
                            }.frame(maxWidth: .infinity, minHeight: 60)
                                .foregroundStyle(selected ? .black : .white)
                                .background(selected ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityLabel(day.formatted(.dateTime.month().day().weekday(.wide)))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("训练周历")
                if let activeSession {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("训练进行中", systemImage: "record.circle").font(.subheadline).foregroundStyle(AppTheme.accent)
                        Text(activeSession.templateName).font(.title2.bold())
                        Button { open(activeSession.id) } label: { Label("继续训练", systemImage: "play.fill").neonButtonStyle() }
                            .accessibilityIdentifier("继续训练")
                    }.padding(20).padding(.top, 30).background { trainingArtwork }.clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let schedule = daySchedules.first {
                    workoutCard(schedule)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(selectedDate.isSameDay(as: .now) ? "今天，按自己的节奏" : selectedDate.formatted(.dateTime.month().day()))
                            .font(.title2.bold())
                        Text("还没有训练安排").foregroundStyle(AppTheme.secondaryText)
                        NavigationLink(destination: DailyWorkoutBuilderView(initialDate: selectedDate)) {
                            Label(selectedDate.isSameDay(as: .now) ? "安排今天训练" : "安排这天训练", systemImage: "plus").neonButtonStyle()
                        }.accessibilityIdentifier("安排今天训练")
                    }.padding(20).padding(.top, 30).background { trainingArtwork }.clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    Text("本周安排").font(.headline)
                    Spacer()
                    NavigationLink("查看全部", destination: ScheduleView()).frame(minHeight: 44)
                }
                let weekSchedules = schedules.filter { item in weekDays.contains { $0.isSameDay(as: item.plannedDate) } && item.status != .skipped }
                if weekSchedules.isEmpty {
                    Text("本周暂无安排。可以逐日添加，也可以导入已有计划。")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                } else {
                    VStack(spacing: 0) {
                        ForEach(weekSchedules) { item in
                            NavigationLink(destination: DailyWorkoutBuilderView(initialDate: item.plannedDate, initialScheduleID: item.id)) {
                                HStack(spacing: 14) {
                                    Text(item.plannedDate, format: .dateTime.weekday(.short)).font(.caption).foregroundStyle(AppTheme.secondaryText).frame(width: 42)
                                    Text(item.templateName).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "chevron.right")
                                        .foregroundStyle(item.status == .completed ? AppTheme.accent : AppTheme.secondaryText)
                                }.frame(minHeight: 56).contentShape(Rectangle())
                            }
                        }
                    }
                }
                VStack(spacing: 0) {
                    if let program = programs.first(where: { $0.statusRaw == "active" }) {
                        NavigationLink(destination: FatLossTrainingView(program: program)) {
                            destinationRow("减脂训练计划", "calendar.badge.plus")
                        }.accessibilityIdentifier("训练-减脂计划导入")
                        Divider()
                    }
                    NavigationLink(destination: PlanView()) { destinationRow("训练计划与动作库", "square.stack.3d.up") }
                        .accessibilityIdentifier("训练计划与动作库")
                    Divider()
                    NavigationLink(destination: HistoryView()) { destinationRow("训练历史", "clock.arrow.circlepath") }
                    Divider()
                    Button { showRope = true } label: { destinationRow("记录跳绳", "figure.jumprope") }
                        .accessibilityIdentifier("训练-记录跳绳")
                }.padding(.top, 4)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.screenBackground().buttonStyle(.plain).toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showWorkout) {
                if let workoutSessionID { ActiveWorkoutView(sessionID: workoutSessionID) }
            }
            .sheet(isPresented: $showRope) {
                JumpRopeQuickEntrySheet(initialDate: min(selectedDate, .now)) { count, active, elapsed, date in
                    do { _ = try WellnessToolService.recordJumpRope(count: count, activeDurationSeconds: active, elapsedDurationSeconds: elapsed, at: date, in: modelContext) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .alert("操作未完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }
    private var trainingArtwork: some View {
        GeometryReader { geometry in
            Image("EditorialTraining")
                .resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.88), .black.opacity(0.12)], startPoint: .leading, endPoint: .trailing)
                }
                .overlay {
                    LinearGradient(colors: [.clear, AppTheme.background.opacity(0.96)], startPoint: .center, endPoint: .bottom)
                }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private func workoutCard(_ schedule: ScheduledWorkout) -> some View {
        let items = templateExercises.filter { $0.templateID == schedule.templateID }.sorted { $0.order < $1.order }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(selectedDate.isSameDay(as: .now) ? "今日训练" : selectedDate.formatted(.dateTime.month().day()))
                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.posterWarmWhite)
                    Spacer()
                    if schedule.status == .completed,
                       let session = sessions.first(where: { $0.scheduledWorkoutID == schedule.id && $0.status == .completed }) {
                        NavigationLink(destination: HistoricalWorkoutEditView(sessionID: session.id)) {
                            Label("修改记录", systemImage: "pencil").font(.caption).frame(minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("修改今日记录")
                    } else {
                        NavigationLink(destination: DailyWorkoutBuilderView(initialDate: selectedDate, initialScheduleID: schedule.id)) {
                            Label("调整", systemImage: "slider.horizontal.3").font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("修改今日计划")
                    }
                }
                Text(schedule.templateName)
                    .font(AppTheme.pageTitle).foregroundStyle(AppTheme.posterWarmWhite)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(items.reduce(0) { $0 + $1.targetSets })")
                        .font(AppTheme.metricValue)
                        .foregroundStyle(AppTheme.accent)
                    Text("组").font(.caption).foregroundStyle(AppTheme.posterWarmWhite)
                    Text("/").font(.subheadline).foregroundStyle(AppTheme.posterWarmWhite).accessibilityHidden(true)
                    Text("\(items.count) 个动作").font(.subheadline).foregroundStyle(AppTheme.posterWarmWhite)
                }.padding(.bottom, 8)
                workoutAction(schedule)
            }
            .padding(18)
            .background { trainingArtwork }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if !items.isEmpty {
                HStack {
                    Text("今日动作").font(.subheadline.weight(.semibold))
                    Rectangle().fill(AppTheme.line).frame(height: 1)
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
                            Text(exercises.first { $0.id == item.exerciseID }?.name ?? "已保存动作").font(.subheadline)
                            Spacer(minLength: 8)
                            Text("\(item.targetSets) 组").font(.caption.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
                        }.frame(minHeight: 44)
                        Rectangle().fill(AppTheme.line).frame(height: 1)
                    }
                }
                if items.count > 4 {
                    NavigationLink(destination: DailyWorkoutBuilderView(initialDate: selectedDate, initialScheduleID: schedule.id)) {
                        HStack { Text("查看全部 \(items.count) 个动作"); Spacer(); Image(systemName: "arrow.right") }
                            .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent).frame(minHeight: 44)
                    }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("训练-今日安排")
    }

    @ViewBuilder private func workoutAction(_ schedule: ScheduledWorkout) -> some View {
        if schedule.status == .completed {
            if let session = sessions.first(where: { $0.scheduledWorkoutID == schedule.id && $0.status == .completed }) {
                NavigationLink(destination: WorkoutDetailView(sessionID: session.id)) {
                    heroActionLabel("查看训练记录", icon: "checkmark.circle")
                }
            } else { Label("已完成", systemImage: "checkmark.circle").foregroundStyle(AppTheme.accent) }
        } else if selectedDate.isSameDay(as: .now) {
            Button { start(schedule) } label: { heroActionLabel(starting ? "正在准备…" : "开始训练") }
                .disabled(starting).accessibilityIdentifier("开始记录训练")
        } else {
            NavigationLink(destination: DailyWorkoutBuilderView(initialDate: selectedDate, initialScheduleID: schedule.id)) {
                heroActionLabel("查看训练安排")
            }
        }
    }
    private func heroActionLabel(_ title: String, icon: String = "arrow.right") -> some View {
        HStack { Text(title); Spacer(); Image(systemName: icon) }
            .padding(.horizontal, 16).neonButtonStyle()
    }
    private func destinationRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 24)
            Text(title).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.secondaryText)
        }.frame(minHeight: 52).contentShape(Rectangle())
    }
    private func open(_ id: UUID) { workoutSessionID = id; showWorkout = true }
    private func start(_ schedule: ScheduledWorkout) {
        starting = true
        Task { @MainActor in
            defer { starting = false }
            do { open(try await WorkoutService.startUsingAvailableBodyWeight(schedule: schedule, in: modelContext)) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

enum ConditionScorePresentation {
    static func emoji(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "😵"
        case 2: return "😣"
        case 3: return "😐"
        case 4: return "🙂"
        default: return "💪"
        }
    }

    static func title(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "状态很差，建议休息或明显降量"
        case 2: return "状态偏差，训练时注意反馈"
        case 3: return "状态一般，按实际感觉调整"
        case 4: return "状态不错，可以正常训练"
        default: return "状态很好，准备充分"
        }
    }

    static func shortTitle(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "状态很差"
        case 2: return "状态偏差"
        case 3: return "状态一般"
        case 4: return "状态不错"
        default: return "状态很好"
        }
    }
}

struct DailyBodyCheckInEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let checkIn: DailyBodyCheckIn?
    let date: Date

    @State private var score: Int
    @State private var notes: String
    @State private var selectedKind: BodyMarkerKind = .area
    @State private var markers: [BodyMapMarker]
    @State private var errorMessage: String?
    @State private var inferenceMessage: String?

    init(checkIn: DailyBodyCheckIn?, date: Date = .now) {
        self.checkIn = checkIn
        self.date = date
        _score = State(initialValue: checkIn?.conditionScore ?? 3)
        _notes = State(initialValue: checkIn?.discomfortNotes ?? "")
        _markers = State(initialValue: checkIn?.bodyMarkers ?? [])
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                scoreCard
                notesCard
                anatomyCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .dismissKeyboardWhenScrolling {
            KeyboardDismissal.dismiss()
        }
        .background(AppTheme.background)
        .navigationTitle(date.isSameDay(as: .now) ? "今日体感" : "身体体感")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .accessibilityIdentifier("取消今日体感")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("保存今日体感")
                    .disabled(date.startOfDay > Date.now.startOfDay)
            }
        }
        .alert("保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("训练前整体状态（1 差 → 5 好）")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        score = value
                    } label: {
                        VStack(spacing: 5) {
                            Text(ConditionScorePresentation.emoji(for: value))
                                .font(.title2)
                            Text("\(value)")
                                .font(.caption2.bold().monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            score == value ? AppTheme.accent.opacity(0.18) : AppTheme.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(score == value ? AppTheme.accent : AppTheme.line, lineWidth: score == value ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("体感 \(value) 分，\(ConditionScorePresentation.title(for: value))")
                    .accessibilityIdentifier("body-score-\(value)")
                    .accessibilityAddTraits(score == value ? .isSelected : [])
                }
            }

            Text(ConditionScorePresentation.title(for: score))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("不适备注")
                .font(.headline)
            TextField("例如：右肩前侧抬手疼，左膝下蹲发紧", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("body-discomfort-notes")

            Button {
                let result = BodyRegionCatalog.inferMarkers(in: notes, kind: selectedKind)
                merge(result.markers)
                if result.requiresConfirmation {
                    inferenceMessage = "无法确定\(result.unresolvedTerms.joined(separator: "、"))的前后或左右位置，请在人体图上确认。"
                } else if result.markers.isEmpty, !result.ignoredNegatedTerms.isEmpty {
                    inferenceMessage = "已忽略否定描述，没有自动添加标记。"
                } else if result.markers.isEmpty {
                    inferenceMessage = "没有识别到明确部位，请在人体图上手动点选。"
                } else if !result.ignoredNegatedTerms.isEmpty {
                    inferenceMessage = "已标记明确不适，并忽略了否定描述。"
                } else {
                    inferenceMessage = "已标记 \(result.markers.count) 个明确部位，请确认后保存。"
                }
            } label: {
                Label("按备注识别并标记部位", systemImage: "sparkles")
                    .font(.caption.bold())
            }
            .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("按备注标记部位")

            if let inferenceMessage {
                Text(inferenceMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("body-inference-result")
            }
        }
        .cardSurface()
    }

    private var anatomyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("不适部位")
                    .font(.headline)
                Text("先选标记类型，再点正面或背面的部位。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("标记类型", selection: $selectedKind) {
                ForEach(BodyMarkerKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("body-marker-kind")

            BodyMapDiagram(
                markers: markers,
                selectedKind: selectedKind,
                isInteractive: true,
                onTap: toggle
            )
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Label("红色区域：肌肉 / 部位", systemImage: "rectangle.inset.filled")
                Label("红点：关节 / 筋膜", systemImage: "circle.fill")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if markers.isEmpty {
                Text("还没有标记。没有不适时可以只保存体感分数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已标注")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(sortedMarkers) { marker in
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: marker.kind == .jointFascia ? 8 : 13, height: 8)
                            Text("\(BodyRegionCatalog.definition(for: marker.regionID)?.name ?? marker.regionID) · \(marker.kind.title)")
                                .font(.caption)
                            Spacer()
                            Button {
                                markers.removeAll { $0.id == marker.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除\(BodyRegionCatalog.definition(for: marker.regionID)?.name ?? marker.regionID)的\(marker.kind.title)标注")
                            .accessibilityIdentifier("remove-body-marker-\(marker.id)")
                        }
                    }
                }
            }
        }
        .cardSurface()
    }

    private var sortedMarkers: [BodyMapMarker] {
        markers.sorted {
            (BodyRegionCatalog.definition(for: $0.regionID)?.name ?? $0.regionID)
                < (BodyRegionCatalog.definition(for: $1.regionID)?.name ?? $1.regionID)
        }
    }

    private func merge(_ incoming: [BodyMapMarker]) {
        guard !incoming.isEmpty else { return }
        for marker in incoming {
            markers.removeAll { $0.id == marker.id }
            markers.append(marker)
        }
    }

    private func toggle(_ regionID: String) {
        if markers.contains(where: { $0.regionID == regionID && $0.kind == selectedKind }) {
            markers.removeAll { $0.regionID == regionID && $0.kind == selectedKind }
        } else {
            markers.append(BodyMapMarker(regionID: regionID, kind: selectedKind))
        }
    }

    private func save() {
        do {
            try DailyBodyCheckInService.save(
                existing: checkIn,
                date: date,
                conditionScore: score,
                discomfortNotes: notes,
                bodyMarkers: markers,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BodyMapDiagram: View {
    let markers: [BodyMapMarker]
    let selectedKind: BodyMarkerKind
    let isInteractive: Bool
    let onTap: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("MuscleMapBase")
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("正面和背面肌肉图")
                    .accessibilityIdentifier("body-muscle-map")

                ForEach(BodyRegionCatalog.all) { region in
                    let placement = BodyRegionImageLayout.placement(for: region)
                    regionControl(region, placement: placement, in: proxy.size)
                        .position(
                            x: proxy.size.width * placement.x,
                            y: proxy.size.height * placement.y
                        )
                }

                viewSideLabel("正面", x: 0.28, in: proxy.size)
                viewSideLabel("背面", x: 0.735, in: proxy.size)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正面和背面肌肉不适标注图")
        .accessibilityIdentifier("body-muscle-map-container")
    }

    @ViewBuilder
    private func regionControl(
        _ region: BodyRegionDefinition,
        placement: BodyRegionImagePlacement,
        in size: CGSize
    ) -> some View {
        let hasAreaMarker = markers.contains { $0.regionID == region.id && $0.kind == .area }
        let hasJointMarker = markers.contains { $0.regionID == region.id && $0.kind == .jointFascia }
        let isSelectedForCurrentKind = markers.contains {
            $0.regionID == region.id && $0.kind == selectedKind
        }
        let markerDescription: String = {
            switch (hasAreaMarker, hasJointMarker) {
            case (true, true): return "肌肉 / 区域和关节 / 筋膜"
            case (true, false): return BodyMarkerKind.area.title
            case (false, true): return BodyMarkerKind.jointFascia.title
            case (false, false): return "未标记"
            }
        }()
        let control = ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    hasAreaMarker
                        ? Color.red.opacity(0.46)
                        : Color.white.opacity(isInteractive ? 0.018 : 0)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            hasAreaMarker
                                ? Color.red
                                : Color.white.opacity(isInteractive ? 0.10 : 0),
                            lineWidth: hasAreaMarker ? 1.5 : 0.7
                        )
                }
                .shadow(color: hasAreaMarker ? Color.red.opacity(0.65) : .clear, radius: 7)

            if hasJointMarker {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                    .shadow(color: Color.red.opacity(0.9), radius: 5)
            }
        }
        .frame(
            width: max(20, size.width * placement.width),
            height: max(16, size.height * placement.height)
        )

        if isInteractive {
            Button { onTap(region.id) } label: {
                control
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(region.name)，\(markerDescription)")
            .accessibilityHint("点按切换为\(selectedKind.title)标记")
            .accessibilityIdentifier("body-region-\(region.id)")
            .accessibilityAddTraits(isSelectedForCurrentKind ? .isSelected : [])
        } else {
            control
                .accessibilityHidden(true)
        }
    }

    private func viewSideLabel(_ title: String, x: CGFloat, in size: CGSize) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .position(x: size.width * x, y: 18)
            .accessibilityHidden(true)
    }
}
