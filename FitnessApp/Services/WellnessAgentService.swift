import Foundation

enum WellnessAgentMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

struct WellnessAgentMessage: Encodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: WellnessAgentMessageRole
    let content: String

    init(id: UUID = UUID(), role: WellnessAgentMessageRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
    }
}

struct WellnessAgentContext: Equatable, Sendable {
    let localTimeISO: String
    let waterMilliliters: Int
    let jumpRopeCount: Int?
    let sedentaryMinutes: Int
    let activeSedentaryStartedAt: String?
    let latestWeightKg: Double?

    init(
        localTimeISO: String,
        waterMilliliters: Int,
        jumpRopeCount: Int?,
        sedentaryMinutes: Int,
        activeSedentaryStartedAt: String? = nil,
        latestWeightKg: Double? = nil
    ) {
        self.localTimeISO = localTimeISO
        self.waterMilliliters = waterMilliliters
        self.jumpRopeCount = jumpRopeCount
        self.sedentaryMinutes = sedentaryMinutes
        self.activeSedentaryStartedAt = activeSedentaryStartedAt
        self.latestWeightKg = latestWeightKg
    }
}

struct WellnessAgentRemoteRequest: Encodable, Equatable, Sendable {
    let schemaVersion: Int
    let locale: String
    let messages: [WellnessAgentMessage]
    let context: WellnessAgentContextPayload

    init(messages: [WellnessAgentMessage], context: WellnessAgentContext) {
        schemaVersion = 1
        locale = "zh-Hans"
        self.messages = messages
        self.context = WellnessAgentContextPayload(context)
    }
}

struct WellnessAgentContextPayload: Encodable, Equatable, Sendable {
    let localTimeISO: String
    let today: WellnessAgentTodayPayload

    init(_ context: WellnessAgentContext) {
        localTimeISO = context.localTimeISO
        today = WellnessAgentTodayPayload(
            waterMilliliters: max(0, context.waterMilliliters),
            jumpRopeCount: context.jumpRopeCount.map { max(0, $0) },
            sedentaryMinutes: max(0, context.sedentaryMinutes),
            activeSedentaryStartedAt: context.activeSedentaryStartedAt,
            latestWeightKg: context.latestWeightKg
        )
    }
}

struct WellnessAgentTodayPayload: Encodable, Equatable, Sendable {
    let waterMilliliters: Int
    let jumpRopeCount: Int?
    let sedentaryMinutes: Int
    let activeSedentaryStartedAt: String?
    let latestWeightKg: Double?
}

enum WellnessAgentRemoteTool: String, Codable, Equatable, Sendable {
    case recordWater = "record_water"
    case recordJumpRope = "record_jump_rope"
    case startSedentary = "start_sedentary"
    case stopSedentary = "stop_sedentary"
    case recordSedentary = "record_sedentary"
    case recordWeight = "record_weight"
    case queryTodaySummary = "query_today_summary"
}

struct WellnessAgentRemoteArguments: Codable, Equatable, Sendable {
    var milliliters: Int?
    var count: Int?
    var durationMinutes: Int?
    var kilograms: Double?

    init(
        milliliters: Int? = nil,
        count: Int? = nil,
        durationMinutes: Int? = nil,
        kilograms: Double? = nil
    ) {
        self.milliliters = milliliters
        self.count = count
        self.durationMinutes = durationMinutes
        self.kilograms = kilograms
    }
}

struct WellnessAgentRemoteProposal: Codable, Equatable, Sendable {
    let tool: WellnessAgentRemoteTool
    let arguments: WellnessAgentRemoteArguments
}

struct WellnessAgentRemoteResponse: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let reply: String
    let proposal: WellnessAgentRemoteProposal?
    let needsConfirmation: Bool
    let source: String
}

enum WellnessAgentSource: String, Equatable, Sendable {
    case deepSeek
    case local
    case localFallback

    var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .local: return "本地理解"
        case .localFallback: return "本地接管"
        }
    }
}

struct WellnessAgentTurn: Equatable {
    let reply: String
    let command: WellnessToolCommand?
    let source: WellnessAgentSource
    let diagnostic: String?

    var requiresConfirmation: Bool {
        command?.requiresConfirmation ?? false
    }
}

@MainActor
protocol WellnessAgentRemoteGateway {
    func respond(to request: WellnessAgentRemoteRequest) async throws -> WellnessAgentRemoteResponse
}

enum WellnessAgentRemoteError: LocalizedError, Equatable {
    case insecureEndpoint
    case invalidResponse
    case unsupportedSchema
    case invalidProposal
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .insecureEndpoint: return "Agent 代理必须使用 HTTPS。"
        case .invalidResponse: return "Agent 代理返回的数据不完整。"
        case .unsupportedSchema: return "Agent 代理协议版本不受支持。"
        case .invalidProposal: return "Agent 返回了不安全或不完整的工具提案。"
        case let .requestFailed(statusCode): return "Agent 代理暂时不可用（HTTP \(statusCode)）。"
        }
    }
}

struct RemoteWellnessAgentGateway: WellnessAgentRemoteGateway {
    let endpoint: URL
    let session: URLSession

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    static func makeRequest(endpoint: URL, payload: WellnessAgentRemoteRequest) throws -> URLRequest {
        guard endpoint.scheme?.lowercased() == "https" else {
            throw WellnessAgentRemoteError.insecureEndpoint
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 22
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("x-fit-wellness-agent-v1", forHTTPHeaderField: "X-XFit-Contract")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    func respond(to request: WellnessAgentRemoteRequest) async throws -> WellnessAgentRemoteResponse {
        let urlRequest = try Self.makeRequest(endpoint: endpoint, payload: request)
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw WellnessAgentRemoteError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw WellnessAgentRemoteError.requestFailed(statusCode: http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(WellnessAgentRemoteResponse.self, from: data) else {
            throw WellnessAgentRemoteError.invalidResponse
        }
        return decoded
    }
}

@MainActor
struct HybridWellnessAgent {
    let remote: (any WellnessAgentRemoteGateway)?

    init(remote: (any WellnessAgentRemoteGateway)?) {
        self.remote = remote
    }

    func interpret(
        userMessage: String,
        history: [WellnessAgentMessage],
        context: WellnessAgentContext,
        now: Date = .now
    ) async -> WellnessAgentTurn {
        let message = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return WellnessAgentTurn(
                reply: "告诉我你想记录或查看什么。",
                command: nil,
                source: remote == nil ? .local : .deepSeek,
                diagnostic: nil
            )
        }

        if let remote {
            do {
                let prior = history
                    .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .suffix(7)
                    .map { WellnessAgentMessage(role: $0.role, content: String($0.content.prefix(600))) }
                let messages = prior + [WellnessAgentMessage(role: .user, content: String(message.prefix(600)))]
                let response = try await remote.respond(to: WellnessAgentRemoteRequest(
                    messages: messages,
                    context: context
                ))
                return try turn(from: response, now: now)
            } catch {
                return localTurn(for: message, now: now, source: .localFallback, diagnostic: error.localizedDescription)
            }
        }
        return localTurn(for: message, now: now, source: .local, diagnostic: nil)
    }

    private func turn(from response: WellnessAgentRemoteResponse, now: Date) throws -> WellnessAgentTurn {
        guard response.schemaVersion == 1,
              response.source == "deepseek",
              !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WellnessAgentRemoteError.unsupportedSchema
        }
        guard let proposal = response.proposal else {
            guard !response.needsConfirmation else {
                throw WellnessAgentRemoteError.invalidProposal
            }
            return WellnessAgentTurn(reply: response.reply, command: nil, source: .deepSeek, diagnostic: nil)
        }
        let command = try command(from: proposal, now: now)
        guard response.needsConfirmation == command.requiresConfirmation else {
            throw WellnessAgentRemoteError.invalidProposal
        }
        return WellnessAgentTurn(reply: response.reply, command: command, source: .deepSeek, diagnostic: nil)
    }

    private func command(from proposal: WellnessAgentRemoteProposal, now: Date) throws -> WellnessToolCommand {
        switch proposal.tool {
        case .recordWater:
            guard let value = proposal.arguments.milliliters, (1...5_000).contains(value) else {
                throw WellnessAgentRemoteError.invalidProposal
            }
            return .recordWater(milliliters: value, at: now)
        case .recordJumpRope:
            guard let count = proposal.arguments.count, (1...100_000).contains(count) else {
                throw WellnessAgentRemoteError.invalidProposal
            }
            if let duration = proposal.arguments.durationMinutes, !(1...1_440).contains(duration) {
                throw WellnessAgentRemoteError.invalidProposal
            }
            return .recordJumpRope(count: count, durationMinutes: proposal.arguments.durationMinutes, at: now)
        case .startSedentary:
            return .startSedentary(at: now)
        case .stopSedentary:
            return .stopSedentary(at: now)
        case .recordSedentary:
            guard let duration = proposal.arguments.durationMinutes, (1...1_440).contains(duration) else {
                throw WellnessAgentRemoteError.invalidProposal
            }
            return .recordSedentary(
                startedAt: now.addingTimeInterval(Double(-duration * 60)),
                durationMinutes: duration
            )
        case .recordWeight:
            guard let kilograms = proposal.arguments.kilograms,
                  kilograms.isFinite,
                  kilograms > 0,
                  kilograms <= 500 else {
                throw WellnessAgentRemoteError.invalidProposal
            }
            return .recordWeight(kilograms: kilograms, at: now)
        case .queryTodaySummary:
            return .queryTodaySummary(on: now)
        }
    }

    private func localTurn(
        for message: String,
        now: Date,
        source: WellnessAgentSource,
        diagnostic: String?
    ) -> WellnessAgentTurn {
        switch LocalWellnessAgent.interpret(message, now: now) {
        case let .pending(command):
            let reply = command.requiresConfirmation
                ? "我在本机理解为“\(command.previewTitle)”，请确认。"
                : "我在本机找到了今天的记录。"
            return WellnessAgentTurn(reply: reply, command: command, source: source, diagnostic: diagnostic)
        case let .unsupported(message):
            return WellnessAgentTurn(reply: message, command: nil, source: source, diagnostic: diagnostic)
        }
    }
}

enum WellnessAgentConfiguration {
    static var endpointURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WELLNESS_AGENT_ENDPOINT") as? String,
              !raw.isEmpty,
              !raw.contains("$("),
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }
}
