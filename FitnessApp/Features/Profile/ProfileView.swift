import SwiftData
import SwiftUI

struct ProfileView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                SprintPageHeader(title: "我的", icon: "person.crop.circle")

                NavigationLink(destination: AppSettingsView()) {
                    HStack(spacing: 14) {
                        SprintIcon(systemName: "slider.horizontal.3", size: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("设置").font(.headline)
                            Text("通知 · Apple 健康 · 数据")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right").foregroundStyle(AppTheme.ink)
                    }
                    .padding(18).frame(minHeight: 76)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityIdentifier("打开设置")

                VStack(alignment: .leading, spacing: 10) {
                    SprintSectionHeading(title: "记录", icon: "clock.arrow.circlepath")
                    VStack(spacing: 0) {
                        NavigationLink(destination: HistoryView()) { row("训练历史", "clock.arrow.circlepath") }
                        rowDivider
                        NavigationLink(destination: BodyMeasurementsView()) { row("身体数据", "figure.arms.open") }
                        rowDivider
                        NavigationLink(destination: TrainingCoachPreferencesView()) { row("训练偏好", "slider.horizontal.3") }
                            .accessibilityIdentifier("偏好与编排")
                    }.cardSurface(padding: 0)
                }

            }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 28)
        }.sprintPage().toolbar(.hidden, for: .navigationBar).buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Divider().overlay(AppTheme.line).padding(.leading, 54)
    }

    private func row(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            SprintIcon(systemName: icon, size: 36)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(AppTheme.secondaryText)
        }.padding(.horizontal, 16).padding(.vertical, 15)
            .frame(minHeight: 54).contentShape(Rectangle())
    }
}

struct ToolsView: View {
    var isTabRoot = false
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HydrationEntry.date, order: .reverse) private var hydrationEntries: [HydrationEntry]
    @Query(sort: \JumpRopeEntry.date, order: .reverse) private var jumpRopeEntries: [JumpRopeEntry]
    @Query(sort: \SedentarySession.startedAt, order: .reverse) private var sedentarySessions: [SedentarySession]
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var bodyMeasurements: [BodyMeasurement]

    @AppStorage("toolsAgentV2Expanded") private var isAgentExpanded = true
    @AppStorage("toolsLastWaterAmountML") private var lastWaterAmount = 250
    @State private var agentInput = ""
    @State private var agentMessages: [WellnessAgentMessage] = []
    @State private var agentSource: WellnessAgentSource = .local
    @State private var isAgentThinking = false
    @State private var agentStatusNote: String?
    @State private var pendingAgentCommand: WellnessToolCommand?
    @State private var showsAgentConfirmation = false
    @State private var showsWaterEntry = false
    @State private var showsJumpRopeEntry = false
    @State private var showsSedentaryEntry = false
    @State private var showsWeightEntry = false
    @State private var lastResult: WellnessToolResult?
    @State private var errorMessage: String?

    private var summary: WellnessToolSummary {
        WellnessToolService.todaySummary(
            on: .now,
            hydrationEntries: hydrationEntries,
            jumpRopeEntries: jumpRopeEntries,
            sedentarySessions: sedentarySessions
        )
    }

    private var activeSedentarySession: SedentarySession? {
        sedentarySessions.first(where: { $0.endedAt == nil })
    }

    private var latestWeightKg: Double? {
        BodyMeasurementService.dailyRepresentativeWeights(from: bodyMeasurements).last?.weightKg
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                SprintPageHeader(title: "记录工具", icon: "square.grid.2x2")
                agentCard

                SprintSectionHeading(title: "快速记录", icon: "plus.circle")
                quickToolsGrid

                todayCard

                if !recentActivities.isEmpty {
                    SprintSectionHeading(title: "最近操作", icon: "clock.arrow.circlepath")
                    recentActivityCard
                }

                if let lastResult {
                    resultCard(lastResult)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .sprintPage()
        .toolbar(isTabRoot ? .hidden : .visible, for: .navigationBar)
        .navigationTitle("记录工具").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsWaterEntry) {
            WaterQuickEntrySheet(initialAmount: lastWaterAmount) { amount, date in
                lastWaterAmount = amount
                execute(.recordWater(milliliters: amount, at: date))
            }
        }
        .sheet(isPresented: $showsJumpRopeEntry) {
            JumpRopeQuickEntrySheet { input in
                do {
                    lastResult = try WellnessToolService.recordJumpRope(
                        count: input.count, activeDurationSeconds: input.activeDurationSeconds,
                        elapsedDurationSeconds: input.elapsedDurationSeconds, at: input.date,
                        totalSetCount: input.totalSetCount, recordedTimeKnown: input.recordedTimeKnown,
                        in: modelContext
                    )
                } catch { errorMessage = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showsSedentaryEntry) {
            SedentaryQuickEntrySheet(activeSession: activeSedentarySession) { command in
                execute(command)
            }
        }
        .sheet(isPresented: $showsWeightEntry) {
            QuickBodyWeightEntryView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.light)
                .tint(AppTheme.ink)
        }
        .sheet(isPresented: $showsAgentConfirmation, onDismiss: {
            pendingAgentCommand = nil
        }) {
            if let pendingAgentCommand {
                AgentToolConfirmationSheet(command: pendingAgentCommand) {
                    execute(pendingAgentCommand, appendToConversation: true)
                    agentInput = ""
                }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .accessibilityIdentifier("工具中心")
    }

    private var agentCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isAgentExpanded.toggle() }
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.accent)
                        Image(systemName: "sparkles")
                            .font(.headline.bold())
                            .foregroundStyle(.black)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("记一笔")
                            .font(.headline.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(agentContextLine)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()
                    Text(displayedAgentSource.displayName)
                        .font(.caption2.bold())
                        .foregroundStyle(agentSourceTint)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 28)
                        .background(agentSourceTint.opacity(0.12), in: Capsule())
                        .accessibilityIdentifier("Agent状态")
                    Image(systemName: isAgentExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 24, height: 44)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("展开Agent工作台")

            if isAgentExpanded {
                Divider().overlay(AppTheme.line).padding(.vertical, 14)

                VStack(alignment: .leading, spacing: 10) {
                    if agentMessages.isEmpty {
                        agentBubble(WellnessAgentMessage(
                            role: .assistant,
                            content: "说出喝水、跳绳或久坐记录，确认后写入。"
                        ))
                    } else {
                        ForEach(agentMessages.suffix(6)) { message in
                            agentBubble(message)
                        }
                    }

                    if isAgentThinking {
                        HStack(spacing: 8) {
                            ProgressView().tint(AppTheme.ink)
                            Text("正在理解你的意思…")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 38)
                        .background(AppTheme.elevatedSurface, in: Capsule())
                        .accessibilityIdentifier("Agent思考中")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("Agent对话")

                HStack(spacing: 10) {
                    TextField("说一句，例如：刚喝了 300 ml", text: $agentInput, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.send)
                        .onSubmit(interpretAgentInput)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("Agent输入")

                    Button(action: interpretAgentInput) {
                        Image(systemName: "arrow.up")
                            .font(.body.bold())
                            .foregroundStyle(.black)
                            .frame(width: 52, height: 52)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(agentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAgentThinking)
                    .opacity(agentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAgentThinking ? 0.45 : 1)
                    .accessibilityLabel("解析工具请求")
                    .accessibilityIdentifier("Agent发送")
                }
                .padding(.top, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        agentExample(label: "+250 ml", request: "喝水 250 ml")
                        agentExample(label: "跳绳 1200", request: "跳绳 1200 个")
                        agentExample(
                            label: activeSedentarySession == nil ? "开始久坐" : "结束久坐",
                            request: activeSedentarySession == nil ? "开始久坐" : "结束久坐"
                        )
                        agentExample(label: "查看今天", request: "今天喝水跳绳久坐各多少")
                    }
                }
                .padding(.top, 10)

                if let agentStatusNote {
                    Label(agentStatusNote, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                        .accessibilityIdentifier("Agent状态说明")
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { isAgentExpanded = true }
                } label: {
                    HStack {
                        Text("说出记录或查询")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Image(systemName: "waveform")
                            .foregroundStyle(AppTheme.ink)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .accessibilityIdentifier("打开Agent输入")
            }
        }
        .cardSurface(padding: 16, cornerRadius: 22)
    }

    private var displayedAgentSource: WellnessAgentSource {
        if agentMessages.isEmpty, WellnessAgentConfiguration.endpointURL != nil {
            return .deepSeek
        }
        return agentSource
    }

    private var agentSourceTint: Color {
        switch displayedAgentSource {
        case .deepSeek: return AppTheme.ink
        case .local: return AppTheme.ink
        case .localFallback: return AppTheme.orange
        }
    }

    private var agentContextLine: String {
        if let activeSedentarySession {
            return "久坐计时从 \(activeSedentarySession.startedAt.formatted(date: .omitted, time: .shortened)) 开始"
        }
        if summary.jumpRopeCount != nil && summary.waterMilliliters + (summary.jumpRopeCount ?? 0) + summary.sedentaryMinutes == 0 {
            return "自然语言记录 · 支持离线理解"
        }
        return "今天：\(summary.waterMilliliters) ml · \(summary.jumpRopeCount.map { "\($0) 个" } ?? "跳绳次数未知") · 久坐 \(summary.sedentaryMinutes) 分"
    }

    private func agentBubble(_ message: WellnessAgentMessage) -> some View {
        Text(message.content)
            .font(.subheadline)
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                message.role == .user ? AppTheme.accent : AppTheme.elevatedSurface,
                in: RoundedRectangle(cornerRadius: 15)
            )
            .frame(maxWidth: 285, alignment: message.role == .user ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func agentExample(label: String, request: String) -> some View {
        Button(label) {
            interpretAgentText(request)
        }
        .font(.caption2.bold())
        .foregroundStyle(AppTheme.ink)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(AppTheme.accent.opacity(0.09), in: Capsule())
        .buttonStyle(.plain)
        .accessibilityLabel(request)
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今天")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text("今日记录")
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer()
                if let activeSedentarySession {
                    Label("计时中", systemImage: "timer")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.orange)
                        .accessibilityIdentifier("久坐计时中")
                        .accessibilityValue(activeSedentarySession.startedAt.formatted(date: .omitted, time: .shortened))
                }
            }

            HStack(spacing: 0) {
                summaryMetric("\(summary.waterMilliliters)", unit: "ml", label: "喝水")
                summaryMetric(summary.jumpRopeCount.map { String($0) } ?? "未知", unit: "个", label: "跳绳")
                summaryMetric("\(summary.sedentaryMinutes)", unit: "分", label: "久坐")
            }
        }
        .cardSurface(padding: 16, cornerRadius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("工具今日摘要")
    }

    private func summaryMetric(_ value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.black).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                Text(unit)
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.line).frame(width: 1, height: 32)
        }
    }

    private var quickToolsGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickToolCard(
                    icon: "drop.fill",
                    title: "+\(lastWaterAmount) ml",
                    tint: AppTheme.accent,
                    identifier: "记录喝水",
                    action: {
                        pendingAgentCommand = .recordWater(milliliters: lastWaterAmount, at: .now)
                        showsAgentConfirmation = true
                    }
                )
                quickToolCard(
                    icon: "figure.jumprope",
                    title: "跳绳",
                    tint: AppTheme.accent,
                    identifier: "记录跳绳",
                    action: { showsJumpRopeEntry = true }
                )
                quickToolCard(
                    icon: activeSedentarySession == nil ? "chair.lounge.fill" : "timer",
                    title: activeSedentarySession == nil ? "久坐" : "结束计时",
                    tint: AppTheme.accent,
                    identifier: "记录久坐",
                    action: { showsSedentaryEntry = true }
                )
                quickToolCard(
                    icon: "scalemass.fill",
                    title: "体重",
                    tint: AppTheme.accent,
                    identifier: "工具记录体重",
                    action: { showsWeightEntry = true }
                )
            }
            .padding(.vertical, 2)
        }
    }

    private func quickToolCard(
        icon: String,
        title: String,
        tint: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var recentActivities: [ToolActivityItem] {
        let hydration = hydrationEntries.map {
            ToolActivityItem(
                id: "water-\($0.id)",
                title: "喝水",
                detail: "\($0.milliliters) ml",
                date: $0.date,
                systemImage: "drop.fill",
                tint: .cyan,
                undoAction: .deleteHydration($0.id)
            )
        }
        let jumps = jumpRopeEntries.map {
            ToolActivityItem(
                id: "jump-\($0.id)",
                title: "跳绳",
                detail: $0.displaySummary,
                date: $0.date,
                systemImage: "figure.jumprope",
                tint: AppTheme.accent,
                undoAction: .deleteJumpRope($0.id),
                dateLabel: $0.recordedTimeKnown == false
                    ? "\($0.trainingLocalDay ?? TrainingLocalDate.key($0.date)) · 时间未知" : nil
            )
        }
        let sedentary = sedentarySessions.compactMap { session -> ToolActivityItem? in
            guard session.endedAt != nil else { return nil }
            return ToolActivityItem(
                id: "sedentary-\(session.id)",
                title: "久坐",
                detail: "\(max(1, session.durationSeconds / 60)) 分钟",
                date: session.endedAt ?? session.startedAt,
                systemImage: "chair.lounge.fill",
                tint: AppTheme.orange,
                undoAction: .deleteSedentary(session.id)
            )
        }
        return (hydration + jumps + sedentary).sorted { $0.date > $1.date }.prefix(5).map { $0 }
    }

    private var recentActivityCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(recentActivities.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(item.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                        Text(item.dateLabel ?? item.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Text(item.detail)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                    Button {
                        undo(item.undoAction)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityLabel("撤销\(item.title)记录")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 64)

                if index < recentActivities.count - 1 {
                    Divider().overlay(AppTheme.line).padding(.leading, 62)
                }
            }
        }
        .cardSurface(padding: 0, cornerRadius: 18)
    }

    private func resultCard(_ result: WellnessToolResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.ink)
            Text(result.message)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
            Spacer()
            if let undoAction = result.undoAction {
                Button("撤销") { undo(undoAction) }
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
            }
        }
        .cardSurface(padding: 14, cornerRadius: 16)
        .accessibilityIdentifier("工具操作结果")
    }

    private func interpretAgentInput() {
        interpretAgentText(agentInput)
    }

    private func interpretAgentText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAgentThinking else { return }

        let history = agentMessages
        agentMessages.append(WellnessAgentMessage(role: .user, content: trimmed))
        agentInput = ""
        isAgentThinking = true
        agentStatusNote = nil

        let context = WellnessAgentContext(
            localTimeISO: ISO8601DateFormatter().string(from: .now),
            waterMilliliters: summary.waterMilliliters,
            jumpRopeCount: summary.jumpRopeCount,
            sedentaryMinutes: summary.sedentaryMinutes,
            activeSedentaryStartedAt: activeSedentarySession.map {
                ISO8601DateFormatter().string(from: $0.startedAt)
            },
            latestWeightKg: latestWeightKg
        )
        let remote = WellnessAgentConfiguration.endpointURL.map {
            RemoteWellnessAgentGateway(endpoint: $0)
        }
        let agent = HybridWellnessAgent(remote: remote)

        Task {
            let turn = await agent.interpret(
                userMessage: trimmed,
                history: history,
                context: context
            )
            isAgentThinking = false
            agentSource = turn.source
            agentMessages.append(WellnessAgentMessage(role: .assistant, content: turn.reply))

            switch turn.source {
            case .deepSeek:
                agentStatusNote = "由 DeepSeek 理解；工具参数仍由本机校验。"
            case .local:
                agentStatusNote = "未配置线上代理，当前由本机离线理解。"
            case .localFallback:
                agentStatusNote = "DeepSeek 暂时不可用，已由本机接管。"
            }

            guard let command = turn.command else { return }
            if command.requiresConfirmation {
                pendingAgentCommand = command
                showsAgentConfirmation = true
            } else {
                execute(command, appendToConversation: true)
            }
        }
    }

    private func execute(_ command: WellnessToolCommand, appendToConversation: Bool = false) {
        do {
            let result = try WellnessToolService.execute(command, in: modelContext)
            lastResult = result
            if appendToConversation {
                agentMessages.append(WellnessAgentMessage(role: .assistant, content: result.message))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ action: WellnessToolUndoAction) {
        do {
            try WellnessToolService.undo(action, in: modelContext)
            lastResult = nil
            agentMessages.append(WellnessAgentMessage(role: .assistant, content: "已撤销刚才的记录。"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ToolActivityItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let date: Date
    let systemImage: String
    let tint: Color
    let undoAction: WellnessToolUndoAction
    var dateLabel: String? = nil
}

private struct AgentToolConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let command: WellnessToolCommand
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
              VStack(alignment: .leading, spacing: 20) {
                SprintIcon(systemName: "checkmark.shield", size: 64, prominent: true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(command.previewTitle)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(command.previewDetail)
                        .font(.title3.weight(.black).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                    Text("确认后写入健康记录。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .cardSurface(padding: 18, cornerRadius: 20)

                Button("确认执行") {
                    onConfirm()
                    dismiss()
                }
                .neonButtonStyle()
                .accessibilityIdentifier("Agent确认执行")
              }
              .padding(20)
            }
            .sprintPage()
            .navigationTitle("执行前确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
        .tint(AppTheme.ink)
        .accessibilityIdentifier("Agent工具确认卡")
    }
}

struct WaterQuickEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int
    @State private var date = Date.now
    let onSave: (Int, Date) -> Void

    init(initialAmount: Int, initialDate: Date = .now, onSave: @escaping (Int, Date) -> Void) {
        _amount = State(initialValue: [200, 250, 500].contains(initialAmount) ? initialAmount : 250)
        _date = State(initialValue: initialDate)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
              VStack(alignment: .leading, spacing: 22) {
                SprintPageHeader(title: "喝了多少？", icon: "drop")

                HStack(spacing: 10) {
                    ForEach([200, 250, 500], id: \.self) { value in
                        Button("\(value) ml") { amount = value }
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                amount == value ? AppTheme.accent : AppTheme.elevatedSurface,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("喝水\(value)")
                    }
                }

                Stepper("\(amount) ml", value: $amount, in: 50...5_000, step: 50)
                    .font(.headline.monospacedDigit())
                    .padding(14)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))

                DatePicker("记录时间", selection: $date, in: ...Date.now)
                Button("保存喝水记录") {
                    onSave(amount, date)
                    dismiss()
                }
                .neonButtonStyle()
                .accessibilityIdentifier("保存喝水记录")
              }
              .padding(20)
            }
            .sprintPage()
            .navigationTitle("喝水")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
        .tint(AppTheme.ink)
    }
}

struct JumpRopeQuickEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var countText = ""
    @State private var setCountText = ""
    @State private var activeMinutes = 10
    @State private var elapsedMinutes = 15
    @State private var includesDuration = true
    @State private var date = Date.now
    @State private var recordedTimeKnown: Bool
    let onSave: (JumpRopeActualInput) -> Void

    init(initialDate: Date = .now, onSave: @escaping (JumpRopeActualInput) -> Void) {
        let sameDay = Calendar.current.isDateInToday(initialDate)
        let hasTime = sameDay && initialDate != Calendar.current.startOfDay(for: initialDate)
        _date = State(initialValue: initialDate)
        _recordedTimeKnown = State(initialValue: hasTime)
        self.onSave = onSave
    }

    private var parsedCount: Int? { Int(countText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var parsedSetCount: Int? { Int(setCountText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var countInputValid: Bool {
        countText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (parsedCount.map { (1...100_000).contains($0) } ?? false)
    }
    private var setCountInputValid: Bool {
        setCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (parsedSetCount.map { (1...10_000).contains($0) } ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("未记录次数（可留空）", text: $countText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("跳绳-次数")
                    Text(parsedCount == nil ? "次数未知，不会按时长推算。" : "次数以本人实际记录为准。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    if !countInputValid { Text("次数需为 1 到 100000 的整数，或留空。 ").foregroundStyle(.red) }
                    TextField("总组数（可留空）", text: $setCountText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("跳绳-总组数")
                    if !setCountInputValid { Text("组数需为 1 到 10000 的整数，或留空。 ").foregroundStyle(.red) }
                    Toggle("记录时长", isOn: $includesDuration)
                    if includesDuration {
                        Stepper("有效跳绳：\(activeMinutes) 分钟", value: $activeMinutes, in: 1...1_440)
                        Stepper("含休息总时长：\(elapsedMinutes) 分钟", value: $elapsedMinutes, in: 1...1_440)
                        if activeMinutes > elapsedMinutes {
                            Text("有效时长不能超过总时长").foregroundStyle(.red)
                        }
                    }
                } header: {
                    Label("跳绳", systemImage: "figure.jumprope")
                }
                Section {
                    Toggle("记录具体完成时间", isOn: $recordedTimeKnown)
                        .accessibilityIdentifier("跳绳-记录具体时间")
                    if recordedTimeKnown {
                        DatePicker("完成时间", selection: $date, in: ...Date.now)
                            .accessibilityIdentifier("跳绳-完成时间")
                    } else {
                        DatePicker("训练日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                            .accessibilityIdentifier("跳绳-训练日期")
                    }
                } header: {
                    Label("时间", systemImage: "clock")
                }
                Section {
                    Button("保存跳绳记录") {
                        onSave(JumpRopeActualInput(count: parsedCount, totalSetCount: parsedSetCount,
                            activeDurationSeconds: includesDuration ? activeMinutes * 60 : nil,
                            elapsedDurationSeconds: includesDuration ? elapsedMinutes * 60 : nil,
                            date: date, recordedTimeKnown: recordedTimeKnown))
                        dismiss()
                    }
                    .buttonStyle(SprintPrimaryButtonStyle())
                    .accessibilityIdentifier("保存跳绳记录")
                    .disabled(!countInputValid || !setCountInputValid || (includesDuration && activeMinutes > elapsedMinutes)
                              || (!includesDuration && parsedCount == nil))
                }
            }
            .scrollContentBackground(.hidden)
            .sprintPage()
            .navigationTitle("跳绳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { KeyboardDismissal.dismiss() }
                        .accessibilityIdentifier("跳绳-收起键盘")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
        .tint(AppTheme.ink)
    }
}

private struct SedentaryQuickEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let activeSession: SedentarySession?
    let onCommand: (WellnessToolCommand) -> Void
    @State private var startedAt = Date.now.addingTimeInterval(-3_600)
    @State private var durationMinutes = 60

    var body: some View {
        NavigationStack {
            Form {
                if let activeSession {
                    Section("正在计时") {
                        LabeledContent("开始", value: activeSession.startedAt.formatted(date: .omitted, time: .shortened))
                        Button("结束并记录") {
                            onCommand(.stopSedentary(at: .now))
                            dismiss()
                        }
                        .buttonStyle(SprintPrimaryButtonStyle())
                        .accessibilityIdentifier("结束久坐计时")
                    }
                } else {
                    Section("久坐计时") {
                        Text("可随时回来结束。同一时间只保留一段计时。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Button("开始计时") {
                            onCommand(.startSedentary(at: .now))
                            dismiss()
                        }
                        .buttonStyle(SprintPrimaryButtonStyle())
                        .accessibilityIdentifier("开始久坐计时")
                    }
                }

                Section("补录已经结束的久坐") {
                    DatePicker("开始时间", selection: $startedAt, in: ...Date.now)
                    Stepper("时长：\(durationMinutes) 分钟", value: $durationMinutes, in: 1...1_440, step: 5)
                    Button("保存补录") {
                        onCommand(.recordSedentary(startedAt: startedAt, durationMinutes: durationMinutes))
                        dismiss()
                    }
                    .buttonStyle(SprintPrimaryButtonStyle())
                    .accessibilityIdentifier("保存久坐补录")
                }
            }
            .scrollContentBackground(.hidden)
            .sprintPage()
            .navigationTitle("久坐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
        .tint(AppTheme.ink)
    }
}
