import Foundation
import XCTest
@testable import FitnessApp

@MainActor
final class WellnessAgentTests: XCTestCase {
    func testRemoteRequestContainsNoProviderCredentialAndOnlyMinimalContext() throws {
        let messages = (0..<10).map { index in
            WellnessAgentMessage(role: index.isMultiple(of: 2) ? .user : .assistant, content: "message-\(index)")
        }
        let payload = WellnessAgentRemoteRequest(
            messages: Array(messages.suffix(8)),
            context: WellnessAgentContext(
                localTimeISO: "2026-09-02T14:00:00+08:00",
                waterMilliliters: 500,
                jumpRopeCount: 1_200,
                sedentaryMinutes: 45,
                activeSedentaryStartedAt: nil,
                latestWeightKg: 82.4
            )
        )

        let request = try RemoteWellnessAgentGateway.makeRequest(
            endpoint: URL(string: "https://api.x-fit.example/v1/wellness/agent")!,
            payload: payload
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let context = try XCTUnwrap(json["context"] as? [String: Any])
        let today = try XCTUnwrap(context["today"] as? [String: Any])

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(json["apiKey"])
        XCTAssertNil(json["trainingHistory"])
        XCTAssertEqual((json["messages"] as? [[String: Any]])?.count, 8)
        XCTAssertEqual(Set(today.keys), [
            "waterMilliliters", "jumpRopeCount", "sedentaryMinutes", "latestWeightKg"
        ])
    }

    func testRemoteRequestRejectsPlainHTTP() {
        let payload = WellnessAgentRemoteRequest(
            messages: [WellnessAgentMessage(role: .user, content: "喝水 250 ml")],
            context: WellnessAgentContext(
                localTimeISO: "2026-09-02T14:00:00+08:00",
                waterMilliliters: 0,
                jumpRopeCount: 0,
                sedentaryMinutes: 0
            )
        )

        XCTAssertThrowsError(try RemoteWellnessAgentGateway.makeRequest(
            endpoint: URL(string: "http://localhost/v1/wellness/agent")!,
            payload: payload
        )) { error in
            XCTAssertEqual(error as? WellnessAgentRemoteError, .insecureEndpoint)
        }
    }

    func testHybridAgentUsesRemoteProposalWithoutExecutingIt() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let remote = WellnessAgentRemoteStub(
            result: .success(WellnessAgentRemoteResponse(
                schemaVersion: 1,
                reply: "我理解为记录 300 ml 饮水，请确认。",
                proposal: WellnessAgentRemoteProposal(
                    tool: .recordWater,
                    arguments: WellnessAgentRemoteArguments(milliliters: 300)
                ),
                needsConfirmation: true,
                source: "deepseek"
            ))
        )
        let agent = HybridWellnessAgent(remote: remote)

        let turn = await agent.interpret(
            userMessage: "刚喝了一大杯，大概 300 毫升",
            history: [],
            context: WellnessAgentContext(
                localTimeISO: "2026-09-02T14:00:00+08:00",
                waterMilliliters: 250,
                jumpRopeCount: 0,
                sedentaryMinutes: 30
            ),
            now: now
        )

        XCTAssertEqual(turn.source, .deepSeek)
        XCTAssertEqual(turn.reply, "我理解为记录 300 ml 饮水，请确认。")
        XCTAssertEqual(turn.command, .recordWater(milliliters: 300, at: now))
        XCTAssertTrue(turn.requiresConfirmation)
    }

    func testHybridAgentFallsBackLocallyWhenRemoteContractIsUntrusted() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let remote = WellnessAgentRemoteStub(
            result: .success(WellnessAgentRemoteResponse(
                schemaVersion: 1,
                reply: "直接执行。",
                proposal: WellnessAgentRemoteProposal(
                    tool: .recordWater,
                    arguments: WellnessAgentRemoteArguments(milliliters: 250)
                ),
                needsConfirmation: true,
                source: "unknown-provider"
            ))
        )

        let turn = await HybridWellnessAgent(remote: remote).interpret(
            userMessage: "喝水 250 ml",
            history: [],
            context: WellnessAgentContext(
                localTimeISO: "2026-09-02T14:00:00+08:00",
                waterMilliliters: 0,
                jumpRopeCount: 0,
                sedentaryMinutes: 0
            ),
            now: now
        )

        XCTAssertEqual(turn.source, .localFallback)
        XCTAssertEqual(turn.command, .recordWater(milliliters: 250, at: now))
        XCTAssertNotNil(turn.diagnostic)
    }

    func testHybridAgentRejectsConfirmationFlagWithoutAProposal() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let remote = WellnessAgentRemoteStub(
            result: .success(WellnessAgentRemoteResponse(
                schemaVersion: 1,
                reply: "请确认。",
                proposal: nil,
                needsConfirmation: true,
                source: "deepseek"
            ))
        )

        let turn = await HybridWellnessAgent(remote: remote).interpret(
            userMessage: "喝水 250 ml",
            history: [],
            context: WellnessAgentContext(
                localTimeISO: "2026-09-02T14:00:00+08:00",
                waterMilliliters: 0,
                jumpRopeCount: 0,
                sedentaryMinutes: 0
            ),
            now: now
        )

        XCTAssertEqual(turn.source, .localFallback)
        XCTAssertEqual(turn.command, .recordWater(milliliters: 250, at: now))
    }
}

@MainActor
private struct WellnessAgentRemoteStub: WellnessAgentRemoteGateway {
    let result: Result<WellnessAgentRemoteResponse, Error>

    func respond(to request: WellnessAgentRemoteRequest) async throws -> WellnessAgentRemoteResponse {
        try result.get()
    }
}
