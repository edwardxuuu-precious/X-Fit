import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HistoricalWorkoutImportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showImporter = false
    @State private var pendingData: Data?
    @State private var preview: HistoricalCSVPreview?
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: "HISTORY SYNC",
                    title: "批量同步训练记录"
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label("适合过去几周的训练记录", systemImage: "calendar.badge.plus")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("我可以把你的截图、表格或其他 App 导出整理成这个 CSV。导入时按动作名称匹配现有动作；缺失动作会创建为自定义动作。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("同一个 session_id 再次导入会跳过，不会产生重复训练。")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                .cardSurface()

                SectionHeader(title: "CSV 必需字段")
                Text("session_id, date, workout, exercise, set, weight_kg, reps")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .cardSurface()

                SectionHeader(title: "可选字段")
                Text("duration_minutes, workout_notes, muscle_group, equipment, rir, exercise_notes")
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.secondaryText)
                    .textSelection(.enabled)
                    .cardSurface()

                if let preview {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("导入预检")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                        HStack(spacing: 10) {
                            previewMetric("\(preview.sessions)", label: "训练")
                            previewMetric("\(preview.exercises)", label: "动作")
                            previewMetric("\(preview.sets)", label: "完成组")
                        }
                        if preview.duplicateSessions > 0 {
                            Label(
                                "\(preview.duplicateSessions) 场已导入，将自动跳过",
                                systemImage: "arrow.trianglehead.2.clockwise"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                        Button {
                            importPendingData()
                        } label: {
                            Label("确认同步记录", systemImage: "square.and.arrow.down.fill")
                                .neonButtonStyle()
                        }
                    }
                    .cardSurface()
                }

                Button {
                    showImporter = true
                } label: {
                    Label(
                        pendingData == nil ? "选择历史 CSV" : "重新选择 CSV",
                        systemImage: "doc.badge.plus"
                    )
                    .font(.headline.bold())
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.accent.opacity(0.45), lineWidth: 1))
                }

                NavigationLink(destination: HistoricalWorkoutEntryView()) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("逐场手动补录")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .cardSurface(padding: 14, cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .screenBackground()
        .navigationTitle("历史同步")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleSelection(result)
        }
        .alert("同步完成", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("无法同步", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func previewMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func handleSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let data = try DataExportService.loadBackupData(from: url)
            preview = try HistoricalWorkoutCSVService.preview(data, in: modelContext)
            pendingData = data
        } catch {
            pendingData = nil
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func importPendingData() {
        guard let pendingData else { return }
        do {
            let summary = try HistoricalWorkoutCSVService.importCSV(pendingData, into: modelContext)
            resultMessage = "已同步 \(summary.importedSessions) 场训练、\(summary.importedSets) 个完成组；新建 \(summary.createdExercises) 个动作，跳过 \(summary.skippedSessions) 场重复记录。"
            self.pendingData = nil
            preview = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
