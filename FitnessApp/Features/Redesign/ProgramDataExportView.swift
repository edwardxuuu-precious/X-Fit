import SwiftData
import SwiftUI

struct ProgramDataExportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                SprintPageHeader(title: "周期导出", icon: "square.and.arrow.up")
                if programs.isEmpty {
                    ContentUnavailableView("还没有周期", systemImage: "calendar", description: Text("创建减脂周期后可导出记录。"))
                }
                ForEach(programs) { program in
                    VStack(alignment: .leading, spacing: 16) {
                        Label(FatLossCalendar.label(program.startDate) + " — " + FatLossCalendar.label(program.endDate), systemImage: "calendar")
                            .font(.headline)
                        Text("逐日记录、实吃、目标版本、餐单历史、健康资料与复盘。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        Button {
                            do { exportedURL = try FatLossService.exportCSV(program: program, in: context) }
                            catch { errorMessage = error.localizedDescription }
                        } label: {
                            Label("生成 CSV", systemImage: "tablecells")
                        }.buttonStyle(SprintPrimaryButtonStyle())
                    }.cardSurface()
                }
                if let exportedURL {
                    ShareLink(item: exportedURL) { Label("保存或分享 CSV", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SprintSecondaryButtonStyle())
                }
            }.padding(20)
        }.sprintPage()
            .navigationTitle("周期导出").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).fatLossError($errorMessage)
    }
}
