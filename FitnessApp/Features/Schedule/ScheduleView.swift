import SwiftData
import SwiftUI

struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledWorkout.plannedDate) private var schedules: [ScheduledWorkout]
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]

    @State private var showAddOptions = false
    @State private var showAdd = false
    @State private var showDailyBuilder = false
    @State private var rescheduling: ScheduledWorkout?
    @State private var skipping: ScheduledWorkout?
    @State private var skipReason = ""
    @State private var errorMessage: String?

    private var visibleSchedules: [ScheduledWorkout] {
        let earliest = Date.now.addingDays(-7).startOfDay
        let latest = Date.now.addingDays(30).startOfDay
        return schedules.filter { $0.plannedDate >= earliest && $0.plannedDate <= latest }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                ScreenHeader(
                    eyebrow: "PLAN YOUR WEEK",
                    title: "训练日程",
                    trailingSystemImage: "plus",
                    trailingAccessibilityLabel: "新增训练安排",
                    trailingAction: { showAddOptions = true }
                )

                legend

                if visibleSchedules.isEmpty {
                    ContentUnavailableView(
                        "还没有训练安排",
                        systemImage: "calendar.badge.plus",
                        description: Text("点击右上角，为指定日期安排一次训练。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                } else {
                    ForEach(visibleSchedules) { schedule in
                        scheduleRow(schedule)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDailyBuilder) {
            DailyWorkoutBuilderView(initialDate: .now)
        }
        .confirmationDialog(
            "新增训练安排",
            isPresented: $showAddOptions,
            titleVisibility: .visible
        ) {
            Button("自选动作编排") {
                showDailyBuilder = true
            }
            Button("从现有模板安排") {
                showAdd = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("自选编排可按日期自由选择动作；模板安排会复用已经建立的训练模板。")
        }
        .sheet(isPresented: $showAdd) {
            AddScheduledWorkoutView(templates: templates)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .sheet(item: $rescheduling) { schedule in
            RescheduleWorkoutView(schedule: schedule)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .alert("跳过这次训练？", isPresented: Binding(
            get: { skipping != nil },
            set: { if !$0 { skipping = nil } }
        )) {
            TextField("原因（可选）", text: $skipReason)
            Button("取消", role: .cancel) {
                skipping = nil
                skipReason = ""
            }
            Button("确认跳过", role: .destructive) {
                skipSelected()
            }
        } message: {
            Text("跳过会保留在日程统计中，但不会计入已完成训练。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("计划", color: AppTheme.accent)
            legendItem("完成", color: .blue)
            legendItem("跳过", color: .orange)
            Spacer()
            Text("近 7 天 / 未来 30 天")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface(padding: 12, cornerRadius: 14)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func scheduleRow(_ schedule: ScheduledWorkout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(schedule.plannedDate, format: .dateTime.day())
                        .font(.title2.weight(.black).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(schedule.plannedDate, format: .dateTime.weekday(.short))
                        .font(.caption2.bold())
                        .foregroundStyle(statusColor(schedule.status))
                }
                .frame(width: 54, height: 58)
                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(schedule.templateName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        if schedule.isManuallyScheduled {
                            Text("临时")
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent, in: Capsule())
                        } else if schedule.originalPlannedDate != nil {
                            Text("已改期")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    Text(statusDescription(schedule))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Menu {
                    if schedule.status == .planned {
                        Button {
                            rescheduling = schedule
                        } label: {
                            Label("调整日期", systemImage: "calendar.badge.clock")
                        }
                        Button(role: .destructive) {
                            skipReason = ""
                            skipping = schedule
                        } label: {
                            Label("跳过训练", systemImage: "forward.end")
                        }
                    } else if schedule.status == .skipped {
                        Button {
                            restore(schedule)
                        } label: {
                            Label("恢复训练", systemImage: "arrow.uturn.backward")
                        }
                        Button {
                            rescheduling = schedule
                        } label: {
                            Label("改期并恢复", systemImage: "calendar.badge.clock")
                        }
                    }

                    if schedule.isManuallyScheduled && (schedule.status == .planned || schedule.status == .skipped) {
                        Button(role: .destructive) {
                            deleteManual(schedule)
                        } label: {
                            Label("删除临时安排", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.elevatedSurface, in: Circle())
                }
                .disabled(schedule.status == .completed || schedule.status == .inProgress)
            }

            if schedule.status == .planned || schedule.status == .skipped {
                NavigationLink(destination: DailyWorkoutBuilderView(
                    initialDate: schedule.plannedDate,
                    initialScheduleID: schedule.id
                )) {
                    HStack {
                        Label(
                            schedule.status == .skipped ? "调整动作并恢复" : "调整当天动作",
                            systemImage: "slider.horizontal.3"
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("调整当天动作")
            }
        }
        .cardSurface(padding: 13, cornerRadius: 17)
    }

    private func statusDescription(_ schedule: ScheduledWorkout) -> String {
        switch schedule.status {
        case .planned:
            if let original = schedule.originalPlannedDate {
                return "从 \(original.formatted(.dateTime.month().day())) 调整到这里"
            }
            return schedule.plannedDate.isSameDay(as: .now) ? "今天 · 等待开始" : "已计划"
        case .inProgress:
            return "训练进行中"
        case .completed:
            return "已完成"
        case .skipped:
            return schedule.skipReason.isEmpty ? "已跳过" : "已跳过 · \(schedule.skipReason)"
        }
    }

    private func statusColor(_ status: ScheduleStatus) -> Color {
        switch status {
        case .planned: return AppTheme.accent
        case .inProgress: return AppTheme.purple
        case .completed: return .blue
        case .skipped: return .orange
        }
    }

    private func skipSelected() {
        guard let skipping else { return }
        do {
            try ScheduleService.skip(skipping, reason: skipReason, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
        self.skipping = nil
        skipReason = ""
    }

    private func restore(_ schedule: ScheduledWorkout) {
        do {
            try ScheduleService.restore(schedule, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteManual(_ schedule: ScheduledWorkout) {
        do {
            try ScheduleService.deleteManual(schedule, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddScheduledWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let templates: [WorkoutTemplate]

    @State private var selectedTemplateID: UUID?
    @State private var selectedDate = Date.now.startOfDay
    @State private var errorMessage: String?

    private var activeTemplates: [WorkoutTemplate] {
        templates.filter(\.isActive)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("训练计划") {
                    if activeTemplates.isEmpty {
                        Text("请先在训练页创建并启用一个训练计划。")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("选择计划", selection: $selectedTemplateID) {
                            ForEach(activeTemplates) { template in
                                Text(template.name).tag(Optional(template.id))
                            }
                        }
                    }
                }

                Section("训练日期") {
                    DatePicker(
                        "日期",
                        selection: $selectedDate,
                        in: Date.now.addingDays(-7)...Date.now.addingDays(90),
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("临时加练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { addSchedule() }
                        .fontWeight(.semibold)
                        .disabled(selectedTemplateID == nil)
                }
            }
            .onAppear {
                selectedTemplateID = selectedTemplateID ?? activeTemplates.first?.id
            }
            .alert("无法添加", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func addSchedule() {
        guard let template = activeTemplates.first(where: { $0.id == selectedTemplateID }) else { return }
        do {
            _ = try ScheduleService.addManual(template: template, on: selectedDate, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RescheduleWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let schedule: ScheduledWorkout
    @State private var selectedDate: Date
    @State private var errorMessage: String?

    init(schedule: ScheduledWorkout) {
        self.schedule = schedule
        _selectedDate = State(initialValue: schedule.plannedDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("训练") {
                    Text(schedule.templateName)
                }
                Section("新的日期") {
                    DatePicker(
                        "日期",
                        selection: $selectedDate,
                        in: Date.now.addingDays(-7)...Date.now.addingDays(90),
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("调整训练日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert("无法改期", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func save() {
        do {
            try ScheduleService.reschedule(schedule, to: selectedDate, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
