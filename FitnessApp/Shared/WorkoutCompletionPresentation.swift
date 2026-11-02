import SwiftUI
import UIKit

extension WorkoutCompletionFeedback {
    func receiveSavedCompletion(session: WorkoutSession, logs: [SetLog],
                                allDaySchedulesCompleted: Bool? = nil, now: Date = .now) -> WorkoutCompletionSummary? {
        let workSets = logs.filter { $0.sessionID == session.id && !$0.isWarmup && $0.reductionOrder == nil }
        return receiveSavedCompletion(record: WorkoutCompletionRecord(sessionID: session.id,
            name: session.templateName, startedAt: session.startedAt, completedAt: session.completedAt,
            isCompleted: session.status == .completed, isHistorical: !session.importIdentifier.isEmpty,
            startTimeKnown: session.isStartTimeKnown, completedWorkSets: workSets.filter(\.isCompleted).count,
            plannedWorkSets: workSets.count), allDaySchedulesCompleted: allDaySchedulesCompleted, now: now)
    }
}

struct WorkoutCompletionCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: WorkoutCompletionSummary
    let onDismiss: () -> Void
    @State private var phase: Phase = .waiting
    @AccessibilityFocusState private var titleFocused: Bool

    private enum Phase: Equatable {
        case waiting
        case celebrating(Date)
        case settled
        case dismissed
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.ink.opacity(0.18).ignoresSafeArea()
                completionCard(maximumHeight: max(160, geometry.size.height - AppTheme.pageMargin * 2))
                    .frame(maxWidth: 360)
                    .padding(.horizontal, AppTheme.pageMargin)
                    .scaleEffect(phase == .waiting && !reduceMotion ? 0.96 : 1)
                    .opacity(phase == .waiting ? 0 : 1)
                    .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.08), value: phase == .waiting)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .task(id: summary.id) {
            guard phase == .waiting else { return }
            phase = .celebrating(.now)
            titleFocused = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
            do {
                try await Task.sleep(for: .milliseconds(1_500))
                guard phase != .dismissed else { return }
                phase = .settled
                try await Task.sleep(for: .milliseconds(4_500))
                guard !Task.isCancelled else { return }
                close()
            } catch {
                return
            }
        }
    }

    private func completionCard(maximumHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 64, height: 64)
                    .background(AppTheme.accent, in: Circle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24).padding(.bottom, 16)
                    .accessibilityHidden(true)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: AppTheme.minimumTouchTarget, height: AppTheme.minimumTouchTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("关闭训练完成反馈")
            }

            ViewThatFits(in: .vertical) {
                cardDetails.fixedSize(horizontal: false, vertical: true)
                ScrollView { cardDetails }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: max(0, maximumHeight - 104))
                    .accessibilityIdentifier("训练完成-内容滚动")
            }
        }
        .background {
            glassSurface
        }
        .background(alignment: .top) {
            if case let .celebrating(startedAt) = phase, !reduceMotion {
                CompletionFireworks(startedAt: startedAt)
                    .frame(height: 220)
                    .offset(y: -100)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("训练完成反馈")
        .accessibilityIdentifier("训练完成-卡片")
    }

    private var cardDetails: some View {
        VStack(spacing: 20) {
            Text(summary.title)
                .font(AppTheme.pageTitle)
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 16) { metrics }
                } else {
                    HStack(alignment: .top, spacing: 16) { metrics }
                }
            }
            .accessibilityRepresentation {
                Text("\(summary.completedWorkSets) 个工作组 · \(summary.durationLabel)")
                    .accessibilityIdentifier("训练完成-实际总结")
            }

            Text("只统计已勾选的工作组 · 时长包含休息")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)

            Button("完成", action: close)
                .buttonStyle(SprintPrimaryButtonStyle())
                .accessibilityIdentifier("训练完成-完成按钮")
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    private var metrics: some View {
        Group {
            metric(value: String(summary.completedWorkSets), label: "个工作组")
            metric(value: durationValue, label: "训练时长")
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(AppTheme.metricValue).foregroundStyle(AppTheme.ink)
            Text(label).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationValue: String {
        guard let seconds = summary.durationSeconds else { return "未记录" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder private var glassSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        if reduceTransparency {
            shape.fill(AppTheme.surface)
        } else if #available(iOS 26.0, *) {
            shape.fill(.clear).glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
                .shadow(color: AppTheme.ink.opacity(0.12), radius: 20, y: 8)
        }
    }

    private func close() {
        guard phase != .dismissed else { return }
        phase = .dismissed
        onDismiss()
    }
}

private struct CompletionFireworks: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                let colors = [AppTheme.accent, AppTheme.accentSoft, AppTheme.background]
                for burst in 0..<2 {
                    let origin = CGPoint(x: burst == 0 ? 10 : size.width - 10, y: burst == 0 ? 100 : 88)
                    for index in 0..<22 {
                        let delay = Double(burst) * 0.12 + Double(index % 4) * 0.018
                        let age = elapsed - delay
                        let lifetime = 0.82 + Double((index * 13) % 5) * 0.085
                        guard age > 0, age < lifetime else { continue }
                        let angle = Double(index) * .pi * 2 / 22 + Double(burst) * 0.17
                        let speed = 145 + Double((index * 37) % 90)
                        let head = position(age: age, angle: angle, speed: speed, origin: origin)
                        let tail = position(age: max(0, age - 0.055), angle: angle, speed: speed, origin: origin)
                        let color = colors[(index + burst) % colors.count]
                        var spark = context
                        spark.opacity = min(age / 0.05, 1) * pow(1 - age / lifetime, 1.2)
                        spark.addFilter(.shadow(color: color.opacity(0.65), radius: 3))
                        var trail = Path()
                        trail.move(to: tail)
                        trail.addLine(to: head)
                        spark.stroke(trail, with: .color(color), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                        let diameter: CGFloat = index % 5 == 0 ? 3.0 : 1.8
                        spark.fill(Path(ellipseIn: CGRect(x: head.x - diameter / 2, y: head.y - diameter / 2,
                            width: diameter, height: diameter)), with: .color(color))
                    }
                }
            }
        }
    }

    private func position(age: Double, angle: Double, speed: Double, origin: CGPoint) -> CGPoint {
        let distance = speed * (1 - exp(-2.8 * age)) / 2.8
        return CGPoint(x: origin.x + CGFloat(cos(angle) * distance),
                       y: origin.y + CGFloat(sin(angle) * distance + 24 * age * age))
    }
}
