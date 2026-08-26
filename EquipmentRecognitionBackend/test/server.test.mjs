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
