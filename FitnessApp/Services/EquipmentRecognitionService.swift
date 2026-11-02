import Foundation
import UIKit
@preconcurrency import Vision

struct EquipmentDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let nameZH: String
    let nameEN: String
    let aliases: [String]
    let exerciseNamesZH: [String]
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
}

enum EquipmentCatalogService {
    static let version = "2026.08.22"

    static let commonChoices = [
        "自重", "哑铃", "杠铃", "壶铃", "史密斯机", "龙门架", "固定器械", "弹力带"
    ]

    static let definitions: [EquipmentDefinition] = [
        .init(id: "smith_machine", nameZH: "史密斯机", nameEN: "Smith Machine", aliases: ["史密斯", "smith", "smith rack"], exerciseNamesZH: ["史密斯机平板卧推", "史密斯机上斜卧推", "史密斯机肩上推举", "杠铃深蹲"], primaryMuscles: ["胸部", "肩部", "腿部"], secondaryMuscles: ["手臂", "臀部", "核心"]),
        .init(id: "cable_machine", nameZH: "龙门架", nameEN: "Cable Machine", aliases: ["绳索", "拉力器", "cable", "functional trainer"], exerciseNamesZH: ["站姿绳索夹胸", "绳索下压", "绳索侧平举", "绳索面拉", "绳索卷腹"], primaryMuscles: ["胸部", "背部", "肩部", "手臂"], secondaryMuscles: ["核心"]),
        .init(id: "lat_pulldown_machine", nameZH: "高位下拉机", nameEN: "Lat Pulldown Machine", aliases: ["高位下拉", "下拉器", "lat pulldown"], exerciseNamesZH: ["高位下拉", "窄握高位下拉", "颈后高位下拉"], primaryMuscles: ["背部"], secondaryMuscles: ["手臂", "肩部"]),
        .init(id: "seated_row_machine", nameZH: "坐姿划船机", nameEN: "Seated Row Machine", aliases: ["划船机", "坐姿划船", "seated row", "row machine"], exerciseNamesZH: ["坐姿器械划船"], primaryMuscles: ["背部"], secondaryMuscles: ["手臂", "肩部"]),
        .init(id: "chest_press_machine", nameZH: "坐姿推胸机", nameEN: "Chest Press Machine", aliases: ["推胸机", "chest press", "incline press", "decline press"], exerciseNamesZH: ["坐姿推胸机", "坐姿上斜推胸机", "坐姿下斜推胸机"], primaryMuscles: ["胸部"], secondaryMuscles: ["肩部", "手臂"]),
        .init(id: "shoulder_press_machine", nameZH: "器械肩推机", nameEN: "Shoulder Press Machine", aliases: ["肩推机", "shoulder press", "overhead press machine"], exerciseNamesZH: ["器械肩上推举"], primaryMuscles: ["肩部"], secondaryMuscles: ["手臂", "胸部"]),
        .init(id: "leg_press_machine", nameZH: "腿举机", nameEN: "Leg Press Machine", aliases: ["腿推", "leg press", "plate loaded leg press"], exerciseNamesZH: ["器械腿举", "单腿器械腿举"], primaryMuscles: ["腿部", "臀部"], secondaryMuscles: ["小腿"]),
        .init(id: "hack_squat_machine", nameZH: "哈克深蹲机", nameEN: "Hack Squat Machine", aliases: ["哈克", "hack squat"], exerciseNamesZH: ["哈克深蹲"], primaryMuscles: ["腿部", "臀部"], secondaryMuscles: ["小腿", "核心"]),
        .init(id: "pendulum_squat_machine", nameZH: "钟摆深蹲机", nameEN: "Pendulum Squat Machine", aliases: ["钟摆", "pendulum squat", "pendulum press"], exerciseNamesZH: ["钟摆深蹲机", "单腿钟摆式腿推/深蹲"], primaryMuscles: ["腿部", "臀部"], secondaryMuscles: ["小腿", "核心"]),
        .init(id: "leg_extension_machine", nameZH: "腿屈伸机", nameEN: "Leg Extension Machine", aliases: ["腿伸展", "leg extension"], exerciseNamesZH: ["器械腿屈伸"], primaryMuscles: ["腿部"], secondaryMuscles: []),
        .init(id: "leg_curl_machine", nameZH: "腿弯举机", nameEN: "Leg Curl Machine", aliases: ["腿弯举", "leg curl", "hamstring curl"], exerciseNamesZH: ["器械腿弯举"], primaryMuscles: ["腿部"], secondaryMuscles: ["小腿"]),
        .init(id: "pec_deck_machine", nameZH: "蝴蝶机", nameEN: "Pec Deck Machine", aliases: ["飞鸟机", "夹胸机", "pec deck", "chest fly", "rear delt fly"], exerciseNamesZH: ["坐姿器械夹胸（蝴蝶机飞鸟）", "器械反向飞鸟"], primaryMuscles: ["胸部", "肩部"], secondaryMuscles: ["手臂"]),
        .init(id: "hip_thrust_machine", nameZH: "臀推机", nameEN: "Hip Thrust Machine", aliases: ["臀桥机", "hip thrust", "glute drive"], exerciseNamesZH: ["器械臀推"], primaryMuscles: ["臀部"], secondaryMuscles: ["腿部", "核心"]),
        .init(id: "standing_calf_raise_machine", nameZH: "站姿提踵机", nameEN: "Standing Calf Raise Machine", aliases: ["提踵机", "calf raise"], exerciseNamesZH: ["器械站姿提踵"], primaryMuscles: ["小腿"], secondaryMuscles: []),
        .init(id: "power_rack", nameZH: "力量架", nameEN: "Power Rack", aliases: ["深蹲架", "squat rack", "power rack"], exerciseNamesZH: ["杠铃深蹲", "杠铃平板卧推", "杠铃肩上推举"], primaryMuscles: ["腿部", "胸部", "肩部"], secondaryMuscles: ["臀部", "手臂", "核心"]),
        .init(id: "dumbbell", nameZH: "哑铃", nameEN: "Dumbbell", aliases: ["dumbbell", "db"], exerciseNamesZH: ["哑铃二头肌弯举", "哑铃侧平举", "坐姿哑铃肩上推举"], primaryMuscles: ["肩部", "手臂"], secondaryMuscles: ["胸部", "背部"]),
        .init(id: "barbell", nameZH: "杠铃", nameEN: "Barbell", aliases: ["barbell", "bb"], exerciseNamesZH: ["杠铃平板卧推", "杠铃深蹲", "杠铃罗马尼亚硬拉", "杠铃俯身划船"], primaryMuscles: ["胸部", "背部", "腿部"], secondaryMuscles: ["肩部", "手臂", "臀部", "核心"]),
        .init(id: "kettlebell", nameZH: "壶铃", nameEN: "Kettlebell", aliases: ["kettlebell", "kb"], exerciseNamesZH: ["壶铃摆动", "壶铃高脚杯深蹲", "壶铃推举"], primaryMuscles: ["臀部", "腿部", "肩部"], secondaryMuscles: ["核心", "背部", "手臂"])
    ]

    static func definition(for text: String) -> EquipmentDefinition? {
        let target = normalized(text)
        guard !target.isEmpty else { return nil }
        return definitions.first { item in
            ([item.id, item.nameZH, item.nameEN] + item.aliases).contains { candidate in
                let normalizedCandidate = normalized(candidate)
                return target == normalizedCandidate
            }
        }
    }

    static func searchTerms(for equipment: String) -> [String] {
        guard let item = definition(for: equipment) else { return [] }
        return [item.nameZH, item.nameEN, item.id] + item.aliases
    }

    /// OCR can contain a complete machine label inside a longer string. Unlike
    /// display-name resolution, this returns every candidate for review.
    static func recognitionCandidates(in text: String) -> [EquipmentDefinition] {
        let evidence = normalized(text)
        guard !evidence.isEmpty else { return [] }
        return definitions.filter { item in
            ([item.nameZH, item.nameEN] + item.aliases).contains { value in
                let term = normalized(value)
                guard term.count >= 3 else { return false }
                if term.unicodeScalars.allSatisfy(\.isASCII) {
                    let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: term) + "(?![a-z0-9])"
                    return evidence.range(of: pattern, options: .regularExpression) != nil
                }
                return evidence.contains(term)
            }
        }
    }

    static func englishName(for equipment: String) -> String? {
        definition(for: equipment)?.nameEN
    }

    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_Hans_CN"))
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}

struct RecognizedMachine: Codable, Equatable, Sendable {
    let canonicalID: String?
    let nameZH: String
    let nameEN: String
    let confidence: Double
    let evidence: [String]
}

struct RecognizedExerciseCandidate: Identifiable, Codable, Equatable, Sendable {
    var id: String { canonicalID ?? nameEN }
    let canonicalID: String?
    let nameZH: String
    let nameEN: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let confidence: Double
}

struct EquipmentRecognitionResponse: Codable, Equatable, Sendable {
    let analysisID: String
    let machine: RecognizedMachine
    let exerciseCandidates: [RecognizedExerciseCandidate]
    let needsConfirmation: Bool
    let warnings: [String]
}

enum EquipmentRecognitionError: LocalizedError, Equatable {
    case noImage
    case invalidImage
    case serviceNotConfigured
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .noImage: return "请至少拍摄或选择一张器械照片。"
        case .invalidImage: return "照片无法处理，请重新拍摄。"
        case .serviceNotConfigured: return "没有识别到本地器械，且云端识别服务尚未配置。"
        case .invalidResponse: return "识别服务返回的数据不完整，请重试。"
        case let .requestFailed(message): return "器械识别失败：\(message)"
        }
    }
}

protocol EquipmentRecognizing: Sendable {
    func recognize(images: [UIImage]) async throws -> EquipmentRecognitionResponse
}

struct EquipmentRecognitionService: EquipmentRecognizing {
    private let session: URLSession
    private let endpoint: URL?

    init(session: URLSession = .shared, endpoint: URL? = EquipmentRecognitionConfiguration.endpointURL) {
        self.session = session
        self.endpoint = endpoint
    }

    func recognize(images: [UIImage]) async throws -> EquipmentRecognitionResponse {
        guard !images.isEmpty else { throw EquipmentRecognitionError.noImage }

        if CommandLine.arguments.contains("--ui-testing-equipment-recognition") {
            return Self.mockResponse
        }

        let localEvidence = await Self.recognizedText(in: images)
        if let endpoint {
            return try await recognizeRemotely(images: images, ocrText: localEvidence, endpoint: endpoint)
        }
        let candidates = EquipmentCatalogService.recognitionCandidates(in: localEvidence.joined(separator: " "))
        if candidates.count == 1, let definition = candidates.first {
            return Self.response(for: definition, evidence: localEvidence, confidence: 0.72)
        }
        throw EquipmentRecognitionError.serviceNotConfigured
    }

    private func recognizeRemotely(
        images: [UIImage],
        ocrText: [String],
        endpoint: URL
    ) async throws -> EquipmentRecognitionResponse {
        let boundary = "xfit-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body = Data()
        body.appendMultipart(name: "locale", value: "zh-Hans", boundary: boundary)
        body.appendMultipart(name: "catalogVersion", value: EquipmentCatalogService.version, boundary: boundary)
        body.appendMultipart(name: "ocrText", value: ocrText.joined(separator: "\n"), boundary: boundary)
        for (index, image) in images.prefix(3).enumerated() {
            guard let data = image.xfitRecognitionJPEGData else { throw EquipmentRecognitionError.invalidImage }
            body.appendMultipart(name: "images", filename: "equipment-\(index + 1).jpg", mimeType: "image/jpeg", data: data, boundary: boundary)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw EquipmentRecognitionError.requestFailed("服务暂时不可用")
            }
            let decoded = try JSONDecoder().decode(EquipmentRecognitionResponse.self, from: data)
            guard !decoded.machine.nameZH.isEmpty, !decoded.machine.nameEN.isEmpty else {
                throw EquipmentRecognitionError.invalidResponse
            }
            return decoded
        } catch let error as EquipmentRecognitionError {
            throw error
        } catch {
            throw EquipmentRecognitionError.requestFailed(error.localizedDescription)
        }
    }

    private static func recognizedText(in images: [UIImage]) async -> [String] {
        await withTaskGroup(of: [String].self) { group in
            for image in images.prefix(3) {
                group.addTask {
                    guard let cgImage = image.cgImage else { return [] }
                    return await withCheckedContinuation { continuation in
                        let request = VNRecognizeTextRequest { request, _ in
                            let values = (request.results as? [VNRecognizedTextObservation])?
                                .compactMap { $0.topCandidates(1).first?.string } ?? []
                            continuation.resume(returning: values)
                        }
                        request.recognitionLevel = .accurate
                        request.recognitionLanguages = ["zh-Hans", "en-US"]
                        request.usesLanguageCorrection = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                            } catch {
                                continuation.resume(returning: [])
                            }
                        }
                    }
                }
            }
            var result: [String] = []
            for await text in group { result.append(contentsOf: text) }
            return result
        }
    }

    static func response(
        for definition: EquipmentDefinition,
        evidence: [String],
        confidence: Double
    ) -> EquipmentRecognitionResponse {
        let exerciseCandidates = definition.exerciseNamesZH.compactMap { name in
            let terminology = ExerciseTerminologyService.candidate(for: name)
            return RecognizedExerciseCandidate(
                canonicalID: terminology?.canonicalID,
                nameZH: terminology?.standardNameZH ?? name,
                nameEN: terminology?.standardNameEN ?? name,
                primaryMuscles: definition.primaryMuscles,
                secondaryMuscles: definition.secondaryMuscles,
                confidence: confidence
            )
        }
        return EquipmentRecognitionResponse(
            analysisID: UUID().uuidString,
            machine: RecognizedMachine(
                canonicalID: definition.id,
                nameZH: definition.nameZH,
                nameEN: definition.nameEN,
                confidence: confidence,
                evidence: Array(evidence.prefix(4))
            ),
            exerciseCandidates: exerciseCandidates,
            needsConfirmation: true,
            warnings: confidence < 0.8 ? ["照片或标牌信息有限，请在加入训练前确认器械和动作。"] : []
        )
    }

    static let mockResponse = response(
        for: EquipmentCatalogService.definitions.first { $0.id == "pendulum_squat_machine" }!,
        evidence: ["HAMMER STRENGTH", "腿部训练轨迹"],
        confidence: 0.84
    )
}

enum EquipmentRecognitionConfiguration {
    static var endpointURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "EQUIPMENT_RECOGNITION_ENDPOINT") as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: raw)
    }
}

private extension UIImage {
    var xfitRecognitionJPEGData: Data? {
        let maxEdge: CGFloat = 1_600
        let scale = min(1, maxEdge / max(size.width, size.height))
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let flattened = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        var quality: CGFloat = 0.82
        var data = flattened.jpegData(compressionQuality: quality)
        while let current = data, current.count > 3_000_000, quality > 0.42 {
            quality -= 0.1
            data = flattened.jpegData(compressionQuality: quality)
        }
        return data
    }
}

private extension Data {
    mutating func appendMultipart(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
