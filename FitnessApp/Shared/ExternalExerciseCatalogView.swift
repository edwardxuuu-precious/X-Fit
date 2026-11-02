import SwiftData
import SwiftUI
import AVKit

struct ExternalExerciseCatalogView: View {
    let excludedExerciseIDs: Set<UUID>
    let onSelect: (Exercise) -> Void
    @State private var query: String
    @State private var muscleGroup = "全部"
    @State private var equipment = "全部"
    @State private var showingLicense = false

    init(initialQuery: String = "", excludedExerciseIDs: Set<UUID> = [],
         onSelect: @escaping (Exercise) -> Void) {
        self.excludedExerciseIDs = excludedExerciseIDs
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        Group {
            switch ExternalExerciseCatalogService.catalogResult {
            case .success(let catalog): catalogList(catalog)
            case .failure(let error):
                ContentUnavailableView("动作库暂不可用", systemImage: "books.vertical",
                    description: Text(error.localizedDescription))
            }
        }
        .navigationTitle("扩展动作库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("来源与许可") { showingLicense = true }
                    .accessibilityIdentifier("扩展库来源许可")
            }
        }
        .sheet(isPresented: $showingLicense) {
            NavigationStack {
                if case .success(let catalog) = ExternalExerciseCatalogService.catalogResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Exercises Dataset").font(.title2.bold())
                            Text("OpenGym 使用的 MIT 上游数据 · 1,324 条非媒体动作。中文名称由 X-Fit 整理；中英文参考步骤保留上游文字。")
                            Link("查看上游固定版本", destination: URL(string: "\(catalog.repository)/tree/\(catalog.commit)")!)
                            Text("版本 \(catalog.commit)").font(.caption).textSelection(.enabled)
                            Text(catalog.licenseText).font(.caption.monospaced()).textSelection(.enabled)
                        }.padding()
                    }
                    .navigationTitle("来源与许可")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingLicense = false } } }
                }
            }
        }
    }

    private func catalogList(_ catalog: ExternalExerciseCatalog) -> some View {
        let results = ExternalExerciseCatalogService.search(catalog.entries, query: query,
            muscleGroup: muscleGroup, equipment: equipment)
        return List {
            Section {
                Picker("肌群", selection: $muscleGroup) {
                    Text("全部").tag("全部")
                    ForEach(Set(catalog.entries.map(\.muscleGroup)).sorted(), id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("扩展库肌群筛选")
                Picker("器械", selection: $equipment) {
                    Text("全部").tag("全部")
                    ForEach(Set(catalog.entries.map(\.equipment)).sorted(), id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("扩展库器械筛选")
                Text("\(results.count) / \(catalog.entries.count) 个动作")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("扩展库结果数量")
            } footer: {
                Text("先在个人动作中选用已有动作。扩展库在选用时才加入个人库。")
            }
            Section {
                ForEach(results) { entry in
                    NavigationLink {
                        ExternalExerciseDetailView(entry: entry, excludedExerciseIDs: excludedExerciseIDs, onSelect: onSelect)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.nameZH).font(.body.weight(.semibold)).lineLimit(2)
                            Text(entry.nameEN).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(entry.muscleGroup) · \(entry.equipment) · \(entry.target)")
                                .font(.caption).foregroundStyle(.secondary)
                            if entry.needsReview { Text("变式待核对").font(.caption2).foregroundStyle(.orange) }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("扩展动作-\(entry.sourceID)")
                }
            }
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "中文、英文、器械或肌群")
        .scrollDismissesKeyboard(.immediately)
    }
}

private struct ExternalExerciseDetailView: View {
    @Query private var exercises: [Exercise]
    let entry: ExternalExerciseEntry
    let excludedExerciseIDs: Set<UUID>
    let onSelect: (Exercise) -> Void

    private var matches: [ExternalExerciseMatch] {
        ExternalExerciseCatalogService.matches(for: entry, among: exercises, excludedIDs: excludedExerciseIDs)
    }
    private var allMatches: [ExternalExerciseMatch] {
        ExternalExerciseCatalogService.matches(for: entry, among: exercises)
    }
    private var linkedExercise: Exercise? {
        exercises.first { ExternalExerciseCatalogService.sourceID(in: $0.referenceURL) == entry.sourceID }
    }

    var body: some View {
        List {
            Section {
                Text(entry.nameZH).font(.title2.bold()).accessibilityIdentifier("扩展动作中文名")
                Text(entry.nameEN).foregroundStyle(.secondary)
                LabeledContent("器械", value: entry.equipment)
                LabeledContent("肌群", value: entry.muscleGroup)
                LabeledContent("上游目标肌肉", value: entry.target)
            }
            if entry.needsReview {
                Section("变式待核对") {
                    ExternalExerciseReviewDisclosure(note: entry.reviewNote)
                }
            }
            ExerciseDemonstrationSection(entry: entry)
            if !matches.isEmpty {
                Section {
                    ForEach(matches) { match in
                        Button {
                            KeyboardDismissal.dismiss()
                            onSelect(match.exercise)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label("使用已有：\(match.exercise.name)", systemImage: "checkmark.circle")
                                Text("\(match.exercise.equipment) · \(match.exercise.volumeUnit.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(match.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("扩展库复用-\(match.exercise.name)")
                    }
                } header: { Text("匹配的个人动作") }
                  footer: { Text("选用保留个人动作的名称、单位、备注与历史。候选匹配需核对实际动作方式。") }
            }
            Section {
                if let linkedExercise {
                    Text(linkedExercise.isArchived ? "此来源动作已归档，可在个人动作中搜索并恢复。" : "此来源动作已加入个人库。")
                    if excludedExerciseIDs.contains(linkedExercise.id) { Text("此动作已在本次选择中。") }
                } else if allMatches.contains(where: \.isExact) {
                    Text("已找到对应的个人动作，可从上方选用并保留原记录。")
                    if matches.isEmpty { Text("此动作已在本次选择中。") }
                } else {
                    NavigationLink {
                        ExternalExerciseAddView(entry: entry, onSelect: onSelect)
                    } label: {
                        Label("加入我的动作", systemImage: "plus.circle.fill")
                    }.accessibilityIdentifier("扩展库加入个人动作")
                }
            }
            Section {
                DisclosureGroup("中文参考步骤（上游）") {
                    ForEach(Array(entry.stepsZH.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)").font(.callout).textSelection(.enabled)
                    }
                }
                DisclosureGroup("English instructions") {
                    ForEach(Array(entry.stepsEN.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)").font(.callout).textSelection(.enabled)
                    }
                }
            }
            Section {
                Text("Exercises Dataset · MIT · 来源 ID \(entry.sourceID)").font(.caption).foregroundStyle(.secondary)
                Link("查看非媒体数据来源", destination: URL(string: ExternalExerciseCatalogService.referenceURL(for: entry))!)
            }
        }
        .navigationTitle("动作详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExternalExerciseReviewDisclosure: View {
    let note: String

    var body: some View {
        DisclosureGroup("查看核对说明") {
            Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .accessibilityIdentifier("扩展库核对说明")
    }
}

private struct ExternalExerciseAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]
    let entry: ExternalExerciseEntry
    let onSelect: (Exercise) -> Void
    @State private var name: String
    @State private var unitRaw = ""
    @State private var errorMessage: String?

    init(entry: ExternalExerciseEntry, onSelect: @escaping (Exercise) -> Void) {
        self.entry = entry
        self.onSelect = onSelect
        _name = State(initialValue: entry.nameZH)
    }

    var body: some View {
        Form {
            Section {
                TextField("动作名称", text: $name).accessibilityIdentifier("扩展库新动作名称")
                LabeledContent("器械", value: entry.equipment)
                LabeledContent("肌群", value: entry.muscleGroup)
                Picker("训练量单位", selection: $unitRaw) {
                    Text("请选择").tag("")
                    ForEach(ExerciseVolumeUnit.allCases) { unit in Text(unit.title).tag(unit.rawValue) }
                }.accessibilityIdentifier("扩展库单位选择")
            } footer: {
                Text("kg 记录重量×次数；个记录次数；秒记录时长；米记录距离；自重记录体重×次数。请按实际记重口径选择。")
                if entry.nameEN.contains("assisted") {
                    Text("辅助重量与外加负重不同。按次数记录时，可在训练备注保留辅助 kg，避免计入负重训练量。")
                }
            }
            if entry.needsReview {
                Section("变式待核对") { ExternalExerciseReviewDisclosure(note: entry.reviewNote) }
            }
            Section {
                Text(entry.nameEN).font(.callout).foregroundStyle(.secondary)
                Text("来源关联会随个人动作保留，方便下次复用。参考步骤在扩展库查看。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("加入我的动作")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存并使用") {
                    do {
                        let exercise = try ExternalExerciseCatalogService.add(entry, name: name,
                            unit: ExerciseVolumeUnit(rawValue: unitRaw), exercises: exercises, in: modelContext)
                        KeyboardDismissal.dismiss()
                        onSelect(exercise)
                    } catch { errorMessage = error.localizedDescription }
                }
                .disabled(unitRaw.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("扩展库保存并使用")
            }
        }
        .alert("无法加入动作", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "未知错误") }
    }
}

/// Opens reference material without selecting, editing, or merging the personal exercise.
struct ExerciseExplanationButton: View {
    let exerciseID: UUID?
    let name: String
    let equipment: String
    var referenceURL: String = ""
    var showsName = false
    var titleAccessibilityID: String? = nil
    var beforeOpen: () -> Bool = { true }
    var lookupName: String? = nil
    @State private var showing = false

    var body: some View {
        Button {
            if beforeOpen() { showing = true }
        } label: {
            HStack(spacing: 6) {
                if showsName {
                    Text(name).accessibilityIdentifier(titleAccessibilityID ?? "动作名-\(name)")
                }
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
            }
            .frame(minWidth: showsName ? nil : 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)，查看动作说明")
        .accessibilityIdentifier("动作说明-\(name)")
        .sheet(isPresented: $showing) {
            NavigationStack {
                ExerciseExplanationView(exerciseID: exerciseID, name: lookupName ?? name, equipment: equipment,
                    referenceURL: referenceURL, onClose: { showing = false })
            }
        }
    }
}

private struct ExerciseExplanationView: View {
    @Query private var exercises: [Exercise]
    let exerciseID: UUID?
    let name: String
    let equipment: String
    let referenceURL: String
    let onClose: () -> Void
    @State private var query: String

    init(exerciseID: UUID?, name: String, equipment: String, referenceURL: String, onClose: @escaping () -> Void) {
        self.exerciseID = exerciseID
        self.name = name
        self.equipment = equipment
        self.referenceURL = referenceURL
        self.onClose = onClose
        _query = State(initialValue: name)
    }

    private var linkedEntry: ExternalExerciseEntry? {
        if let entry = ExternalExerciseCatalogService.linkedEntry(reference: referenceURL) { return entry }
        guard let id = exerciseID,
              let personal = exercises.first(where: { $0.id == id && (equipment.isEmpty || $0.equipment == equipment) }) else { return nil }
        return ExternalExerciseCatalogService.linkedEntry(reference: personal.referenceURL)
    }

    private var personalExercise: Exercise? {
        guard let id = exerciseID else { return nil }
        return exercises.first { $0.id == id && (equipment.isEmpty || $0.equipment == equipment) }
    }

    var body: some View {
        Group {
            if let entry = linkedEntry {
                ExerciseExplanationContent(entry: entry, onClose: onClose)
            } else {
                List {
                    Section("当前动作") {
                        Text(name).font(.headline)
                        if !equipment.isEmpty { LabeledContent("器械", value: equipment) }
                        if let personal = personalExercise, personal.name != name {
                            Text("对应的个人动作名称：\(personal.name)；请核对变式。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("此动作尚未明确关联扩展库。下方是可查看的候选，请先核对器械和变式；查看不会改变动作或历史。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    switch ExternalExerciseCatalogService.catalogResult {
                    case .failure(let error):
                        Section { Text(error.localizedDescription) }
                    case .success(let catalog):
                        let exact = ExternalExerciseCatalogService.explanationCandidates(name: query, equipment: equipment)
                        let results = exact.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? ExternalExerciseCatalogService.search(catalog.entries, query: query) : exact
                        Section("动作库候选") {
                            if results.isEmpty {
                                Text("没有找到明确候选，可修改上方搜索词；动作说明暂不可用。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(results.prefix(50))) { entry in
                                    NavigationLink {
                                        ExerciseExplanationContent(entry: entry, onClose: onClose)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.nameZH).font(.body.weight(.semibold))
                                            Text("\(entry.nameEN) · \(entry.equipment) · \(entry.muscleGroup)")
                                                .font(.caption).foregroundStyle(.secondary)
                                            if entry.needsReview { Text("变式待核对").font(.caption).foregroundStyle(.orange) }
                                        }
                                    }.accessibilityIdentifier("动作说明候选-\(entry.sourceID)")
                                }
                            }
                        }
                    }
                }
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索中文、英文或器械")
                .navigationTitle("动作说明")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) } }
                .onAppear {
                    if query == name, let personal = personalExercise { query = personal.name }
                }
            }
        }
    }
}

private final class ExerciseDemonstrationPlayback: ObservableObject {
    @Published var player: AVPlayer?
    @Published var failed = false
    @Published var ready = false
    private var observation: NSKeyValueObservation?
    private var timeout: DispatchWorkItem?

    func play(_ url: URL) {
        stop()
        failed = false
        ready = false
        let item = AVPlayerItem(url: url)
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            DispatchQueue.main.async {
                guard let self, self.player?.currentItem === item else { return }
                if status == .failed { self.failed = true }
                if status == .readyToPlay { self.ready = true; self.timeout?.cancel() }
            }
        }
        player = AVPlayer(playerItem: item)
        player?.play()
        let pending = DispatchWorkItem { [weak self] in
            guard let self, self.player?.currentItem === item, !self.ready else { return }
            self.failed = true
        }
        timeout = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: pending)
    }

    func stop() {
        player?.pause()
        player = nil
        observation = nil
        timeout?.cancel()
        timeout = nil
    }
}

private struct ExerciseExplanationContent: View {
    let entry: ExternalExerciseEntry
    let onClose: () -> Void

    var body: some View {
        List {
            Section {
                Text(entry.nameZH).font(.title2.bold()).accessibilityIdentifier("动作说明中文名")
                Text(entry.nameEN).foregroundStyle(.secondary)
                LabeledContent("器械", value: entry.equipment)
                LabeledContent("肌群", value: entry.muscleGroup)
                LabeledContent("目标", value: entry.target)
            }
            if entry.needsReview {
                Section("动作变式待核对") { Text(entry.reviewNote).font(.footnote) }
            }
            ExerciseDemonstrationSection(entry: entry)
            Section("中文动作步骤") {
                ForEach(Array(entry.stepsZH.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)").fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            Section {
                DisclosureGroup("English instructions") {
                    ForEach(Array(entry.stepsEN.enumerated()), id: \.offset) { index, step in Text("\(index + 1). \(step)") }
                }
            }
            Section("文字来源") {
                Text("Exercises Dataset · MIT · 来源 ID \(entry.sourceID)").font(.caption)
                if let source = URL(string: ExternalExerciseCatalogService.referenceURL(for: entry)) {
                    Link("查看文字来源", destination: source)
                }
            }
        }
        .navigationTitle("动作说明")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) } }
    }
}

private struct ExerciseDemonstrationSection: View {
    let entry: ExternalExerciseEntry
    @StateObject private var playback = ExerciseDemonstrationPlayback()

    var body: some View {
        Section("动作演示") {
            if let demo = ExternalExerciseCatalogService.demonstration(for: entry) {
                if let player = playback.player {
                    VideoPlayer(player: player).frame(height: 220)
                        .accessibilityIdentifier("动作演示视频")
                } else {
                    Button { playback.play(demo.videoURL) } label: {
                        Label("联网播放短视频", systemImage: "play.rectangle")
                    }.accessibilityIdentifier("播放动作演示")
                }
                if playback.ready { Text("动作演示已就绪").font(.caption).foregroundStyle(.secondary) }
                if playback.failed {
                    Text("视频暂时无法播放，请检查网络；下方文字仍可查看。")
                    Button("重试播放") { playback.play(demo.videoURL) }
                }
                Text("按需从 wger 加载，约 \(demo.approximateMegabytes)；不上传训练记录。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("演示：\(demo.author) · wger · CC BY-SA 4.0，未修改。")
                    .font(.caption)
                Link("查看视频来源", destination: demo.sourceURL)
                Link("查看 CC BY-SA 4.0 许可", destination: demo.licenseURL)
            } else {
                Text("暂无身份和许可均已核对的动图或视频；可继续查看下方文字步骤。")
                    .foregroundStyle(.secondary)
            }
        }.onDisappear { playback.stop() }
    }
}
