import Foundation

enum TrainingGoalMode: String, CaseIterable, Identifiable {
    case cuttingVolume
    case balancedProgression

    static let storageKey = "training.goal.mode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cuttingVolume:
            return "减脂 · 容量优先"
        case .balancedProgression:
            return "均衡 · 渐进超负荷"
        }
    }

    var detail: String {
        switch self {
        case .cuttingVolume:
            return "优先保留有效组数和训练容量；恢复与 RIR 允许时才微加重。"
        case .balancedProgression:
            return "达到次数上限且余力充足时，逐步增加重量。"
        }
    }
}

enum ProgressionRecommendation: Equatable {
    case increase(percent: Double)
    case maintain
    case reduce

    func title(for goalMode: TrainingGoalMode) -> String {
        switch (goalMode, self) {
        case (.cuttingVolume, .increase):
            return "可选微加重 · 组数不减"
        case (.cuttingVolume, .maintain):
            return "维持重量与组数"
        case (.cuttingVolume, .reduce):
            return "减重保组数"
        case (.balancedProgression, .increase):
            return "建议小幅加重"
        case (.balancedProgression, .maintain):
            return "建议保持重量"
        case (.balancedProgression, .reduce):
            return "建议降低重量"
        }
    }
}

struct ProgressionAssessment: Equatable {
    let recommendation: ProgressionRecommendation
    let title: String
    let detail: String
    let currentVolume: Double
    let previousVolume: Double?
    let hasCompleteRIR: Bool
}

enum TrainingMetrics {
    static func volume(for logs: [SetLog]) -> Double {
        logs
            .filter(\.isCompleted)
            .reduce(0) { $0 + ($1.actualWeight * Double($1.actualReps)) }
    }

    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return weight * (1 + Double(reps) / 30)
    }

    static func progression(
        completedReps: [Int],
        minimumReps: Int,
        maximumReps: Int,
        rirValues: [Int]
    ) -> ProgressionRecommendation {
        guard !completedReps.isEmpty else { return .maintain }

        if completedReps.contains(where: { $0 < minimumReps }) || rirValues.contains(0) {
            return .reduce
        }

        let allAtTop = completedReps.allSatisfy { $0 >= maximumReps }
        let effortControlled = rirValues.count == completedReps.count
            && rirValues.allSatisfy { $0 >= 2 }
        return allAtTop && effortControlled ? .increase(percent: 0.025) : .maintain
    }

    static func progressionAssessment(
        weights: [Double],
        completedReps: [Int],
        minimumReps: Int,
        maximumReps: Int,
        rirValues: [Int?],
        previousVolume: Double? = nil,
        goalMode: TrainingGoalMode
    ) -> ProgressionAssessment {
        let pairedCount = min(weights.count, completedReps.count)
        let currentVolume = (0..<pairedCount).reduce(0.0) {
            $0 + max(0, weights[$1]) * Double(max(0, completedReps[$1]))
        }
        let hasCompleteRIR = !completedReps.isEmpty
            && rirValues.count == completedReps.count
            && rirValues.allSatisfy { $0 != nil }
        let knownRIR = rirValues.compactMap { $0 }
        let missedMinimum = completedReps.contains { $0 < minimumReps }
        let reachedFailure = knownRIR.contains(0)

        let recommendation: ProgressionRecommendation
        if missedMinimum || reachedFailure {
            recommendation = .reduce
        } else if goalMode == .cuttingVolume {
            let meaningfulVolumeDrop = previousVolume.map {
                $0 > 0 && currentVolume < $0 * 0.9
            } ?? false
            let allAtTop = !completedReps.isEmpty
                && completedReps.allSatisfy { $0 >= maximumReps }
            let ampleReserve = hasCompleteRIR
                && knownRIR.allSatisfy { $0 >= 3 }
            let volumeMaintained = previousVolume.map {
                $0 <= 0 || currentVolume >= $0 * 0.98
            } ?? false

            if meaningfulVolumeDrop {
                recommendation = .reduce
            } else if allAtTop && ampleReserve && volumeMaintained {
                recommendation = .increase(percent: 0.025)
            } else {
                recommendation = .maintain
            }
        } else {
            recommendation = progression(
                completedReps: completedReps,
                minimumReps: minimumReps,
                maximumReps: maximumReps,
                rirValues: knownRIR
            )
        }

        let title: String
        let detail: String
        if completedReps.isEmpty {
            title = "建立训练量基线"
            detail = goalMode == .cuttingVolume
                ? "从 4 个工作组和适中重量开始，记录每组 RIR 后再调整重量。"
                : "先完成一次真实训练，再根据次数和 RIR 生成进阶建议。"
        } else if case .reduce = recommendation {
            title = recommendation.title(for: goalMode)
            detail = goalMode == .cuttingVolume
                ? "次数低于目标、出现 0 RIR，或容量明显下降；建议减轻约 5–10%，优先完成原定组数。"
                : "有组未达到最低次数或已经力竭，建议降低重量并恢复动作质量。"
        } else if !hasCompleteRIR {
            title = recommendation.title(for: goalMode)
            detail = "RIR 没有完整记录，本次不据此加重；下次先保持组数与工作重量并补记 RIR。"
        } else {
            title = recommendation.title(for: goalMode)
            switch (goalMode, recommendation) {
            case (.cuttingVolume, .increase(let percent)):
                detail = "训练容量没有下降且每组至少保留 3 RIR；可微加重 \(Int(percent * 1000) / 10)%，但不要减少组数。"
            case (.cuttingVolume, .maintain):
                if let previousVolume, previousVolume > 0 {
                    let ratio = Int((currentVolume / previousVolume * 100).rounded())
                    detail = "本次容量约为上次的 \(ratio)%；继续保留组数和适中重量，以稳定输出为先。"
                } else {
                    detail = "先以本次组数和容量建立基线；减脂期不因单次完成次数达标就自动加重。"
                }
            case (.cuttingVolume, .reduce):
                detail = "建议减重并保留原定组数。"
            case (.balancedProgression, .increase(let percent)):
                detail = "所有完成组达到次数上限且至少保留 2 RIR，可尝试增加约 \(Int(percent * 1000) / 10)% 重量。"
            case (.balancedProgression, .maintain):
                detail = "当前表现适合维持重量，先让各组稳定达到次数上限。"
            case (.balancedProgression, .reduce):
                detail = "建议降低重量并恢复动作质量。"
            }
        }

        return ProgressionAssessment(
            recommendation: recommendation,
            title: title,
            detail: detail,
            currentVolume: currentVolume,
            previousVolume: previousVolume,
            hasCompleteRIR: hasCompleteRIR
        )
    }

    static func workingWeight(weights: [Double], reps: [Int]) -> Double {
        let pairedCount = min(weights.count, reps.count)
        let totalReps = (0..<pairedCount).reduce(0) { $0 + max(0, reps[$1]) }
        guard totalReps > 0 else { return weights.last ?? 0 }
        let volume = (0..<pairedCount).reduce(0.0) {
            $0 + max(0, weights[$1]) * Double(max(0, reps[$1]))
        }
        return (volume / Double(totalReps) * 2).rounded() / 2
    }
}
