import Foundation

enum ProgressionRecommendation: Equatable {
    case increase(percent: Double)
    case maintain
    case reduce

    var title: String {
        switch self {
        case .increase:
            return "建议小幅加重"
        case .maintain:
            return "建议保持重量"
        case .reduce:
            return "建议降低重量"
        }
    }
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
        let effortControlled = rirValues.isEmpty || rirValues.allSatisfy { $0 >= 2 }
        return allAtTop && effortControlled ? .increase(percent: 0.025) : .maintain
    }
}

