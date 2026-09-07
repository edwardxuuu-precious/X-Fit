import SwiftData
import SwiftUI

/// Training intention only. Does not read or write pain markers.
struct MuscleSelectionView: View {
    @Binding var selectedGroups: Set<String>
    @State private var side: BodyMapViewSide = .front
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("身体视角", selection: $side) {
                Text("正面").tag(BodyMapViewSide.front)
                Text("背面").tag(BodyMapViewSide.back)
            }.pickerStyle(.segmented)
            Text("按身体自身左右").font(.caption).foregroundStyle(AppTheme.secondaryText)
            TrainingMuscleFigure(side: side, selected: selectedGroups, counts: [:], onTap: toggle)
                .frame(height: 340)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondaryText)
                TextField("搜索肌群，如胸、肩、腿", text: $search)
                    .textFieldStyle(.plain).accessibilityIdentifier("肌群中文搜索")
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(AppTheme.elevatedSurface, in: Capsule())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74))], spacing: 8) {
                ForEach(visibleGroups, id: \.self) { group in
                    Button { toggle(group) } label: {
                        HStack(spacing: 5) {
                            Text(group)
                            Image(systemName: selectedGroups.contains(group) ? "checkmark.circle.fill" : "circle").font(.caption)
                        }.font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selectedGroups.contains(group) ? AppTheme.accent : .primary)
                            .background(selectedGroups.contains(group) ? AppTheme.accent.opacity(0.08) : Color.clear, in: Capsule())
                            .overlay { Capsule().stroke(selectedGroups.contains(group) ? AppTheme.accent : AppTheme.secondaryText.opacity(0.35), lineWidth: 1) }
                    }.buttonStyle(.plain).accessibilityValue(selectedGroups.contains(group) ? "已选择" : "未选择")
                }
            }
            HStack {
                Text(selectedGroups.isEmpty ? "点击身体区域或文字选择" : selectedGroups.sorted().joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                Spacer()
                if !selectedGroups.isEmpty {
                    Button("清除") { selectedGroups.removeAll() }
                        .font(.caption).frame(minWidth: 44, minHeight: 44)
                }
            }
        }.accessibilityElement(children: .contain)
    }
    private var visibleGroups: [String] {
        let choices = MuscleCoverageService.groups + selectedGroups.filter { !MuscleCoverageService.groups.contains($0) }.sorted()
        guard !search.isEmpty else { return choices }
        let matching = MuscleCoverageService.groups(in: search)
        return choices.filter { $0.localizedCaseInsensitiveContains(search) || matching.contains($0) }
    }
    private func toggle(_ group: String) {
        if selectedGroups.contains(group) { selectedGroups.remove(group) } else { selectedGroups.insert(group) }
    }
}

struct MuscleCoverageView: View {
    @Query private var sessions: [WorkoutSession]
    @Query private var snapshots: [SessionExercise]
    @Query private var logs: [SetLog]
    @State private var side: BodyMapViewSide = .front
    @State private var selected: Set<String> = []
    private var coverage: [MuscleCoverageValue] {
        MuscleCoverageService.coverage(from: Date.now.addingDays(-6).startOfDay, through: .now,
            sessions: sessions, snapshots: snapshots, logs: logs)
    }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("实际训练分布").font(.headline)
                Spacer()
                Text("近 7 天").font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Picker("身体视角", selection: $side) {
                Text("正面").tag(BodyMapViewSide.front); Text("背面").tag(BodyMapViewSide.back)
            }.pickerStyle(.segmented)
            Text("按身体自身左右").font(.caption).foregroundStyle(AppTheme.secondaryText)
            TrainingMuscleFigure(side: side, selected: selected,
                counts: Dictionary(uniqueKeysWithValues: coverage.map { ($0.group, $0.completedSets) })) { group in
                    selected = selected.contains(group) ? [] : [group]
                }.frame(height: 340)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                ForEach(coverage.filter { selected.isEmpty || selected.contains($0.group) }) { value in
                    HStack {
                        Text(value.group).font(.subheadline)
                        Spacer()
                        Text("\(value.completedSets) 组").font(.subheadline.monospacedDigit())
                            .foregroundStyle(value.completedSets > 0 ? AppTheme.accent : AppTheme.secondaryText)
                    }
                }
            }
            Text("仅计已完成工作组；复合动作可计入多个肌群。灰色表示没有相应记录，不表示恢复状态。")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        }
        .background(AppTheme.background)
        .navigationTitle("实际训练分布")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TrainingMuscleFigure: View {
    let side: BodyMapViewSide
    let selected: Set<String>
    let counts: [String: Int]
    let onTap: (String) -> Void

    private var regions: [BodyRegionDefinition] {
        BodyRegionCatalog.all.filter { $0.side == side && MuscleCoverageService.group(for: $0.id) != nil }
    }
    var body: some View {
        GeometryReader { proxy in
            // Preserve the drawing's proportions rather than stretching a short body to fill its box.
            let scale = min(proxy.size.width / 300, proxy.size.height / 600)
            let size = CGSize(width: 300 * scale, height: 600 * scale)
            ZStack {
                AnatomyDrawing.base(side: side).applying(CGAffineTransform(scaleX: scale, y: scale))
                    .fill(Color(white: 0.16))
                AnatomyDrawing.head.applying(CGAffineTransform(scaleX: scale, y: scale))
                    .fill(Color(white: 0.16))
                ForEach(regions) { region in
                    regionView(region, scale: scale)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                let point = CGPoint(x: tap.location.x / scale, y: tap.location.y / scale)
                let exact = regions.first { AnatomyDrawing.muscle($0).contains(point) }
                let nearby = exact ?? regions.filter {
                    let box = AnatomyDrawing.muscle($0).boundingRect
                    return box.insetBy(dx: -max(0, (44 / scale - box.width) / 2),
                                       dy: -max(0, (44 / scale - box.height) / 2)).contains(point)
                }.min {
                    let a = AnatomyDrawing.muscle($0).boundingRect
                    let b = AnatomyDrawing.muscle($1).boundingRect
                    return hypot(point.x - a.midX, point.y - a.midY) < hypot(point.x - b.midX, point.y - b.midY)
                }
                if let region = nearby, let group = MuscleCoverageService.group(for: region.id) { onTap(group) }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func regionView(_ region: BodyRegionDefinition, scale: CGFloat) -> some View {
        let group = MuscleCoverageService.group(for: region.id) ?? ""
        let path = AnatomyDrawing.muscle(region).applying(CGAffineTransform(scaleX: scale, y: scale))
        let box = path.boundingRect
        let local = path.applying(CGAffineTransform(translationX: -box.minX, y: -box.minY))
        let active = selected.contains(group)
        return local.fill(fill(group))
            .overlay { local.stroke(active ? AppTheme.accent : Color(white: 0.10),
                                    style: StrokeStyle(lineWidth: active ? 1.25 : 0.8, lineJoin: .round)) }
            .frame(width: box.width, height: box.height)
            .frame(minWidth: 44, minHeight: 44)
            .position(x: box.midX, y: box.midY)
            .accessibilityElement()
            .accessibilityLabel("\(group)，\(region.name)")
            .accessibilityValue(active ? "已选择" : counts[group].map { "已完成 \($0) 组" } ?? "未选择")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap(group) }
            .accessibilityIdentifier("training-region-\(region.id)")
    }
    private func fill(_ group: String) -> Color {
        if selected.contains(group) { return Color(red: 0.43, green: 0.61, blue: 0.15) }
        if let count = counts[group], count > 0 {
            return AppTheme.accent.opacity(0.24 + 0.4 * Double(count) / Double(max(1, counts.values.max() ?? 1)))
        }
        return Color(white: 0.23)
    }
}

/// Original vector anatomy on a shared 300 × 600 artboard. The same paths own
/// both visible muscle boundaries and hit testing; pain-map geometry is untouched.
private enum AnatomyDrawing {
    // Static path commands are restricted to M/L/C/Q/Z, with explicit whitespace.
    private static func draw(_ commands: String) -> Path {
        let tokens = commands.split(separator: " "); var i = 0; var path = Path()
        func point() -> CGPoint {
            let x = Double(tokens[i])!; let y = Double(tokens[i + 1])!; i += 2
            return CGPoint(x: x, y: y)
        }
        while i < tokens.count {
            let command = tokens[i]; i += 1
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C": let a = point(); let b = point(); path.addCurve(to: point(), control1: a, control2: b)
            case "Q": let a = point(); path.addQuadCurve(to: point(), control: a)
            case "Z": path.closeSubpath()
            default: preconditionFailure("Unsupported anatomy path command")
            }
        }
        return path
    }
    private static func pair(_ commands: String) -> Path {
        let left = draw(commands); var result = left
        result.addPath(left.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 300, ty: 0)))
        return result
    }
    static var head: Path {
        draw("M 150 7 C 132 7 125 17 126 35 L 129 53 Q 130 64 139 68 L 137 84 Q 150 91 163 84 L 161 68 Q 170 64 171 53 L 174 35 C 175 17 168 7 150 7 Z")
    }
    static func base(side: BodyMapViewSide) -> Path {
        var result = draw("M 150 7 C 132 7 125 17 126 35 L 129 53 Q 130 64 139 68 L 139 80 L 161 80 L 161 68 Q 170 64 171 53 L 174 35 C 175 17 168 7 150 7 Z")
        result.addPath(pair("M 139 72 L 132 87 Q 121 93 104 96 C 83 96 71 107 68 126 L 56 166 Q 49 185 49 201 L 30 256 L 23 275 Q 16 284 14 299 L 10 308 Q 14 314 21 309 L 29 297 L 35 291 L 36 282 L 46 263 Q 63 238 68 213 L 72 204 L 84 178 L 92 153 Q 106 180 112 205 L 117 232 Q 116 250 110 269 Q 99 293 99 320 L 102 365 L 110 410 Q 101 437 105 462 L 117 523 L 116 556 L 106 575 Q 104 586 116 589 L 135 589 L 138 581 L 135 552 L 137 516 Q 149 465 138 431 L 138 411 L 143 366 L 147 320 L 150 298 L 150 73 Z"))
        return result
    }
    static func muscle(_ region: BodyRegionDefinition) -> Path {
        let id = region.id
        let raw: String
        if id == "front-chest" {
            return pair("M 148 112 C 132 105 113 105 102 110 Q 94 120 94 134 C 103 152 122 161 147 151 Z")
        } else if id == "front-abdomen" {
            return pair("M 146 158 Q 135 157 130 163 L 130 177 Q 137 182 147 176 Z M 147 181 Q 136 185 130 182 L 130 199 Q 136 204 147 199 Z M 147 204 L 131 206 L 133 224 Q 139 228 147 223 Z M 147 228 L 134 232 Q 135 244 149 255 Z M 109 157 L 124 166 L 123 178 L 113 170 Z M 113 175 L 124 183 L 124 197 L 117 190 Z M 118 196 L 126 206 L 128 230 L 120 216 Z M 120 224 L 130 237 L 147 262 L 147 277 Q 129 258 118 247 Z")
        } else if id == "back-upper" {
            return pair("M 139 78 L 148 84 L 148 158 Q 133 147 120 122 L 104 101 L 129 91 Z M 105 111 L 122 132 L 145 165 L 129 175 Q 108 157 100 139 Z")
        } else if id == "back-lower" {
            return pair("M 147 172 L 134 187 L 133 218 L 122 248 L 148 237 Z")
        } else if id.contains("shoulder") {
            raw = "M 101 101 Q 77 98 71 119 L 66 137 Q 81 144 96 133 L 106 110 Z M 70 141 L 86 143 L 75 159 L 61 171 Z"
        } else if id.contains("biceps") {
            raw = "M 90 143 Q 80 145 71 161 L 60 185 Q 60 194 67 200 Q 81 183 86 164 Z M 59 169 L 52 193 L 52 207 L 60 201 L 63 186 Z"
        } else if id.contains("triceps") {
            raw = "M 87 143 L 73 151 Q 63 167 59 188 L 66 204 Q 76 194 81 180 Z M 69 148 Q 56 170 52 195 L 56 205 L 61 187 L 72 163 Z"
        } else if id.contains("forearm") {
            raw = "M 52 210 L 62 205 Q 64 224 48 249 L 34 276 L 28 275 Q 35 243 43 228 Z M 65 211 Q 63 240 43 263 L 37 277 L 34 274 L 48 244 Z"
        } else if id.contains("quadriceps") {
            raw = "M 111 269 Q 104 293 105 331 L 109 368 Q 111 387 119 398 L 116 374 L 112 330 L 116 285 Z M 119 271 Q 129 278 131 300 L 127 333 L 119 371 L 116 346 L 115 312 Z M 134 283 L 144 302 L 139 337 Q 136 362 126 384 L 122 388 L 128 349 L 135 310 Z M 137 370 Q 142 391 134 403 Q 128 409 123 400 L 127 387 Z"
        } else if id.contains("hamstring") {
            raw = "M 109 303 Q 120 312 128 309 L 124 348 L 115 401 Q 106 376 106 348 Z M 131 309 L 145 300 L 140 350 L 134 400 L 124 403 L 130 348 Z"
        } else if id.contains("shin") {
            raw = "M 114 429 Q 108 445 113 466 L 123 519 L 122 550 L 130 552 L 132 509 L 127 462 L 121 430 Z M 127 427 Q 143 443 135 477 L 132 500 L 126 456 Z M 109 435 L 109 461 L 119 510 L 116 476 Z"
        } else if id.contains("calf") {
            raw = "M 116 428 Q 102 449 111 478 L 122 504 L 126 480 L 125 437 Z M 129 431 Q 145 443 138 469 L 128 493 L 126 478 Z M 122 509 L 129 507 L 129 551 L 122 552 Z"
        } else if id.contains("glute") {
            raw = "M 119 248 Q 132 241 147 244 L 147 280 Q 140 303 121 303 Q 104 299 106 280 Z"
        } else if id.contains("lat") {
            raw = "M 101 145 L 117 161 L 134 180 L 129 212 L 119 234 Q 115 207 108 186 Z"
        } else {
            return Path()
        }
        let left = draw(raw)
        // The reference paths depict screen-left. Front-right and back-left
        // mean the person's own side, matching the existing region identifiers.
        let onRight = MuscleCoverageService.horizontalPosition(for: region) > 0.5
        return onRight ? left.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 300, ty: 0)) : left
    }
}
