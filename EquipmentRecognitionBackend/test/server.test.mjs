import assert from "node:assert/strict";
import test from "node:test";
import { buildApp } from "../src/server.mjs";

function multipartBody({ ocrText = "HAMMER STRENGTH PENDULUM", includeImage = true } = {}) {
  const boundary = "xfit-test-boundary";
  const chunks = [
    `--${boundary}\r\nContent-Disposition: form-data; name="locale"\r\n\r\nzh-Hans\r\n`,
    `--${boundary}\r\nContent-Disposition: form-data; name="catalogVersion"\r\n\r\n2026.08.22\r\n`,
    `--${boundary}\r\nContent-Disposition: form-data; name="ocrText"\r\n\r\n${ocrText}\r\n`
  ];
  if (includeImage) {
    chunks.push(`--${boundary}\r\nContent-Disposition: form-data; name="images"; filename="machine.jpg"\r\nContent-Type: image/jpeg\r\n\r\nfake-jpeg\r\n`);
  }
  chunks.push(`--${boundary}--\r\n`);
  return { boundary, body: chunks.join("") };
}

test("health exposes the active catalog version", async () => {
  const app = await buildApp();
  const response = await app.inject({ method: "GET", url: "/health" });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), { ok: true, catalogVersion: "2026.08.22" });
  await app.close();
});

test("local OCR catalog match returns a confirmation-only candidate", async () => {
  const app = await buildApp();
  const { boundary, body } = multipartBody();
  const response = await app.inject({
    method: "POST",
    url: "/v1/equipment/recognitions",
    headers: { "content-type": `multipart/form-data; boundary=${boundary}` },
    payload: body
  });
  assert.equal(response.statusCode, 200);
  const result = response.json();
  assert.equal(result.machine.canonicalID, "pendulum_squat_machine");
  assert.equal(result.needsConfirmation, true);
  assert.ok(result.exerciseCandidates.length > 0);
  await app.close();
});

test("image is required and unknown OCR does not invent a result", async () => {
  const app = await buildApp();
  const missing = multipartBody({ includeImage: false });
  const missingResponse = await app.inject({
    method: "POST",
    url: "/v1/equipment/recognitions",
    headers: { "content-type": `multipart/form-data; boundary=${missing.boundary}` },
    payload: missing.body
  });
  assert.equal(missingResponse.statusCode, 400);

  const unknown = multipartBody({ ocrText: "UNKNOWN MACHINE" });
  const unknownResponse = await app.inject({
    method: "POST",
    url: "/v1/equipment/recognitions",
    headers: { "content-type": `multipart/form-data; boundary=${unknown.boundary}` },
    payload: unknown.body
  });
  assert.equal(unknownResponse.statusCode, 503);
  await app.close();
});

test("wellness agent returns a confirmation-only whitelisted tool proposal", async () => {
  const observed = [];
  const app = await buildApp({
    wellnessAgentCompletion: async (request) => {
      observed.push(request);
      return {
        reply: "我理解为记录 300 ml 饮水，请确认。",
        proposal: { tool: "record_water", arguments: { milliliters: 300 } }
      };
    }
  });

  const response = await app.inject({
    method: "POST",
    url: "/v1/wellness/agent",
    payload: {
      schemaVersion: 1,
      locale: "zh-Hans",
      messages: [{ role: "user", content: "刚喝了一大杯，大概 300 毫升" }],
      context: {
        localTimeISO: "2026-09-02T14:00:00+08:00",
        today: { waterMilliliters: 250, jumpRopeCount: 0, sedentaryMinutes: 30 }
      }
    }
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    schemaVersion: 1,
    reply: "我理解为记录 300 ml 饮水，请确认。",
    proposal: { tool: "record_water", arguments: { milliliters: 300 } },
    needsConfirmation: true,
    source: "deepseek"
  });
  assert.equal(observed.length, 1);
  assert.equal(observed[0].messages.length, 1);
  assert.equal("apiKey" in observed[0], false);
  await app.close();
});

test("wellness agent keeps the DeepSeek key server-side", async () => {
  const upstream = [];
  const app = await buildApp({
    wellnessAgentEnvironment: {
      DEEPSEEK_API_URL: "https://api.deepseek.com/chat/completions",
      DEEPSEEK_API_KEY: "server-only-secret",
      DEEPSEEK_MODEL: "deepseek-chat"
    },
    fetchImpl: async (url, options) => {
      upstream.push({ url, options });
      return new Response(JSON.stringify({
        choices: [{ message: { content: JSON.stringify({
          reply: "今天已记录的数据如下。",
          proposal: { tool: "query_today_summary", arguments: {} }
        }) } }]
      }), { status: 200, headers: { "content-type": "application/json" } });
    }
  });

  const response = await app.inject({
    method: "POST",
    url: "/v1/wellness/agent",
    payload: {
      schemaVersion: 1,
      messages: [{ role: "user", content: "我今天记录了什么？" }],
      context: {
        localTimeISO: "2026-09-02T14:00:00+08:00",
        today: { waterMilliliters: 500, jumpRopeCount: 1200, sedentaryMinutes: 45 }
      }
    }
  });

  assert.equal(response.statusCode, 200);
  assert.equal(upstream.length, 1);
  assert.equal(upstream[0].url, "https://api.deepseek.com/chat/completions");
  assert.equal(upstream[0].options.headers.Authorization, "Bearer server-only-secret");
  assert.equal(JSON.stringify(response.json()).includes("server-only-secret"), false);
  assert.equal(response.json().needsConfirmation, false);
  await app.close();
});

test("wellness agent rejects unsafe arguments before they reach the phone", async () => {
  const app = await buildApp({
    wellnessAgentCompletion: async () => ({
      reply: "已准备跳绳记录。",
      proposal: { tool: "record_jump_rope", arguments: { count: 0, durationMinutes: -3 } }
    })
  });
  const response = await app.inject({
    method: "POST",
    url: "/v1/wellness/agent",
    payload: {
      schemaVersion: 1,
      messages: [{ role: "user", content: "跳绳" }],
      context: {
        localTimeISO: "2026-09-02T14:00:00+08:00",
        today: { waterMilliliters: 0, jumpRopeCount: 0, sedentaryMinutes: 0 }
      }
    }
  });
  assert.equal(response.statusCode, 502);
  assert.deepEqual(response.json(), { error: "agent_response_invalid" });
  await app.close();
});
