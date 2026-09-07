import SwiftData
import SwiftUI

struct ProgramDataExportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    var body: some View {
        List {
            if programs.isEmpty {
                ContentUnavailableView("还没有减脂周期", systemImage: "calendar", description: Text("在目标页创建周期后，可以导出完整记录。"))
            }
            ForEach(programs) { program in
                Section(FatLossCalendar.label(program.startDate) + " — " + FatLossCalendar.label(program.endDate)) {
                    Text("包含逐日记录、实吃、目标版本、餐单历史、健康资料与复盘。")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    Button("生成周期 CSV") {
                        do { exportedURL = try FatLossService.exportCSV(program: program, in: context) }
                        catch { errorMessage = error.localizedDescription }
                    }.frame(minHeight: 44)
                }
            }
            if let exportedURL {
                Section {
                    ShareLink(item: exportedURL) { Label("保存或分享 CSV", systemImage: "square.and.arrow.up") }
                        .frame(minHeight: 44)
                }
            }
        }.scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("导出减脂周期").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).fatLossError($errorMessage)
    }
}
