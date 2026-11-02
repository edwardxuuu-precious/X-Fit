import SwiftUI
import UIKit

struct SavedSchedulePlanView: View {
    private struct Content {
        let title: String
        let localDay: String
        let items: [ScheduledWorkoutExerciseSnapshot]
        let ropeSummary: String?
        let ropeNotes: String?
        let draft: ProgramCardioDraft?
        let cardio: CardioWorkoutSummary?
    }

    private let content: Content
    @State private var expanded: Set<UUID> = []
    @State private var notesExpanded: Set<UUID> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(schedule: ScheduledWorkout, draft: ProgramCardioDraft?) {
        let rope = schedule.jumpRopePlan
        content = Content(title: schedule.templateName, localDay: TrainingScheduleDate.localDay(schedule),
            items: schedule.planSnapshot, ropeSummary: rope?.summary, ropeNotes: rope?.notes,
            draft: rope == nil ? draft : nil, cardio: CardioWorkoutPresentation.plan(schedule))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heading
                nonStrengthContent
                if !content.items.isEmpty {
                    overview
                    HStack {
                        Text("训练动作").font(.headline)
                        Spacer()
                        Button {
                            expanded = expanded.count == content.items.count ? [] : Set(content.items.map(\.id))
                        } label: {
                            Image(systemName: "chevron.up.chevron.down").frame(width: 44, height: 44)
                        }.accessibilityLabel(expanded.count == content.items.count ? "收起全部动作" : "展开全部动作")
                            .accessibilityIdentifier("计划-全部展开")
                    }
                    VStack(spacing: 11) {
                        ForEach(content.items) { item in exerciseCard(item) }
                    }
                } else if content.ropeSummary == nil && content.draft == nil {
                    Text("未保存计划明细").foregroundStyle(EditorialTheme.muted)
                        .accessibilityIdentifier("计划-无保存明细")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(23)
        }.editorialPage().navigationTitle("查看计划").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("训练-保存的计划")
    }

    private var heading: some View {
        let titleParts = content.title.components(separatedBy: " · ")
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    if let date = TrainingLocalDate.date(content.localDay) {
                        Text(date, format: .dateTime.month().day().weekday())
                    } else { Text(content.localDay) }
                } icon: { Image(systemName: "calendar").accessibilityHidden(true) }
                    .font(.caption).foregroundStyle(EditorialTheme.muted)
                Text(titleParts.first ?? content.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                if titleParts.count > 1 {
                    Text(titleParts.dropFirst().joined(separator: " · ")).font(.caption).foregroundStyle(EditorialTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: content.cardio?.symbolName ?? (content.ropeSummary == nil ? "dumbbell" : "figure.jumprope"))
                    .font(.system(size: 30, weight: .semibold)).frame(width: 68, height: 68)
                    .background(EditorialTheme.lime, in: RoundedRectangle(cornerRadius: 22))
                    .rotationEffect(.degrees(-8)).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var nonStrengthContent: some View {
        if let rope = content.ropeSummary {
            Text(rope)
            if let notes = content.ropeNotes, !notes.isEmpty { Text(notes) }
        } else if let draft = content.draft {
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.title).font(.headline)
                if let seconds = draft.activeSeconds { Text("有效时长 \(seconds) 秒") }
                if let seconds = draft.activeSecondsUpper { Text("有效时长上限 \(seconds) 秒") }
                if let seconds = draft.elapsedSeconds { Text("总时长 \(seconds) 秒") }
                if !draft.timing.isEmpty { Text(draft.timing) }
                if !draft.intervals.isEmpty { Text(draft.intervals) }
                if !draft.guidance.isEmpty { Text(draft.guidance) }
            }
        }
        if let cardio = content.cardio { Text(cardio.label) }
    }

    private var overview: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 20))
        return layout {
            overviewValue(content.items.count, unit: "动作", symbol: "dumbbell")
            if !dynamicTypeSize.isAccessibilitySize {
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 24).accessibilityHidden(true)
            }
            overviewValue(content.items.reduce(0) { $0 + $1.targetSets }, unit: "组", symbol: "square.3.layers.3d")
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(EditorialTheme.ink, in: RoundedRectangle(cornerRadius: 18))
    }

    private func overviewValue(_ value: Int, unit: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(EditorialTheme.lime).accessibilityHidden(true)
            Text("\(value)").font(.title2.bold().italic())
            Text(unit).font(.caption.bold())
        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private func exerciseCard(_ item: ScheduledWorkoutExerciseSnapshot) -> some View {
        let isExpanded = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button { toggle(item.id, in: &expanded) } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            illustration(item)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(SavedPlanDisplay.shortName(item.exerciseName)).font(.subheadline.bold())
                                    .fixedSize(horizontal: false, vertical: true)
                                if !item.equipment.isEmpty { Text(item.equipment).font(.caption).foregroundStyle(EditorialTheme.muted) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundStyle(EditorialTheme.muted).accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        metadata(item)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        illustration(item)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(SavedPlanDisplay.shortName(item.exerciseName)).font(.subheadline.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            if !item.equipment.isEmpty { Text(item.equipment).font(.caption).foregroundStyle(EditorialTheme.muted) }
                            metadata(item)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(EditorialTheme.muted).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).contentShape(Rectangle())
                }
            }.buttonStyle(.plain)
                .accessibilityLabel(item.exerciseName + "，" + SavedPlanDisplay.metadataLabel(item))
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityHint(isExpanded ? "轻点收起逐组目标" : "轻点查看逐组目标")
                .accessibilityIdentifier("计划-动作-" + item.id.uuidString)
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if item.plannedSets.isEmpty {
                        Text(SavedPlanDisplay.missingSets(item)).foregroundStyle(EditorialTheme.muted)
                    }
                    ForEach(Array(item.plannedSets.enumerated()), id: \.element.id) { index, set in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("第\(index + 1)组 · " + SavedPlanDisplay.target(set, unit: item.volumeUnit)).font(.subheadline)
                            if let prescription = set.prescription {
                                Text(prescription.label).font(.caption).foregroundStyle(EditorialTheme.muted)
                                if let rir = SavedPlanDisplay.rir(prescription) { Text(rir).font(.caption).foregroundStyle(EditorialTheme.muted) }
                            } else {
                                Text("休息 \(item.restSeconds) 秒").font(.caption).foregroundStyle(EditorialTheme.muted)
                            }
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    if !item.exerciseNotes.isEmpty || item.plannedSets.contains(where: { $0.prescription != nil }) || SavedPlanDisplay.shortName(item.exerciseName) != item.exerciseName {
                        Button { toggle(item.id, in: &notesExpanded) } label: {
                            HStack {
                                Text(notesExpanded.contains(item.id) ? "收起完整说明" : "完整处方与备注").font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Image(systemName: notesExpanded.contains(item.id) ? "minus" : "plus").accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(notesExpanded.contains(item.id) ? "已展开" : "已收起")
                            .accessibilityIdentifier("计划-说明-" + item.id.uuidString)
                        if notesExpanded.contains(item.id) {
                            Text(item.exerciseName).font(.headline)
                            ForEach(Array(item.plannedSets.enumerated()), id: \.element.id) { index, set in
                                if let prescription = set.prescription {
                                    Text("第\(index + 1)组 · " + prescription.summary).font(.subheadline)
                                }
                            }
                            if !item.exerciseNotes.isEmpty { Text(item.exerciseNotes).font(.subheadline) }
                        }
                    }
                }.padding(.top, 16)
            }
        }.padding(14).foregroundStyle(EditorialTheme.ink)
            .background(isExpanded ? AppTheme.accentSoft : EditorialTheme.sage, in: RoundedRectangle(cornerRadius: 20))
    }

    private func metadata(_ item: ScheduledWorkoutExerciseSnapshot) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 9))
        return layout {
            metadataValue("\(item.targetSets)组", symbol: "square.3.layers.3d")
            metadataValue(SavedPlanDisplay.repetitionSummary(item), symbol: "repeat")
            if let rest = SavedPlanDisplay.commonRest(item) { metadataValue(rest, symbol: "stopwatch") }
        }.font(.caption2).foregroundStyle(EditorialTheme.muted)
    }

    private func metadataValue(_ text: String, symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func illustration(_ item: ScheduledWorkoutExerciseSnapshot) -> some View {
        ExerciseArtworkView(exerciseID: item.exerciseID, name: item.exerciseName, size: 64)
    }

    private func toggle(_ id: UUID, in values: inout Set<UUID>) {
        if values.contains(id) { values.remove(id) } else { values.insert(id) }
    }
}

enum SavedPlanDisplay {
    static func shortName(_ name: String) -> String {
        name.components(separatedBy: "，").first ?? name
    }

    static func missingSets(_ item: ScheduledWorkoutExerciseSnapshot) -> String {
        "已保存 \(item.targetSets) 组，逐组目标未保存"
    }

    static func repetitionSummary(_ item: ScheduledWorkoutExerciseSnapshot) -> String {
        guard let first = item.plannedSets.first, let last = item.plannedSets.last else { return "目标未保存" }
        let values = item.plannedSets.map(\.reps)
        let suffix: String
        switch item.volumeUnit {
        case .second: suffix = "秒"
        case .meter: suffix = "趟"
        case .count: suffix = item.volumeUnit.symbol
        case .kilogram, .bodyweight: suffix = "次"
        }
        if values.allSatisfy({ $0 == first.reps }) { return "\(first.reps)\(suffix)" }
        if zip(values, values.dropFirst()).allSatisfy({ $0 >= $1 }) || zip(values, values.dropFirst()).allSatisfy({ $0 <= $1 }) {
            return "\(first.reps)→\(last.reps)\(suffix)"
        }
        return "\(values.min()!)–\(values.max()!)\(suffix)"
    }

    static func commonRest(_ item: ScheduledWorkoutExerciseSnapshot) -> String? {
        guard !item.plannedSets.isEmpty else { return nil }
        let rests = item.plannedSets.map { set in
            if let prescription = set.prescription {
                return prescription.restLowerSeconds == prescription.restUpperSeconds
                    ? "\(prescription.restLowerSeconds)秒" : "\(prescription.restLowerSeconds)–\(prescription.restUpperSeconds)秒"
            }
            return "\(item.restSeconds)秒"
        }
        return Set(rests).count == 1 ? rests.first : nil
    }

    static func metadataLabel(_ item: ScheduledWorkoutExerciseSnapshot) -> String {
        (["\(item.targetSets)组", repetitionSummary(item), commonRest(item).map { "休息 " + $0 }].compactMap { $0 }).joined(separator: "，")
    }

    static func rir(_ prescription: WorkoutSetPrescription) -> String? {
        guard let lower = prescription.rirLower, let upper = prescription.rirUpper else { return nil }
        return lower == upper ? "RIR \(lower)" : "RIR \(lower)–\(upper)"
    }

    static func target(_ set: WorkoutSetPlan, unit: ExerciseVolumeUnit) -> String {
        switch unit {
        case .kilogram:
            if set.weight == 0, set.actualDefaultPolicy == .blank || set.weightSide == .unknown {
                return "重量待校准 · \(set.reps) 次（\(set.repsSide.title)）"
            }
            return "\(TrainingFormatters.weight(set.weight)) kg（\(set.weightSide.title)） · \(set.reps) 次（\(set.repsSide.title)）"
        case .bodyweight: return "自重 · \(set.reps) 次（\(set.repsSide.title)）"
        case .meter: return "\(TrainingFormatters.weight(set.weight)) 米 × \(set.reps) 趟"
        case .second: return "\(set.reps) 秒"
        case .count: return "\(set.reps) \(unit.symbol)（\(set.repsSide.title)）"
        }
    }
}
