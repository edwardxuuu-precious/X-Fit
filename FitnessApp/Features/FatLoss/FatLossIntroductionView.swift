import SwiftUI

struct FatLossIntroductionView: View {
    let create: () throws -> Void
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                SprintPageHeader(title: "减脂周期", icon: "figure.run")
                Text("2026.09.06 — 12.06")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
            }
            HStack {
                FatLossMetric(value: "85 kg", label: "自述起点 · 尚非实测")
                FatLossMetric(value: "77.5 kg", label: "期望目标")
                FatLossMetric(value: "13 周", label: "完整记录")
            }

            DisclosureGroup("查看餐单与训练安排") {
            VStack(alignment: .leading, spacing: 17) {
                previewRow("fork.knife", title: "14 天家常餐单", detail: "早餐自己准备，午晚餐由钟点工提前做。份量先用碗、勺与餐盒估算。")
                previewRow("dumbbell.fill", title: "每周 3 天全身", detail: "第 4 天可选轻协调。训练先预览，再选择日期导入；已有训练保留。")
                previewRow("figure.jumprope", title: "跳绳记录实际活动", detail: "实际跳跃 8–10 分钟与含休息总时长分开记，不为了追赶体重加量。")
                previewRow("chart.xyaxis.line", title: "前两周建立基线", detail: "观察体重、腹胀和训练表现，每周记录反馈。目标和调整原因持续保留。")
            }.padding(.top, 12)
            }.foregroundStyle(AppTheme.ink)

            VStack(alignment: .leading, spacing: 9) {
                Label("营养目标待确认", systemImage: "heart.text.clipboard")
                    .font(.headline).foregroundStyle(AppTheme.orange)
                Text("先记录，再结合医生建议确认热量与蛋白质。菜单可调整。")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                Text("15 斤为期望目标，进度结合健康情况调整。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }.padding(.vertical, 8)

            Button {
                isSaving = true
                do { try create() } catch { errorMessage = error.localizedDescription }
                isSaving = false
            } label: {
                Label("创建周期", systemImage: "plus")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(SprintPrimaryButtonStyle())
            .disabled(isSaving)
            .accessibilityIdentifier("创建减脂周期")
            FatLossNote(text: "创建后即可记录；餐单与训练日程分别预览并导入。")
        }
        .fatLossError($errorMessage)
    }

    private func previewRow(_ icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            SprintIcon(systemName: icon, size: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(AppTheme.ink)
                Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}
