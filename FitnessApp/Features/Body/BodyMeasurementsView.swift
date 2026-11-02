import Charts
import SwiftData
import SwiftUI

struct BodyMeasurementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]

    @State private var showQuickEditor = false
    @State private var fullEditor: BodyEditorRoute?
    @State private var errorMessage: String?

    private var latestWeight: BodyWeightDailyValue? {
        BodyMeasurementService.dailyRepresentativeWeights(from: measurements).last
    }

    private var latestBodyFat: BodyMeasurement? {
        measurements.first { measurement in
            guard let value = measurement.bodyFatPercent else { return false }
            return value.isFinite && value > 0
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SprintPageHeader(title: "身体记录", icon: "figure.arms.open")
                latestCard
                Button {
                    fullEditor = BodyEditorRoute(measurement: nil)
                } label: {
                    Label("记录体脂与围度", systemImage: "ruler")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(SprintSecondaryButtonStyle())
                .accessibilityIdentifier("记录完整身体数据")

                BodyWeightTrendCard(measurements: measurements)
                SectionHeader(title: "历史记录", actionTitle: "\(measurements.count) 条")

                if measurements.isEmpty {
                    ContentUnavailableView(
                        "还没有身体数据",
                        systemImage: "scalemass",
                        description: Text("先记录一次体重，趋势会从这里开始。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(measurements) { measurement in
                            measurementRow(measurement)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.immediately)
        .sprintPage()
        .navigationTitle("身体数据")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    traceQuickWeight("button.action")
                    showQuickEditor = true
                } label: {
                    Label("快速记录体重", systemImage: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("快速记录体重")
            }
        }
        .sheet(isPresented: $showQuickEditor) {
            QuickBodyWeightEntryView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.light)
                .tint(AppTheme.ink)
                .onAppear { traceQuickWeight("sheet.appear") }
                .onDisappear { traceQuickWeight("sheet.disappear") }
        }
        .onChange(of: showQuickEditor) { _, presented in
            traceQuickWeight(presented ? "presentation.true" : "presentation.false")
        }
        .sheet(item: $fullEditor) { route in
            BodyMeasurementEditorView(measurement: route.measurement)
                .preferredColorScheme(.light)
                .tint(AppTheme.ink)
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

    // Bounded diagnosis only: no user values, database writes or production logging.
    private func traceQuickWeight(_ event: String) {
#if DEBUG
        guard CloudSyncRuntime.isTesting, CloudSyncRuntime.isUITesting,
              CommandLine.arguments.contains("--ui-testing-quick-weight-diagnostics") else { return }
        NSLog("XFitQuickWeightTrace %@", event)
#endif
    }

    private var latestCard: some View {
        LazyVGrid(columns: [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 145), alignment: .leading)], spacing: 14) {
            bodyMetric(
                title: latestWeight.map { sourceAndDate($0) } ?? "体重",
                value: latestWeight.map { "\(TrainingFormatters.weight($0.weightKg)) kg" } ?? "—",
                icon: "scalemass.fill"
            )
            bodyMetric(
                title: latestBodyFat.map { "\($0.source == .healthKit ? "Apple 健康" : "X-Fit") · 体脂" } ?? "体脂",
                value: latestBodyFat?.bodyFatPercent.map { "\(TrainingFormatters.weight($0))%" } ?? "—",
                icon: "percent"
            )
        }
        .accessibilityIdentifier("身体数据最新摘要")
    }

    private func bodyMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SprintIcon(systemName: icon, size: 40)
            Text(value)
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func measurementRow(_ measurement: BodyMeasurement) -> some View {
        Button {
            guard measurement.source == .manual else { return }
            fullEditor = BodyEditorRoute(measurement: measurement)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(measurement.date, format: .dateTime.year().month().day().hour().minute())
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(measurement.source == .healthKit ? "Apple 健康" : "X-Fit 手动")
                        .font(.caption2.bold())
                        .foregroundStyle(measurement.source == .healthKit ? AppTheme.secondaryText : AppTheme.ink)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 10) {
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
                if !measurement.notes.isEmpty {
                    Text(measurement.notes)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }
            .cardSurface(padding: 14, cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .disabled(measurement.source != .manual)
        .accessibilityIdentifier("身体记录-\(measurement.id.uuidString)")
        .accessibilityHint(measurement.source == .manual ? "点按编辑，长按可删除" : "来自 Apple 健康的只读记录")
        .contextMenu {
            if measurement.source == .manual {
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

    private func sourceAndDate(_ value: BodyWeightDailyValue) -> String {
        let source = value.source == .healthKit ? "Apple 健康" : "X-Fit"
        return "\(source) · \(value.date.formatted(.dateTime.month().day()))"
    }
}

struct BodyWeightTrendCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let measurements: [BodyMeasurement]
    var showsHistoryLink = false

    @State private var period: BodyWeightTrendPeriod = .oneMonth

    private var dailyValues: [BodyWeightDailyValue] {
        BodyMeasurementService.dailyRepresentativeWeights(from: measurements)
    }

    private var points: [BodyWeightTrendPoint] {
        BodyMeasurementService.filteredTrendPoints(
            BodyMeasurementService.trendPoints(from: dailyValues),
            period: period
        )
    }

    private var change: Double? {
        guard let first = points.first, let last = points.last, first.id != last.id else { return nil }
        return last.weightKg - first.weightKg
    }

    var body: some View {
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        let legendLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        return VStack(alignment: .leading, spacing: 16) {
            headerLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Label("体重趋势", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.ink)
                    if let latest = dailyValues.last {
                        Text("\(TrainingFormatters.weight(latest.weightKg)) kg")
                            .font(.title2.weight(.black).monospacedDigit())
                            .foregroundStyle(AppTheme.ink)
                    } else {
                        Text("暂无记录")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                if let change {
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                        Text(change == 0 ? "0 kg" : String(format: "%+.1f kg", change))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.ink)
                        Text("本周期")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("周期").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Picker("体重趋势周期", selection: $period) {
                        ForEach(BodyWeightTrendPeriod.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .accessibilityIdentifier("体重趋势周期")
                }
            } else {
                Picker("体重趋势周期", selection: $period) {
                    ForEach(BodyWeightTrendPeriod.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("体重趋势周期")
            }

            if points.isEmpty {
                VStack(spacing: 12) {
                    SprintIcon(systemName: "chart.line.uptrend.xyaxis", size: 46)
                    Text("记录后显示每日值与 7 日均线")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }.frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(points) { point in
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("每日体重", point.weightKg)
                        )
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.75))
                        .symbolSize(24)
                    }
                    ForEach(points.filter { $0.movingAverageKg != nil }) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("7 日均线", point.movingAverageKg ?? point.weightKg)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(AppTheme.ink)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 180).sprintChart()
                .accessibilityIdentifier("体重趋势图")

                legendLayout {
                    Label("每日值", systemImage: "circle.fill")
                    Label("7 日均线", systemImage: "line.diagonal")
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            }

            if showsHistoryLink {
                NavigationLink(destination: BodyMeasurementsView()) {
                    Label("查看完整记录", systemImage: "arrow.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("查看完整身体记录")
            }
        }
        .cardSurface()
        .accessibilityIdentifier("身体数据趋势卡片")
    }
}

struct QuickBodyWeightEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]

    @State private var weightText = ""
    @State private var date = Date.now
    @State private var showsMore = false
    @State private var bodyFatText = ""
    @State private var waistText = ""
    @State private var chestText = ""
    @State private var armText = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight, bodyFat, waist, chest, arm, notes
    }

    private var latestWeight: Double? {
        BodyMeasurementService.dailyRepresentativeWeights(from: measurements).last?.weightKg
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("体重", systemImage: "scalemass")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.secondaryText)
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = nil }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button { adjustWeight(by: -0.1) } label: {
                                Image(systemName: "minus")
                                    .frame(width: 44, height: 44)
                                    .background(AppTheme.elevatedSurface, in: Circle())
                            }
                            .accessibilityLabel("体重减少 0.1 千克")

                            TextField("00.0", text: $weightText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .weight)
                                .font(AppTheme.metricValue)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(AppTheme.ink)
                                .minimumScaleFactor(0.6)
                                .accessibilityLabel("体重，单位千克")
                                .accessibilityIdentifier("快速体重输入")

                            Button { adjustWeight(by: 0.1) } label: {
                                Image(systemName: "plus")
                                    .frame(width: 44, height: 44)
                                    .background(AppTheme.elevatedSurface, in: Circle())
                            }
                            .accessibilityLabel("体重增加 0.1 千克")

                            Text("kg")
                                .font(.title3.bold())
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .padding(18)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.accent.opacity(0.22)))

                    if let latestWeight {
                        Text("上次 \(TrainingFormatters.weight(latestWeight)) kg")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    DatePicker(
                        "测量时间",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showsMore.toggle() }
                    } label: {
                        HStack {
                            Label("更多身体数据", systemImage: "ruler")
                            Spacer()
                            Image(systemName: showsMore ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("展开更多身体数据")

                    if showsMore {
                        VStack(spacing: 12) {
                            decimalRow("体脂", text: $bodyFatText, unit: "%", field: .bodyFat)
                            decimalRow("腰围", text: $waistText, unit: "cm", field: .waist)
                            decimalRow("胸围", text: $chestText, unit: "cm", field: .chest)
                            decimalRow("臂围", text: $armText, unit: "cm", field: .arm)
                            TextField("测量条件或身体状态（可选）", text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .focused($focusedField, equals: .notes)
                                .padding(12)
                                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("更多身体数据表单")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button("保存体重") { save() }
                        .neonButtonStyle()
                        .disabled(parsed(weightText) == nil)
                        .opacity(parsed(weightText) == nil ? 0.45 : 1)
                        .accessibilityIdentifier("保存体重")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("quick-body-weight-scroll")
            .scrollDismissesKeyboard(.immediately)
            .dismissKeyboardWhenScrolling {
                focusedField = nil
                KeyboardDismissal.dismiss()
            }
            .sprintPage()
            .navigationTitle("记录体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if weightText.isEmpty, let latestWeight {
                    weightText = TrainingFormatters.weight(latestWeight)
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
        .accessibilityIdentifier("快速记录体重")
    }

    private func decimalRow(_ title: String, text: Binding<String>, unit: String, field: Field) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.ink)
            Spacer()
            TextField("可选", text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .accessibilityIdentifier("快速\(title)输入")
            Text(unit)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(12)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func adjustWeight(by delta: Double) {
        let base = parsed(weightText) ?? latestWeight ?? 0
        let adjusted = max(0, (base + delta) * 10).rounded() / 10
        weightText = adjusted > 0 ? TrainingFormatters.weight(adjusted) : ""
    }

    private func save() {
        guard let weight = parsed(weightText) else {
            errorMessage = "请输入有效体重。"
            return
        }
        do {
            try BodyMeasurementService.saveQuickEntry(
                BodyMeasurementQuickEntry(
                    date: date,
                    weightKg: weight,
                    bodyFatPercent: parsed(bodyFatText),
                    waistCm: parsed(waistText),
                    chestCm: parsed(chestText),
                    armCm: parsed(armText),
                    notes: notes,
                    includesExtendedFields: showsMore
                ),
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsed(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }
}

private struct BodyEditorRoute: Identifiable {
    let id = UUID()
    let measurement: BodyMeasurement?
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
                Section {
                    DatePicker("记录日期", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                } header: {
                    Label("日期", systemImage: "calendar")
                }
                Section {
                    decimalField("体重", value: $weightKg, unit: "kg")
                    decimalField("体脂", value: $bodyFatPercent, unit: "%")
                    decimalField("腰围", value: $waistCm, unit: "cm")
                    decimalField("胸围", value: $chestCm, unit: "cm")
                    decimalField("臂围", value: $armCm, unit: "cm")
                } header: {
                    Label("身体数据", systemImage: "ruler")
                }
                Section {
                    TextField("测量条件或身体状态", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("完整身体数据-备注")
                } header: {
                    Label("备注", systemImage: "text.alignleft")
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .dismissKeyboardWhenScrolling {
                KeyboardDismissal.dismiss()
            }
            .scrollContentBackground(.hidden)
            .sprintPage()
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
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
        [weightKg, bodyFatPercent, waistCm, chestCm, armCm].allSatisfy { sanitized($0) == nil }
    }

    private func decimalField(_ title: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("可选", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .accessibilityIdentifier("完整身体数据-\(title)")
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard !allValuesEmpty else { return }
        let saved = measurement ?? BodyMeasurement(source: .manual)
        if measurement == nil {
            modelContext.insert(saved)
        }
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
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
