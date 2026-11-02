import SwiftData
import SwiftUI

struct ConfirmedTrainingPlanImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let preview: ConfirmedTrainingPlanPreview
    let onImported: (ConfirmedTrainingPlanApplyResult) -> Void
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: SprintSectionHeading(title: "已确认计划 · 完整预览", icon: "checkmark.shield")) {
                    Text(preview.packet.snapshot.title).font(.headline)
                    Text(preview.packet.snapshot.code).font(.caption.monospaced())
                    Text("\(preview.packet.startLocalDay) — \(preview.packet.endLocalDay) · \(preview.packet.timeZoneIdentifier)")
                        .font(.caption)
                    Text("偏好 \(preview.packet.snapshot.preferenceRevisionCode)").font(.caption)
                    Text("\(preview.newScheduleCount) 项新日程；仅这一周，不覆盖旧训练，不更改长期偏好。")
                        .font(.subheadline)
                    Text("重量留空，由当天热身确定；以下为计划目标，不是实际完成记录。")
                        .font(.caption).foregroundStyle(AppTheme.orange)
                }
                if !preview.conflicts.isEmpty {
                    Section(header: SprintSectionHeading(title: "待处理 · 尚未写入", icon: "exclamationmark.triangle")) {
                        ForEach(preview.conflicts, id: \.self) { Text($0).foregroundStyle(AppTheme.orange) }
                    }
                }
                if let additions = preview.packet.catalogAdditions, !additions.isEmpty {
                    Section(header: SprintSectionHeading(title: "已确认动作", icon: "dumbbell")) {
                        Text("将新增 \(preview.newExerciseCount ?? 0) 个动作，与日程一起保存；失败一起回滚。不会恢复已归档同名动作或改写旧记录。")
                            .font(.subheadline).accessibilityIdentifier("已确认计划-新增动作说明")
                        ForEach(additions, id: \.id) { addition in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(addition.name).font(.subheadline.weight(.semibold))
                                Text("\(addition.equipment) · kg · \(addition.muscleGroup)")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        Text("器械及单位确认：\(preview.packet.catalogConfirmationReference ?? "")")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                ForEach(preview.packet.snapshot.strengthWorkouts) { workout in
                    Section(workout.title) {
                        Text(workout.guidance).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        ForEach(workout.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(exercise.name).font(.subheadline.weight(.semibold))
                                Text("\(exercise.equipment) · \(exercise.sets) 组\(exercise.unilateral ? " · 每侧" : "")")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                                ForEach(Array((exercise.plannedSets ?? []).enumerated()), id: \.offset) { index, plan in
                                    if let prescription = plan.prescription {
                                        Text("第 \(index + 1) 组 · \(prescription.summary)").font(.caption)
                                        if let cue = prescription.effortCue { Text(cue).font(.caption) }
                                    }
                                }
                                Text(exercise.note).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                ForEach(preview.packet.snapshot.cardioWorkouts) { cardio in
                    Section(cardio.title) {
                        Text(cardio.timing).font(.subheadline)
                        Text(cardio.intervals).font(.subheadline)
                        Text(cardio.guidance).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                Section(header: SprintSectionHeading(title: "恢复、替代与来源", icon: "arrow.triangle.2.circlepath")) {
                    Text(preview.packet.snapshot.progressionRule).font(.subheadline)
                    Text(preview.packet.snapshot.lowEnergyRule).font(.subheadline)
                    Text("确认来源：\(preview.packet.confirmationReference)").font(.caption)
                    DisclosureGroup("查看完整原方案") {
                        Text("原文保留当时的草案状态；本次确认及写入状态独立保存。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        Text(preview.packet.sourceMarkdown).font(.caption).textSelection(.enabled)
                    }
                }
            }
            .scrollContentBackground(.hidden).sprintPage()
            .navigationTitle("确认加入日程").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(preview.existingRevisionID == nil ? "确认导入" : "核验已导入计划") {
                        isSaving = true
                        do {
                            let result = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
                            onImported(result)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                        isSaving = false
                    }
                    .disabled(isSaving || !preview.conflicts.isEmpty)
                    .accessibilityIdentifier("已确认计划-确认导入")
                }
            }
            .fatLossError($errorMessage)
        }
    }
}
