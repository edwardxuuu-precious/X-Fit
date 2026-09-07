import SwiftData
import SwiftUI

private enum TerminologyReviewFilter: String, CaseIterable, Identifiable {
    case pending
    case reviewed
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待审核"
        case .reviewed: return "已处理"
        case .all: return "全部"
        }
    }
}

struct ExerciseTerminologyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var setLogs: [SetLog]

    @State private var filter: TerminologyReviewFilter = .pending
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var activeExercises: [Exercise] {
        exercises.filter { !$0.isArchived }
    }

    private var visibleExercises: [Exercise] {
        activeExercises
            .filter { exercise in
                switch filter {
                case .pending: exercise.terminologyDecision == .pending
                case .reviewed: exercise.terminologyDecision != .pending
                case .all: true
                }
            }
            .filter { exercise in
                guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return true
                }
                let text = [
                    exercise.name,
                    exercise.terminologyStandardNameZH ?? "",
                    exercise.terminologyStandardNameEN ?? "",
                    exercise.muscleGroup,
                    exercise.equipment
                ].joined(separator: " ")
                return text.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { lhs, rhs in
                let left = reviewPriority(lhs)
                let right = reviewPriority(rhs)
                if left != right { return left < right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: nil, title: "动作名称审核")

                boundaryCard
                summaryGrid

                Picker("审核范围", selection: $filter) {
                    ForEach(TerminologyReviewFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if visibleExercises.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "当前没有动作" : "没有匹配动作",
                        systemImage: "checkmark.seal",
                        description: Text(searchText.isEmpty ? "可以切换到“全部”查看动作库。" : "请尝试其他中英文名称。")
                    )
                    .foregroundStyle(.white)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleExercises) { exercise in
                            NavigationLink {
                                ExerciseTerminologyDetailView(exercise: exercise)
                            } label: {
                                terminologyRow(exercise)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("terminology-row-\(exercise.name)")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $searchText, prompt: "搜索中文、英文、肌群或器械")
        .task {
            do {
                try ExerciseTerminologyService.stageCatalogCandidates(in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("无法准备审核数据", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var boundaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("本地候选库已启用", systemImage: "checkmark.shield.fill")
                .font(.headline.bold())
                .foregroundStyle(.white)
            Text("接受候选只会批准 canonical 身份与中英文显示名，不会改写已完成训练的原始名称，也不会直接合并动作 UUID、PR 或上次重量。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            HStack(spacing: 8) {
                Label("AI API 未连接", systemImage: "network.slash")
                Text("·")
                Text("DeepSeek 需通过 HTTPS 代理接入")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.orange)
        }
        .cardSurface()
    }

    private var summaryGrid: some View {
        let pending = activeExercises.filter { $0.terminologyDecision == .pending }.count
        let accepted = activeExercises.filter { $0.terminologyDecision == .accepted }.count
        let unresolved = activeExercises.filter {
            $0.terminologyDecision == .pending && $0.terminologyReviewStatus == .unresolved
        }.count
        let impactedSets = setLogs.filter { log in
            log.isCompleted
                && activeExercises.contains(where: {
                    $0.id == log.exerciseID && $0.terminologyDecision == .pending
                })
        }.count

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricCard(title: "待审核动作", value: "\(pending)", detail: "逐项人工确认", systemImage: "checklist")
            MetricCard(title: "未唯一解析", value: "\(unresolved)", detail: "需照片或器械信息", systemImage: "questionmark.diamond.fill", tint: AppTheme.orange)
            MetricCard(title: "已接受候选", value: "\(accepted)", detail: "历史原名仍保留", systemImage: "checkmark.seal.fill")
            MetricCard(title: "涉及完成组", value: "\(impactedSets)", detail: "确认前不合并趋势", systemImage: "clock.arrow.circlepath", tint: AppTheme.purple)
        }
    }

    private func terminologyRow(_ exercise: Exercise) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon(exercise))
                .font(.subheadline.bold())
                .foregroundStyle(statusColor(exercise))
                .frame(width: 38, height: 38)
                .background(statusColor(exercise).opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(exercise.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Text(exercise.terminologyDecision.title)
                        .font(.caption2.bold())
                        .foregroundStyle(statusColor(exercise))
                }
                if let standardZH = exercise.terminologyStandardNameZH, standardZH != exercise.name {
                    Text("候选：\(standardZH)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                if let standardEN = exercise.terminologyStandardNameEN, !standardEN.isEmpty {
                    Text(standardEN)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                HStack(spacing: 6) {
                    Text(exercise.terminologyReviewStatus?.title ?? "待生成候选")
                    Text("·")
                    Text("\(exercise.muscleGroup) / \(exercise.equipment)")
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.top, 12)
        }
        .cardSurface(padding: 14, cornerRadius: 16)
    }

    private func reviewPriority(_ exercise: Exercise) -> Int {
        guard exercise.terminologyDecision == .pending else { return 10 }
        switch exercise.terminologyReviewStatus {
        case .unresolved: return 0
        case .mergeReview: return 1
        case .variantReview: return 2
        case .approvalReady: return 3
        case nil: return 4
        }
    }

    private func statusColor(_ exercise: Exercise) -> Color {
        switch exercise.terminologyDecision {
        case .accepted: return AppTheme.accent
        case .rejected: return AppTheme.secondaryText
        case .pending:
            switch exercise.terminologyReviewStatus {
            case .unresolved: return AppTheme.orange
            case .mergeReview: return AppTheme.purple
            case .variantReview: return .yellow
            case .approvalReady, nil: return AppTheme.accent
            }
        }
    }

    private func statusIcon(_ exercise: Exercise) -> String {
        switch exercise.terminologyDecision {
        case .accepted: return "checkmark.seal.fill"
        case .rejected: return "equal.circle.fill"
        case .pending:
            switch exercise.terminologyReviewStatus {
            case .unresolved: return "questionmark.diamond.fill"
            case .mergeReview: return "arrow.triangle.merge"
            case .variantReview: return "slider.horizontal.3"
            case .approvalReady, nil: return "text.badge.checkmark"
            }
        }
    }
}

private struct ExerciseTerminologyDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]
    @Query private var setLogs: [SetLog]

    let exercise: Exercise

    @State private var pendingAction: ExerciseTerminologyDecision?
    @State private var showResetConfirmation = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private var completedSetCount: Int {
        setLogs.filter { $0.exerciseID == exercise.id && $0.isCompleted }.count
    }

    private var mergePeers: [Exercise] {
        guard let group = exercise.terminologyMergeGroup, !group.isEmpty else { return [] }
        return exercises.filter { $0.id != exercise.id && $0.terminologyMergeGroup == group }
    }

    private var hasAcceptableCandidate: Bool {
        !(exercise.terminologyCanonicalID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(exercise.terminologyStandardNameZH ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(exercise.terminologyStandardNameEN ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: nil, title: exercise.name)

                rawIdentityCard
                candidateCard
                impactCard
                actionCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(actionTitle(pendingAction), role: pendingAction == .rejected ? .destructive : nil) {
                    apply(pendingAction)
                }
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog("撤销这次审核？", isPresented: $showResetConfirmation) {
            Button("恢复为待审核") { resetDecision() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只撤销术语审核决定，不会修改训练记录。")
        }
        .alert("完成", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
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

    private var rawIdentityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("当前原始记录", systemImage: "lock.shield.fill")
                .font(.headline.bold())
                .foregroundStyle(.white)
            detailRow("名称", exercise.name)
            detailRow("肌群", exercise.muscleGroup)
            detailRow("器械", exercise.equipment)
            Text("接受候选后，这三个原始字段和已完成训练快照仍保持不变。")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface()
    }

    private var candidateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("标准名称候选", systemImage: "character.book.closed.fill")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text(exercise.terminologyConfidence.map { "\($0.title)置信度" } ?? "未评级")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.accent)
            }
            detailRow("中文", exercise.terminologyStandardNameZH ?? "尚无候选")
            detailRow("英文", exercise.terminologyStandardNameEN.orPlaceholder)
            detailRow("Canonical", exercise.terminologyCanonicalID.orPlaceholder)
            detailRow("状态", exercise.terminologyReviewStatus?.title ?? "待生成候选")
            if let note = exercise.terminologyReviewNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.orange)
            }
        }
        .cardSurface()
    }

    private var impactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("历史影响", systemImage: "clock.arrow.circlepath")
                .font(.headline.bold())
                .foregroundStyle(.white)
            detailRow("当前完成组", "\(completedSetCount)")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("terminology-completed-set-row")
            if !mergePeers.isEmpty {
                detailRow("同组候选", mergePeers.map(\.name).joined(separator: "、"))
            }
            Text(mergePeers.isEmpty
                ? "批准后只增加可追溯的标准身份；不会改写这 \(completedSetCount) 个完成组。"
                : "确认后会同时审核同组候选，但仍不合并动作 UUID。只有后续指标层显式采用已批准 canonical ID 时，趋势才可安全归组。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface()
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            if exercise.terminologyDecision == .pending {
                Button {
                    pendingAction = .accepted
                } label: {
                    Text(hasAcceptableCandidate
                        ? (mergePeers.isEmpty ? "接受标准名称候选" : "确认同一动作并接受候选")
                        : "信息不足，暂不可接受")
                        .neonButtonStyle()
                }
                .buttonStyle(.plain)
                .disabled(!hasAcceptableCandidate)
                .opacity(hasAcceptableCandidate ? 1 : 0.55)
                .accessibilityIdentifier("terminology-accept-button")

                Button {
                    pendingAction = .rejected
                } label: {
                    Text("保留当前名称，不采用候选")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.orange)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTouchTarget)
                        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 13))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("terminology-reject-button")
            } else {
                HStack {
                    Label(exercise.terminologyDecision.title, systemImage: exercise.terminologyDecision == .accepted ? "checkmark.seal.fill" : "equal.circle.fill")
                        .font(.headline.bold())
                        .foregroundStyle(exercise.terminologyDecision == .accepted ? AppTheme.accent : AppTheme.secondaryText)
                    Spacer()
                    if let date = exercise.terminologyReviewedAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                Button { showResetConfirmation = true } label: {
                    Text("撤销审核决定")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTouchTarget)
                        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 13))
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("terminology-reset-button")
            }
        }
        .cardSurface()
    }

    private var confirmationTitle: String {
        guard let pendingAction else { return "确认审核决定？" }
        return pendingAction == .accepted ? "接受这组候选？" : "保留当前名称？"
    }

    private var confirmationMessage: String {
        guard let pendingAction else { return "" }
        if pendingAction == .accepted {
            return mergePeers.isEmpty
                ? "只批准 canonical 身份与中英文候选，不改写历史名称、UUID、PR 或上次重量。"
                : "将同时批准 \(mergePeers.map(\.name).joined(separator: "、")) 的同一 canonical 候选，但不会直接合并 UUID、PR 或历史组。"
        }
        return mergePeers.isEmpty
            ? "当前名称继续作为唯一有效显示名，候选仍保留用于以后复核。"
            : "同组候选都会标记为保留当前名称，不会建立共享 canonical 身份。"
    }

    private func actionTitle(_ decision: ExerciseTerminologyDecision) -> String {
        decision == .accepted ? "确认接受" : "确认保留当前名称"
    }

    private func apply(_ decision: ExerciseTerminologyDecision) {
        do {
            if decision == .accepted {
                try ExerciseTerminologyService.accept(exercise, among: exercises, in: modelContext)
                resultMessage = "已保存审核决定；历史名称和训练数据未被修改。"
            } else {
                try ExerciseTerminologyService.reject(exercise, among: exercises, in: modelContext)
                resultMessage = "已保留当前名称；候选未被应用。"
            }
            pendingAction = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetDecision() {
        do {
            try ExerciseTerminologyService.reset(exercise, among: exercises, in: modelContext)
            resultMessage = "已恢复为待审核。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private extension Optional where Wrapped == String {
    var orPlaceholder: String {
        guard let value = self, !value.isEmpty else { return "尚无候选" }
        return value
    }
}
