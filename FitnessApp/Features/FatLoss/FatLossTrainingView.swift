import SwiftData
import SwiftUI

struct FatLossTrainingView: View {
    @Environment(\.modelContext) private var context
    let program: FatLossProgram
    @State private var startDate = Date.now
    @State private var importDays = 14
    @State private var preview: [ProgramImportPreview] = []
    @State private var showsImport = false
    @State private var skipConflicts = false
    @State private var errorMessage: String?
    @State private var notice: String?
    var body: some View {
        List {
            Section {
                Text("各动作从 2 个工作组、约 3 次余力开始。工作重量按当天状态选择，前两周以稳定执行和恢复为主。")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
            ForEach(FatLossCatalog.workouts) { workout in
                Section(workout.title) {
                    Text(workout.guidance).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    ForEach(workout.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(exercise.name).font(.headline)
                            Text("\(exercise.sets) 组 × \(exercise.repsLower)–\(exercise.repsUpper) · 休息 \(exercise.restSeconds) 秒")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                            Text(exercise.note).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section("可选活动") {
                Text(FatLossCatalog.coordinationGuidance)
                Text(FatLossCatalog.jumpRopeGuidance)
                NavigationLink("记录跳绳与饮水", destination: ToolsView())
            }
            Section("手动导入日程") {
                DatePicker("开始日期", selection: $startDate, in: program.startDate...FatLossCalendar.adding(-1, to: program.endDate), displayedComponents: .date)
                Picker("导入范围", selection: $importDays) {
                    Text("接下来 14 天").tag(14)
                    Text("剩余整个周期").tag(program.executionDays)
                }
                Button("预览训练日程") {
                    do {
                        preview = try FatLossService.importPreview(program: program, from: startDate, days: importDays, in: context)
                        skipConflicts = false; showsImport = true
                    } catch { errorMessage = error.localizedDescription }
                }.accessibilityIdentifier("预览减脂训练导入")
                if let notice { Text(notice).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            }
        }.scrollContentBackground(.hidden).screenBackground().fatLossCalendar().navigationTitle("全身训练计划").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onAppear { startDate = min(max(FatLossCalendar.day(.now), program.startDate), FatLossCalendar.adding(-1, to: program.endDate)) }
            .sheet(isPresented: $showsImport) { importSheet.preferredColorScheme(.dark) }
            .fatLossError($errorMessage)
    }
    private var importSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("已有训练保留；重复日期跳过。")
                        .font(.subheadline)
                    if preview.contains(where: { !$0.conflictingNames.isEmpty }) {
                        Toggle("跳过冲突日期，导入其余日期", isOn: $skipConflicts)
                        Text("未选择时请取消并调整日期。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                ForEach(preview) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(FatLossCalendar.label(item.date)) · \(item.workout.title)").font(.headline)
                        if item.alreadyImported { Text("已导入 · 将跳过").foregroundStyle(AppTheme.secondaryText) }
                        else if !item.conflictingNames.isEmpty {
                            Text("已有：\(item.conflictingNames.joined(separator: "、"))")
                                .foregroundStyle(AppTheme.orange)
                        } else { Text("待导入").foregroundStyle(AppTheme.secondaryText) }
                    }.font(.caption)
                }
            }.scrollContentBackground(.hidden).screenBackground().fatLossCalendar().navigationTitle("导入前预览")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showsImport = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确认导入") {
                            do {
                                let count = try FatLossService.importWorkouts(program: program, from: startDate, days: importDays, conflictPolicy: skipConflicts ? .skipConflicts : .reject, in: context)
                                notice = "已导入 \(count) 次训练；已有日程保留。"; showsImport = false
                            } catch { errorMessage = error.localizedDescription }
                        }.disabled(preview.contains { !$0.conflictingNames.isEmpty } && !skipConflicts)
                            .accessibilityIdentifier("确认导入减脂训练")
                    }
                }
        }
    }
}
