import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.62, green: 0.91, blue: 0.02)
    static let accentSoft = Color(red: 0.45, green: 0.70, blue: 0.00)
    static let background = Color(red: 0.018, green: 0.022, blue: 0.025)
    static let surface = Color(red: 0.055, green: 0.067, blue: 0.073)
    static let elevatedSurface = Color(red: 0.075, green: 0.090, blue: 0.098)
    static let line = Color.white.opacity(0.075)
    static let secondaryText = Color.white.opacity(0.56)
    static let tabBar = Color(red: 0.025, green: 0.031, blue: 0.034)
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
}

struct CardSurface: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
    }
}

extension View {
    func cardSurface(padding: CGFloat = 16, cornerRadius: CGFloat = 18) -> some View {
        modifier(CardSurface(padding: padding, cornerRadius: cornerRadius))
    }

    func screenBackground() -> some View {
        background(AppTheme.screenGradient.ignoresSafeArea())
    }

    func neonButtonStyle() -> some View {
        font(.subheadline.bold())
            .foregroundStyle(.black)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            if let trailingSystemImage {
                Button(action: trailingAction ?? {}) {
                    Image(systemName: trailingSystemImage)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
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

struct HeroWorkoutImage: View {
    var body: some View {
        GeometryReader { proxy in
            Image("WorkoutHero")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }
}

enum TrainingFormatters {
    static func weight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }

    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(1, Int(end.timeIntervalSince(start) / 60))
        return "\(minutes) 分钟"
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
