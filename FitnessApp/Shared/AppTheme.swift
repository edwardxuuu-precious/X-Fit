import SwiftUI
import UIKit

enum AppTheme {
    static let pageMargin: CGFloat = 20
    static let minimumTouchTarget: CGFloat = 44
    static let sectionSpacing: CGFloat = 24
    static let pageTitle = Font.title2.bold()
    static let metricValue = Font.title.bold().monospacedDigit()

    static let accent = Color(red: 0.77, green: 0.98, blue: 0.275)
    static let accentSoft = Color(red: 0.57, green: 0.75, blue: 0.20)
    static let background = Color(red: 0.047, green: 0.051, blue: 0.043)
    static let surface = Color(red: 0.083, green: 0.090, blue: 0.075)
    static let elevatedSurface = Color(red: 0.126, green: 0.137, blue: 0.114)
    static let line = Color.white.opacity(0.075)
    static let secondaryText = Color(red: 0.67, green: 0.69, blue: 0.63)
    static let tabBar = Color(red: 0.025, green: 0.031, blue: 0.034)
    static let posterBackground = Color(red: 0.035, green: 0.043, blue: 0.045)
    static let posterWarmWhite = Color(red: 0.96, green: 0.96, blue: 0.92)
    static let orange = Color(red: 1.00, green: 0.39, blue: 0.12)
    static let purple = Color(red: 0.73, green: 0.27, blue: 1.00)

    static let heroGradient = LinearGradient(
        colors: [Color.black.opacity(0.08), Color.black.opacity(0.94)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let screenGradient = LinearGradient(
        colors: [Color(red: 0.035, green: 0.045, blue: 0.050), background],
        startPoint: .top,
        endPoint: .center
    )

    static let homeBackgroundGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.055, green: 0.068, blue: 0.068), location: 0),
            .init(color: Color(red: 0.020, green: 0.027, blue: 0.028), location: 0.42),
            .init(color: Color(red: 0.006, green: 0.009, blue: 0.010), location: 1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let homeAmbientGlow = RadialGradient(
        colors: [Color.white.opacity(0.075), .clear],
        center: UnitPoint(x: 0.78, y: 0.04),
        startRadius: 0,
        endRadius: 340
    )

    static let homeAccentGlow = RadialGradient(
        colors: [accent.opacity(0.085), .clear],
        center: UnitPoint(x: 0.10, y: 0.42),
        startRadius: 0,
        endRadius: 300
    )

    static let homeCoolGlow = RadialGradient(
        colors: [Color(red: 0.18, green: 0.27, blue: 0.29).opacity(0.16), .clear],
        center: UnitPoint(x: 0.90, y: 0.48),
        startRadius: 0,
        endRadius: 320
    )
}

struct CardSurface: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

    }
}

struct FloatingGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func cardSurface(padding: CGFloat = 16, cornerRadius: CGFloat = 12) -> some View {
        modifier(CardSurface(padding: padding, cornerRadius: cornerRadius))
    }

    func screenBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }

    func homeScreenBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }

    func floatingGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(FloatingGlassSurface(cornerRadius: cornerRadius))
    }

    func neonButtonStyle() -> some View {
        font(.subheadline.bold())
            .foregroundStyle(.black)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

@MainActor
enum KeyboardDismissal {
    static func dismiss() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.endEditing(true) }

        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct DismissKeyboardOnScrollPhaseModifier: ViewModifier {
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, newPhase in
                if newPhase == .tracking || newPhase == .interacting {
                    action()
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Uses the real scroll phase so keyboard dismissal still fires when a
    /// SwiftUI drag gesture is consumed by the scroll view itself.
    func dismissKeyboardWhenScrolling(perform action: @escaping () -> Void) -> some View {
        modifier(DismissKeyboardOnScrollPhaseModifier(action: action))
    }
}

/// A compact numeric field for workout logging. It selects the current value
/// when editing begins and never rewrites the visible text while the field owns
/// focus. That keeps rapid gym-floor entry from appending to an old value or
/// losing the cursor when SwiftData publishes an edit.
struct StableNumericTextField: UIViewRepresentable {
    private enum Kind {
        case decimal(maximumFractionDigits: Int)
        case integer
    }

    private let decimalValue: Binding<Double>?
    private let integerValue: Binding<Int>?
    private let kind: Kind
    private let placeholder: String
    private let accessibilityIdentifier: String

    init(
        _ placeholder: String,
        value: Binding<Double>,
        maximumFractionDigits: Int = 3,
        accessibilityIdentifier: String
    ) {
        decimalValue = value
        integerValue = nil
        kind = .decimal(maximumFractionDigits: maximumFractionDigits)
        self.placeholder = placeholder
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    init(
        _ placeholder: String,
        value: Binding<Int>,
        accessibilityIdentifier: String
    ) {
        decimalValue = nil
        integerValue = value
        kind = .integer
        self.placeholder = placeholder
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.placeholder = placeholder
        field.accessibilityIdentifier = accessibilityIdentifier
        field.textAlignment = .center
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .label
        field.tintColor = UIColor(AppTheme.accent)
        field.keyboardType = keyboardType
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(
                title: "完成",
                style: .done,
                target: context.coordinator,
                action: #selector(Coordinator.dismissKeyboard)
            )
        ]
        field.inputAccessoryView = toolbar
        field.text = formattedValue
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.placeholder = placeholder
        field.accessibilityIdentifier = accessibilityIdentifier
        field.keyboardType = keyboardType

        // Reformat only after editing ends. Replacing text during an active edit
        // resets UIKit selection and was the source of the visible page/input jump.
        if !field.isFirstResponder, field.text != formattedValue {
            field.text = formattedValue
        }
    }

    private var keyboardType: UIKeyboardType {
        switch kind {
        case .decimal: .decimalPad
        case .integer: .numberPad
        }
    }

    private var formattedValue: String {
        switch kind {
        case .decimal:
            TrainingFormatters.weight(decimalValue?.wrappedValue ?? 0)
        case .integer:
            String(integerValue?.wrappedValue ?? 0)
        }
    }

    private func accepts(_ candidate: String) -> Bool {
        guard !candidate.isEmpty else { return true }
        let normalized = candidate.replacingOccurrences(of: ",", with: ".")
        switch kind {
        case let .decimal(maximumFractionDigits):
            guard normalized.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
            let pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
            guard pieces.count <= 2 else { return false }
            return pieces.count == 1 || pieces[1].count <= maximumFractionDigits
        case .integer:
            return normalized.allSatisfy(\.isNumber)
        }
    }

    private func commit(_ text: String) {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return }
        switch kind {
        case .decimal:
            if let value = Double(normalized) { decimalValue?.wrappedValue = value }
        case .integer:
            if let value = Int(normalized) { integerValue?.wrappedValue = value }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: StableNumericTextField

        init(parent: StableNumericTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ field: UITextField) {
            parent.commit(field.text ?? "")
        }

        @objc func dismissKeyboard() {
            KeyboardDismissal.dismiss()
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            DispatchQueue.main.async {
                field.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if field.text?.isEmpty == true {
                parent.commit("0")
            }
            field.text = parent.formattedValue
        }

        func textField(
            _ field: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard let current = field.text,
                  let swiftRange = Range(range, in: current)
            else { return false }
            return parent.accepts(current.replacingCharacters(in: swiftRange, with: string))
        }
    }
}

struct ScreenHeader: View {
    let eyebrow: String?
    let title: String
    var trailingSystemImage: String? = nil
    var trailingAccessibilityLabel: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Text(title)
                    .font(AppTheme.pageTitle)
                    .foregroundStyle(AppTheme.posterWarmWhite)
            }

            Spacer()

            if let trailingSystemImage {
                Button(action: trailingAction ?? {}) {
                    Image(systemName: trailingSystemImage)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.elevatedSurface, in: Circle())
                        .overlay(Circle().stroke(AppTheme.line, lineWidth: 1))
                }
                .accessibilityLabel(trailingAccessibilityLabel ?? trailingSystemImage)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(.white)
            Spacer()
            if let actionTitle {
                Text(actionTitle)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }
}

struct NeonProgressRing: View {
    let progress: Double
    let value: String
    let detail: String
    var size: CGFloat = 82

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [AppTheme.accentSoft, AppTheme.accent], center: .center),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(value)
                    .font(.headline.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(width: size, height: size)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            Text(value)
                .font(.title3.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 14, cornerRadius: 16)
    }
}

enum WorkoutHeroKind: String, CaseIterable {
    case push
    case pull
    case legs
    case core
    case full

    var assetName: String {
        switch self {
        case .push: "WorkoutHeroPush"
        case .pull: "WorkoutHeroPull"
        case .legs: "WorkoutHeroLegs"
        case .core: "WorkoutHeroCore"
        case .full: "WorkoutHero"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .push: "推训练背景图"
        case .pull: "拉训练背景图"
        case .legs: "下肢训练背景图"
        case .core: "核心训练背景图"
        case .full: "综合训练背景图"
        }
    }

    var imageAlignment: Alignment {
        switch self {
        case .push, .pull, .core: .leading
        case .legs, .full: .center
        }
    }

    static func resolve(workoutName: String, muscleGroups: [String]) -> WorkoutHeroKind {
        if workoutName.contains("全身") || workoutName.contains("综合") {
            return .full
        }

        var scores: [WorkoutHeroKind: Int] = [
            .push: 0,
            .pull: 0,
            .legs: 0,
            .core: 0
        ]

        addNameScore(to: &scores, kind: .push, terms: ["推", "胸", "肩", "三头"], name: workoutName)
        addNameScore(to: &scores, kind: .pull, terms: ["拉", "背", "二头"], name: workoutName)
        addNameScore(to: &scores, kind: .legs, terms: ["腿", "下肢", "臀", "小腿"], name: workoutName)
        addNameScore(to: &scores, kind: .core, terms: ["核心", "腹"], name: workoutName)

        for group in muscleGroups {
            if containsAny(group, terms: ["胸", "肩", "三头"]) { scores[.push, default: 0] += 1 }
            if containsAny(group, terms: ["背", "二头"]) { scores[.pull, default: 0] += 1 }
            if containsAny(group, terms: ["腿", "下肢", "臀", "小腿"]) { scores[.legs, default: 0] += 1 }
            if containsAny(group, terms: ["核心", "腹"]) { scores[.core, default: 0] += 1 }
        }

        let ranked = scores.sorted { left, right in
            if left.value != right.value { return left.value > right.value }
            return left.key.rawValue < right.key.rawValue
        }
        guard let best = ranked.first, best.value > 0 else { return .full }
        guard ranked.dropFirst().first?.value != best.value else { return .full }
        return best.key
    }

    private static func addNameScore(
        to scores: inout [WorkoutHeroKind: Int],
        kind: WorkoutHeroKind,
        terms: [String],
        name: String
    ) {
        scores[kind, default: 0] += terms.filter(name.contains).count * 2
    }

    private static func containsAny(_ value: String, terms: [String]) -> Bool {
        terms.contains(where: value.contains)
    }
}

struct HeroWorkoutImage: View {
    let kind: WorkoutHeroKind

    init(kind: WorkoutHeroKind = .full) {
        self.kind = kind
    }

    var body: some View {
        GeometryReader { proxy in
            Image(kind.assetName)
                .resizable()
                .scaledToFill()
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: kind.imageAlignment
                )
                .clipped()
                .accessibilityLabel(kind.accessibilityLabel)
        }
    }
}

struct ExerciseMuscleCategory: Equatable {
    let majorGroup: String
    let minorGroup: String
}

enum ExerciseMuscleTaxonomy {
    static let majorGroupOrder = ["胸部", "背部", "肩部", "手臂", "腿部", "核心", "其他"]

    static let minorGroupOrder: [String: [String]] = [
        "胸部": ["上胸", "中胸", "下胸"],
        "背部": ["上背", "中背", "背阔肌"],
        "肩部": ["前束", "中束", "后束"],
        "手臂": ["肱二头肌", "肱三头肌", "前臂"],
        "腿部": ["股四头肌", "腘绳肌", "臀肌", "小腿"],
        "核心": ["腹直肌", "腹斜肌"],
        "其他": ["其他"]
    ]

    static func category(name: String, muscleGroup: String) -> ExerciseMuscleCategory {
        let normalizedName = name.replacingOccurrences(of: " ", with: "").lowercased()
        let normalizedGroup = muscleGroup.replacingOccurrences(of: " ", with: "").lowercased()
        let combined = normalizedName + "|" + normalizedGroup

        let majorGroup: String
        if containsAny(normalizedGroup, terms: ["胸"]) {
            majorGroup = "胸部"
        } else if containsAny(normalizedGroup, terms: ["背", "背阔"]) {
            majorGroup = "背部"
        } else if containsAny(normalizedGroup, terms: ["肩", "三角肌"]) {
            majorGroup = "肩部"
        } else if containsAny(normalizedGroup, terms: ["手臂", "二头", "三头", "前臂"]) {
            majorGroup = "手臂"
        } else if containsAny(normalizedGroup, terms: ["腿", "臀", "小腿", "股四头", "腘绳"]) {
            majorGroup = "腿部"
        } else if containsAny(normalizedGroup, terms: ["核心", "腹", "躯干"]) {
            majorGroup = "核心"
        } else {
            majorGroup = inferredMajorGroup(from: combined)
        }

        let minorGroup: String
        switch majorGroup {
        case "胸部":
            if containsAny(combined, terms: ["上斜", "上胸"]) {
                minorGroup = "上胸"
            } else if containsAny(combined, terms: ["下斜", "下胸"]) {
                minorGroup = "下胸"
            } else {
                minorGroup = "中胸"
            }
        case "背部":
            if containsAny(combined, terms: ["上背"]) {
                minorGroup = "上背"
            } else if containsAny(combined, terms: ["划船", "中背"]) {
                minorGroup = "中背"
            } else {
                minorGroup = "背阔肌"
            }
        case "肩部":
            if containsAny(combined, terms: ["反向飞鸟", "面拉", "后束"]) {
                minorGroup = "后束"
            } else if containsAny(combined, terms: ["侧平举", "三角肌训练", "中束"]) {
                minorGroup = "中束"
            } else {
                minorGroup = "前束"
            }
        case "手臂":
            if containsAny(combined, terms: ["三头", "下压", "臂屈伸"]) {
                minorGroup = "肱三头肌"
            } else if containsAny(combined, terms: ["前臂", "腕弯举"]) {
                minorGroup = "前臂"
            } else {
                minorGroup = "肱二头肌"
            }
        case "腿部":
            if containsAny(combined, terms: ["小腿", "提踵"]) {
                minorGroup = "小腿"
            } else if containsAny(combined, terms: ["腿弯举", "硬拉", "腘绳", "股二头"]) {
                minorGroup = "腘绳肌"
            } else if containsAny(combined, terms: ["髋推", "臀推", "臀部", "臀肌"]) {
                minorGroup = "臀肌"
            } else {
                minorGroup = "股四头肌"
            }
        case "核心":
            minorGroup = containsAny(combined, terms: ["旋转", "伐木", "腹斜"])
                ? "腹斜肌"
                : "腹直肌"
        default:
            minorGroup = "其他"
        }

        return ExerciseMuscleCategory(majorGroup: majorGroup, minorGroup: minorGroup)
    }

    static func orderedMajorGroups(in categories: [ExerciseMuscleCategory]) -> [String] {
        ordered(Set(categories.map(\.majorGroup)), preferredOrder: majorGroupOrder)
    }

    static func orderedMinorGroups(
        for majorGroup: String,
        in categories: [ExerciseMuscleCategory]
    ) -> [String] {
        let available = Set(
            categories
                .filter { $0.majorGroup == majorGroup }
                .map(\.minorGroup)
        )
        return ordered(available, preferredOrder: minorGroupOrder[majorGroup] ?? [])
    }

    private static func inferredMajorGroup(from value: String) -> String {
        if containsAny(value, terms: ["卧推", "夹胸", "飞鸟", "推胸"]) { return "胸部" }
        if containsAny(value, terms: ["划船", "下拉", "引体"]) { return "背部" }
        if containsAny(value, terms: ["肩推", "侧平举", "面拉"]) { return "肩部" }
        if containsAny(value, terms: ["弯举", "下压", "臂屈伸"]) { return "手臂" }
        if containsAny(value, terms: ["深蹲", "腿举", "硬拉", "髋推", "提踵", "弓步"]) { return "腿部" }
        if containsAny(value, terms: ["卷腹", "举腿", "躯干旋转"]) { return "核心" }
        return "其他"
    }

    private static func ordered(_ values: Set<String>, preferredOrder: [String]) -> [String] {
        let preferred = preferredOrder.filter(values.contains)
        let remaining = values.subtracting(preferredOrder).sorted()
        return preferred + remaining
    }

    private static func containsAny(_ value: String, terms: [String]) -> Bool {
        terms.contains(where: value.contains)
    }
}

enum ExerciseGlyphKind: String, CaseIterable {
    case chestPress
    case chestFly
    case shoulderPress
    case lateralRaise
    case armExtension
    case armCurl
    case verticalPull
    case row
    case squat
    case hinge
    case legPress
    case lunge
    case hipThrust
    case legCurl
    case calfRaise
    case olympicLift
    case crunch
    case legRaise
    case rotation
    case general

    static func resolve(name: String, muscleGroup: String, equipment: String) -> ExerciseGlyphKind {
        let normalizedName = name
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        let normalizedGroup = muscleGroup.lowercased()
        let normalizedEquipment = equipment.lowercased()

        func nameContains(_ terms: [String]) -> Bool {
            terms.contains(where: normalizedName.contains)
        }

        if nameContains(["举腿"]) { return .legRaise }
        if nameContains(["卷腹"]) { return .crunch }
        if nameContains(["旋转", "伐木"]) { return .rotation }
        if nameContains(["夹胸", "飞鸟"]) && normalizedGroup.contains("胸") { return .chestFly }
        if nameContains(["侧平举", "反向飞鸟", "面拉", "三角肌"]) { return .lateralRaise }
        if nameContains(["三头下压", "绳索下压", "臂屈伸"]) { return .armExtension }
        if nameContains(["腿弯举", "腿弯曲"]) { return .legCurl }
        if nameContains(["弯举"]) { return .armCurl }
        if nameContains(["划船"]) { return .row }
        if nameContains(["下拉", "引体向上"]) { return .verticalPull }
        if nameContains(["提踵"]) { return .calfRaise }
        if nameContains(["弓步"]) { return .lunge }
        if nameContains(["腿举", "钟摆推举"]) { return .legPress }
        if nameContains(["髋推", "臀推"]) { return .hipThrust }
        if nameContains(["高翻", "抓举", "挺举"]) { return .olympicLift }
        if nameContains(["硬拉"]) { return .hinge }
        if nameContains(["深蹲"]) { return .squat }

        if normalizedGroup.contains("胸") { return .chestPress }
        if normalizedGroup.contains("背") { return .verticalPull }
        if normalizedGroup.contains("肩") { return .shoulderPress }
        if normalizedGroup.contains("手臂") || normalizedGroup.contains("二头") {
            return normalizedEquipment.contains("龙门") ? .armExtension : .armCurl
        }
        if normalizedGroup.contains("三头") { return .armExtension }
        if normalizedGroup.contains("核心") || normalizedGroup.contains("腹") { return .crunch }
        if normalizedGroup.contains("小腿") { return .calfRaise }
        if normalizedGroup.contains("腿") || normalizedGroup.contains("臀") { return .squat }
        return .general
    }
}

struct ExerciseGlyph: View {
    let kind: ExerciseGlyphKind

    var body: some View {
        Canvas { context, size in
            let geometry = kind.geometry
            let scale = min(size.width, size.height) / 24
            let offset = CGPoint(
                x: (size.width - 24 * scale) / 2,
                y: (size.height - 24 * scale) / 2
            )
            let stroke = StrokeStyle(
                lineWidth: max(1.8, 2.05 * scale),
                lineCap: .round,
                lineJoin: .round
            )

            func renderedPoint(_ point: CGPoint) -> CGPoint {
                CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
            }

            for segment in geometry.segments {
                guard let first = segment.first else { continue }
                var path = Path()
                path.move(to: renderedPoint(first))
                for point in segment.dropFirst() {
                    path.addLine(to: renderedPoint(point))
                }
                context.stroke(path, with: .color(AppTheme.accent), style: stroke)
            }

            for circle in geometry.circles {
                let rect = CGRect(
                    x: offset.x + circle.origin.x * scale,
                    y: offset.y + circle.origin.y * scale,
                    width: circle.width * scale,
                    height: circle.height * scale
                )
                context.fill(Path(ellipseIn: rect), with: .color(AppTheme.accent))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct ExerciseGlyphGeometry {
    let segments: [[CGPoint]]
    let circles: [CGRect]
}

private extension ExerciseGlyphKind {
    var geometry: ExerciseGlyphGeometry {
        switch self {
        case .chestPress:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 3, y: 18.5), CGPoint(x: 19, y: 18.5)],
                    [CGPoint(x: 7, y: 15), CGPoint(x: 14, y: 15), CGPoint(x: 18.5, y: 19.5)],
                    [CGPoint(x: 10.5, y: 15), CGPoint(x: 12, y: 10), CGPoint(x: 16.5, y: 7.5)],
                    [CGPoint(x: 7, y: 7.5), CGPoint(x: 21, y: 7.5)]
                ],
                circles: [CGRect(x: 3.5, y: 12.5, width: 3.8, height: 3.8)]
            )
        case .chestFly:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 12, y: 7), CGPoint(x: 12, y: 16)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 7, y: 9), CGPoint(x: 3, y: 6.5)],
                    [CGPoint(x: 13, y: 10), CGPoint(x: 17, y: 9), CGPoint(x: 21, y: 6.5)],
                    [CGPoint(x: 12, y: 16), CGPoint(x: 8, y: 21), CGPoint(x: 12, y: 16), CGPoint(x: 16, y: 21)]
                ],
                circles: [CGRect(x: 10.1, y: 2, width: 3.8, height: 3.8)]
            )
        case .shoulderPress:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 12, y: 8), CGPoint(x: 12, y: 16)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 7, y: 7), CGPoint(x: 7, y: 3)],
                    [CGPoint(x: 13, y: 10), CGPoint(x: 17, y: 7), CGPoint(x: 17, y: 3)],
                    [CGPoint(x: 5, y: 3), CGPoint(x: 19, y: 3)],
                    [CGPoint(x: 12, y: 16), CGPoint(x: 8, y: 21), CGPoint(x: 12, y: 16), CGPoint(x: 16, y: 21)]
                ],
                circles: [CGRect(x: 10.1, y: 3.7, width: 3.8, height: 3.8)]
            )
        case .lateralRaise:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 12, y: 7), CGPoint(x: 12, y: 16)],
                    [CGPoint(x: 2.5, y: 8.5), CGPoint(x: 7, y: 9.5), CGPoint(x: 12, y: 10), CGPoint(x: 17, y: 9.5), CGPoint(x: 21.5, y: 8.5)],
                    [CGPoint(x: 12, y: 16), CGPoint(x: 8, y: 21), CGPoint(x: 12, y: 16), CGPoint(x: 16, y: 21)]
                ],
                circles: [CGRect(x: 10.1, y: 2, width: 3.8, height: 3.8)]
            )
        case .armExtension:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 8, y: 8), CGPoint(x: 8, y: 20)],
                    [CGPoint(x: 8, y: 10), CGPoint(x: 13, y: 11.5), CGPoint(x: 17, y: 17)],
                    [CGPoint(x: 18.5, y: 3), CGPoint(x: 18.5, y: 17)],
                    [CGPoint(x: 15.5, y: 17), CGPoint(x: 20.5, y: 17)],
                    [CGPoint(x: 6, y: 20), CGPoint(x: 12, y: 20)]
                ],
                circles: [CGRect(x: 4.3, y: 3, width: 3.8, height: 3.8)]
            )
        case .armCurl:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 8, y: 8), CGPoint(x: 8, y: 20)],
                    [CGPoint(x: 8, y: 10), CGPoint(x: 12, y: 15), CGPoint(x: 17, y: 9)],
                    [CGPoint(x: 15.5, y: 7.5), CGPoint(x: 19.5, y: 10.5)],
                    [CGPoint(x: 6, y: 20), CGPoint(x: 12, y: 20)]
                ],
                circles: [CGRect(x: 4.3, y: 3, width: 3.8, height: 3.8)]
            )
        case .verticalPull:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 3, y: 3), CGPoint(x: 21, y: 3)],
                    [CGPoint(x: 12, y: 8), CGPoint(x: 12, y: 16)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 7, y: 7), CGPoint(x: 5, y: 3), CGPoint(x: 7, y: 7), CGPoint(x: 12, y: 10), CGPoint(x: 17, y: 7), CGPoint(x: 19, y: 3)],
                    [CGPoint(x: 12, y: 16), CGPoint(x: 8, y: 21), CGPoint(x: 12, y: 16), CGPoint(x: 16, y: 21)]
                ],
                circles: [CGRect(x: 10.1, y: 3.9, width: 3.8, height: 3.8)]
            )
        case .row:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 4, y: 18), CGPoint(x: 11, y: 18)],
                    [CGPoint(x: 8, y: 13), CGPoint(x: 12, y: 15), CGPoint(x: 18, y: 18)],
                    [CGPoint(x: 11, y: 14), CGPoint(x: 15, y: 11), CGPoint(x: 20, y: 12)],
                    [CGPoint(x: 20, y: 5), CGPoint(x: 20, y: 20)]
                ],
                circles: [CGRect(x: 4.1, y: 9, width: 3.8, height: 3.8)]
            )
        case .squat:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 4, y: 8), CGPoint(x: 20, y: 8)],
                    [CGPoint(x: 12, y: 8), CGPoint(x: 13, y: 14)],
                    [CGPoint(x: 13, y: 14), CGPoint(x: 8, y: 16), CGPoint(x: 6, y: 21), CGPoint(x: 8, y: 16), CGPoint(x: 13, y: 14), CGPoint(x: 18, y: 16), CGPoint(x: 20, y: 21)],
                    [CGPoint(x: 8, y: 8), CGPoint(x: 6.5, y: 11), CGPoint(x: 8, y: 8), CGPoint(x: 16, y: 8), CGPoint(x: 17.5, y: 11)]
                ],
                circles: [CGRect(x: 10.1, y: 3, width: 3.8, height: 3.8)]
            )
        case .hinge:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 8, y: 8), CGPoint(x: 14, y: 12), CGPoint(x: 18, y: 17)],
                    [CGPoint(x: 14, y: 12), CGPoint(x: 11, y: 21), CGPoint(x: 14, y: 12), CGPoint(x: 18, y: 21)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 8.5, y: 17)],
                    [CGPoint(x: 4, y: 18), CGPoint(x: 21, y: 18)]
                ],
                circles: [CGRect(x: 4.1, y: 3.7, width: 3.8, height: 3.8)]
            )
        case .legPress:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 4, y: 19), CGPoint(x: 9, y: 13), CGPoint(x: 14, y: 15)],
                    [CGPoint(x: 13, y: 15), CGPoint(x: 18, y: 9), CGPoint(x: 21, y: 11)],
                    [CGPoint(x: 18, y: 4), CGPoint(x: 22, y: 8)],
                    [CGPoint(x: 4, y: 20.5), CGPoint(x: 12, y: 20.5)]
                ],
                circles: [CGRect(x: 3.7, y: 9.2, width: 3.8, height: 3.8)]
            )
        case .lunge:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 11, y: 7), CGPoint(x: 12, y: 14)],
                    [CGPoint(x: 12, y: 14), CGPoint(x: 7, y: 17), CGPoint(x: 3, y: 21), CGPoint(x: 7, y: 17), CGPoint(x: 12, y: 14), CGPoint(x: 18, y: 18), CGPoint(x: 21, y: 18)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 6, y: 12), CGPoint(x: 11, y: 10), CGPoint(x: 16, y: 12)]
                ],
                circles: [CGRect(x: 9.1, y: 2, width: 3.8, height: 3.8)]
            )
        case .hipThrust:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 3, y: 15), CGPoint(x: 8, y: 15)],
                    [CGPoint(x: 7, y: 13), CGPoint(x: 14, y: 11), CGPoint(x: 19, y: 14)],
                    [CGPoint(x: 19, y: 14), CGPoint(x: 17, y: 20), CGPoint(x: 19, y: 14), CGPoint(x: 22, y: 20)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 17, y: 10)]
                ],
                circles: [CGRect(x: 3.8, y: 9.7, width: 3.8, height: 3.8)]
            )
        case .legCurl:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 3, y: 15), CGPoint(x: 15, y: 15)],
                    [CGPoint(x: 7, y: 12), CGPoint(x: 14, y: 13), CGPoint(x: 18, y: 9), CGPoint(x: 20, y: 6)],
                    [CGPoint(x: 16, y: 17.5), CGPoint(x: 21, y: 17.5)]
                ],
                circles: [CGRect(x: 2.8, y: 9, width: 3.8, height: 3.8)]
            )
        case .calfRaise:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 11, y: 7), CGPoint(x: 11, y: 15)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 7, y: 12), CGPoint(x: 11, y: 10), CGPoint(x: 15, y: 12)],
                    [CGPoint(x: 11, y: 15), CGPoint(x: 9, y: 20), CGPoint(x: 6, y: 20), CGPoint(x: 9, y: 20), CGPoint(x: 11, y: 15), CGPoint(x: 15, y: 19), CGPoint(x: 18, y: 18)],
                    [CGPoint(x: 14, y: 21), CGPoint(x: 22, y: 21)]
                ],
                circles: [CGRect(x: 9.1, y: 2, width: 3.8, height: 3.8)]
            )
        case .olympicLift:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 4, y: 3), CGPoint(x: 20, y: 3)],
                    [CGPoint(x: 12, y: 9), CGPoint(x: 12, y: 15)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 7, y: 7), CGPoint(x: 6, y: 3), CGPoint(x: 7, y: 7), CGPoint(x: 12, y: 10), CGPoint(x: 17, y: 7), CGPoint(x: 18, y: 3)],
                    [CGPoint(x: 12, y: 15), CGPoint(x: 7, y: 20), CGPoint(x: 4, y: 20), CGPoint(x: 7, y: 20), CGPoint(x: 12, y: 15), CGPoint(x: 17, y: 20), CGPoint(x: 20, y: 20)]
                ],
                circles: [CGRect(x: 10.1, y: 4, width: 3.8, height: 3.8)]
            )
        case .crunch:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 7, y: 10), CGPoint(x: 11, y: 13), CGPoint(x: 14, y: 17)],
                    [CGPoint(x: 14, y: 17), CGPoint(x: 19, y: 17), CGPoint(x: 21, y: 20)],
                    [CGPoint(x: 12, y: 14), CGPoint(x: 8, y: 17)],
                    [CGPoint(x: 4, y: 21), CGPoint(x: 22, y: 21)]
                ],
                circles: [CGRect(x: 3, y: 6, width: 3.8, height: 3.8)]
            )
        case .legRaise:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 4, y: 3), CGPoint(x: 20, y: 3)],
                    [CGPoint(x: 12, y: 8), CGPoint(x: 12, y: 15)],
                    [CGPoint(x: 11, y: 9), CGPoint(x: 7, y: 3), CGPoint(x: 11, y: 9), CGPoint(x: 17, y: 3)],
                    [CGPoint(x: 12, y: 15), CGPoint(x: 18, y: 15), CGPoint(x: 21, y: 12)]
                ],
                circles: [CGRect(x: 10.1, y: 4, width: 3.8, height: 3.8)]
            )
        case .rotation:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 12, y: 7), CGPoint(x: 12, y: 16)],
                    [CGPoint(x: 11, y: 10), CGPoint(x: 16, y: 9), CGPoint(x: 21, y: 6)],
                    [CGPoint(x: 12, y: 16), CGPoint(x: 8, y: 21), CGPoint(x: 12, y: 16), CGPoint(x: 16, y: 21)],
                    [CGPoint(x: 19, y: 3), CGPoint(x: 22, y: 6), CGPoint(x: 19, y: 9)]
                ],
                circles: [CGRect(x: 10.1, y: 2, width: 3.8, height: 3.8)]
            )
        case .general:
            ExerciseGlyphGeometry(
                segments: [
                    [CGPoint(x: 5, y: 8), CGPoint(x: 5, y: 16)],
                    [CGPoint(x: 8, y: 10), CGPoint(x: 8, y: 14)],
                    [CGPoint(x: 8, y: 12), CGPoint(x: 16, y: 12)],
                    [CGPoint(x: 16, y: 10), CGPoint(x: 16, y: 14)],
                    [CGPoint(x: 19, y: 8), CGPoint(x: 19, y: 16)]
                ],
                circles: []
            )
        }
    }
}

enum TrainingFormatters {
    static func weight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(1, Int(end.timeIntervalSince(start) / 60))
        return "\(minutes) 分钟"
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
