import Charts
import SwiftData
import SwiftUI

struct BodyMeasurementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]

    @State private var showEditor = false
    @State private var editingMeasurement: BodyMeasurement?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: "PRIVATE BODY LOG",
                    title: "身体数据",
                    trailingSystemImage: "plus",
                    trailingAction: {
                        editingMeasurement = nil
                        showEditor = true
                    }
                )

                latestCard
                weightTrend
                SectionHeader(title: "历史记录", actionTitle: "\(measurements.count) 条")

                if measurements.isEmpty {
                    ContentUnavailableView(
                        "还没有身体数据",
                        systemImage: "figure.arms.open",
                        description: Text("点击右上角，手动记录体重、体脂或围度。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    ForEach(measurements) { measurement in
                        measurementRow(measurement)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            BodyMeasurementEditorView(measurement: editingMeasurement)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
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

    private var latestCard: some View {
        HStack(spacing: 14) {
            bodyMetric(
                title: "体重",
                value: measurements.first?.weightKg.map { "\(TrainingFormatters.weight($0)) kg" } ?? "—",
                icon: "scalemass.fill"
            )
            bodyMetric(
                title: "体脂",
                value: measurements.first?.bodyFatPercent.map { "\(TrainingFormatters.weight($0))%" } ?? "—",
                icon: "percent"
            )
        }
    }

    private func bodyMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private var weightTrend: some View {
        let points = measurements.compactMap { measurement -> (Date, Double)? in
            guard let weight = measurement.weightKg else { return nil }
            return (measurement.date, weight)
        }.sorted { $0.0 < $1.0 }

        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("体重趋势")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Chart(Array(points.enumerated()), id: \.offset) { item in
                    LineMark(
                        x: .value("日期", item.element.0),
                        y: .value("体重", item.element.1)
                    )
                    .foregroundStyle(AppTheme.accent)
                    PointMark(
                        x: .value("日期", item.element.0),
                        y: .value("体重", item.element.1)
                    )
                    .foregroundStyle(AppTheme.accent)
                }
                .frame(height: 170)
            }
            .cardSurface()
        }
    }

    private func measurementRow(_ measurement: BodyMeasurement) -> some View {
        Button {
            editingMeasurement = measurement
            showEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(measurement.date, format: .dateTime.year().month().day())
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Text(measurement.source == .healthKit ? "Apple 健康" : "手动")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                HStack(spacing: 14) {
                    if let weight = measurement.weightKg {
                        Label("\(TrainingFormatters.weight(weight)) kg", systemImage: "scalemass")
                    }
                    if let bodyFat = measurement.bodyFatPercent {
                        Label("\(TrainingFormatters.weight(bodyFat))%", systemImage: "percent")
                    }
                    if let waist = measurement.waistCm {
                        Label("腰 \(TrainingFormatters.weight(waist)) cm", systemImage: "ruler")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
            .cardSurface(padding: 14, cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                modelContext.delete(measurement)
                do {
                    try modelContext.save()
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
    }
}

private struct BodyMeasurementEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let measurement: BodyMeasurement?

    @State private var date: Date
    @State private var weightKg: Double?
    @State private var bodyFatPercent: Double?
    @State private var waistCm: Double?
    @State private var chestCm: Double?
    @State private var armCm: Double?
    @State private var notes: String
    @State private var errorMessage: String?

    init(measurement: BodyMeasurement?) {
        self.measurement = measurement
        _date = State(initialValue: measurement?.date ?? .now)
        _weightKg = State(initialValue: measurement?.weightKg)
        _bodyFatPercent = State(initialValue: measurement?.bodyFatPercent)
        _waistCm = State(initialValue: measurement?.waistCm)
        _chestCm = State(initialValue: measurement?.chestCm)
        _armCm = State(initialValue: measurement?.armCm)
        _notes = State(initialValue: measurement?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日期") {
                    DatePicker("记录日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section("身体数据") {
                    decimalField("体重", value: $weightKg, unit: "kg")
                    decimalField("体脂", value: $bodyFatPercent, unit: "%")
                    decimalField("腰围", value: $waistCm, unit: "cm")
                    decimalField("胸围", value: $chestCm, unit: "cm")
                    decimalField("臂围", value: $armCm, unit: "cm")
                }
                Section("备注") {
                    TextField("测量条件或身体状态", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(measurement == nil ? "记录身体数据" : "编辑身体数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(allValuesEmpty)
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
    }

    private var allValuesEmpty: Bool {
        weightKg == nil && bodyFatPercent == nil && waistCm == nil && chestCm == nil && armCm == nil
    }

    private func decimalField(_ title: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("可选", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let saved = measurement ?? BodyMeasurement()
        if measurement == nil { modelContext.insert(saved) }
        saved.date = date
        saved.weightKg = sanitized(weightKg)
        saved.bodyFatPercent = sanitized(bodyFatPercent)
        saved.waistCm = sanitized(waistCm)
        saved.chestCm = sanitized(chestCm)
        saved.armCm = sanitized(armCm)
        saved.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.source = .manual
        saved.updatedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sanitized(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
