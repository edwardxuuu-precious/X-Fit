import Fastify from "fastify";
import multipart from "@fastify/multipart";
import { pathToFileURL } from "node:url";
import { catalogVersion, localCatalogMatch, responseForCatalogItem } from "./catalog.mjs";

const maxImageBytes = 3_000_000;

export async function buildApp(options = {}) {
  const app = Fastify({ logger: options.logger ?? false });
  await app.register(multipart, {
    limits: { files: 3, fileSize: maxImageBytes, fields: 6, parts: 9 }
  });

  app.get("/health", async () => ({ ok: true, catalogVersion }));

  app.post("/v1/equipment/recognitions", async (request, reply) => {
    const fields = {};
    const images = [];

    try {
      for await (const part of request.parts()) {
        if (part.type === "file") {
          if (part.fieldname !== "images" || !["image/jpeg", "image/png"].includes(part.mimetype)) {
            await part.toBuffer();
            return reply.code(415).send({ error: "unsupported_image" });
          }
          const data = await part.toBuffer();
          if (data.length === 0 || data.length > maxImageBytes) {
            return reply.code(413).send({ error: "image_too_large" });
          }
          images.push({ mimeType: part.mimetype, data });
        } else {
          fields[part.fieldname] = String(part.value ?? "");
        }
      }
    } catch (error) {
      request.log.warn({ error }, "multipart parse failed");
      return reply.code(400).send({ error: "invalid_multipart" });
    }

    if (images.length === 0) return reply.code(400).send({ error: "image_required" });
    if (fields.catalogVersion && fields.catalogVersion !== catalogVersion) {
      reply.header("X-XFit-Catalog-Version", catalogVersion);
    }

    const evidence = String(fields.ocrText ?? "")
      .split(/\r?\n/)
      .map((value) => value.trim())
      .filter(Boolean);
    const localMatch = localCatalogMatch(evidence.join(" "));

    if (!process.env.VISION_MODEL_API_URL || !process.env.VISION_MODEL_API_KEY) {
      if (!localMatch) return reply.code(503).send({ error: "model_not_configured" });
      return responseForCatalogItem(localMatch, evidence, 0.72);
    }

    try {
      const result = await recognizeWithModel({ images, evidence, localMatch });
      return validateResponse(result);
    } catch (error) {
      request.log.error({ error }, "model recognition failed");
      if (localMatch) return responseForCatalogItem(localMatch, evidence, 0.62);
      return reply.code(502).send({ error: "model_response_invalid" });
    }
  });

  return app;
}

async function recognizeWithModel({ images, evidence, localMatch }) {
  const imageParts = images.map((image) => ({
    type: "image_url",
    image_url: { url: `data:${image.mimeType};base64,${image.data.toString("base64")}` }
  }));
  const prompt = [
    "Identify the gym equipment in the photos and list safe, plausible exercises and muscle groups.",
    "Return JSON only and use the exact response shape described below.",
    "Never invent certainty: confidence must be 0...1 and needsConfirmation must be true.",
    `OCR evidence: ${evidence.join(" | ") || "none"}`,
    `Local catalog hint: ${localMatch ? `${localMatch.nameZH} / ${localMatch.nameEN}` : "none"}`,
    'Shape: {"analysisID":"uuid","machine":{"canonicalID":string|null,"nameZH":string,"nameEN":string,"confidence":number,"evidence":string[]},"exerciseCandidates":[{"canonicalID":string|null,"nameZH":string,"nameEN":string,"primaryMuscles":string[],"secondaryMuscles":string[],"confidence":number}],"needsConfirmation":true,"warnings":string[]}'
  ].join("\n");

  const response = await fetch(process.env.VISION_MODEL_API_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${process.env.VISION_MODEL_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: process.env.VISION_MODEL_NAME || "vision-model",
      temperature: 0,
      response_format: { type: "json_object" },
      messages: [{ role: "user", content: [{ type: "text", text: prompt }, ...imageParts] }]
    }),
    signal: AbortSignal.timeout(40_000)
  });
  if (!response.ok) throw new Error(`model_http_${response.status}`);
  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content;
  return typeof content === "string" ? JSON.parse(content) : content;
}

function validateResponse(value) {
  if (!value || typeof value !== "object") throw new Error("missing_response");
  const machine = value.machine;
  if (!machine || typeof machine.nameZH !== "string" || typeof machine.nameEN !== "string") {
    throw new Error("missing_machine_names");
  }
  if (!Number.isFinite(machine.confidence) || machine.confidence < 0 || machine.confidence > 1) {
    throw new Error("invalid_machine_confidence");
  }
  if (!Array.isArray(value.exerciseCandidates) || value.exerciseCandidates.length === 0) {
    throw new Error("missing_exercises");
  }
  const candidates = value.exerciseCandidates.slice(0, 8).map((item) => {
    if (!item || typeof item.nameZH !== "string" || typeof item.nameEN !== "string") {
      throw new Error("invalid_exercise_name");
    }
    const confidence = Number(item.confidence);
    if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
      throw new Error("invalid_exercise_confidence");
    }
    return {
      canonicalID: typeof item.canonicalID === "string" ? item.canonicalID : null,
      nameZH: item.nameZH.trim(),
      nameEN: item.nameEN.trim(),
      primaryMuscles: strings(item.primaryMuscles),
      secondaryMuscles: strings(item.secondaryMuscles),
      confidence
    };
  });
  return {
    analysisID: typeof value.analysisID === "string" ? value.analysisID : crypto.randomUUID(),
    machine: {
      canonicalID: typeof machine.canonicalID === "string" ? machine.canonicalID : null,
      nameZH: machine.nameZH.trim(),
      nameEN: machine.nameEN.trim(),
      confidence: Number(machine.confidence),
      evidence: strings(machine.evidence).slice(0, 4)
    },
    exerciseCandidates: candidates,
    needsConfirmation: true,
    warnings: strings(value.warnings).slice(0, 4)
  };
}

function strings(value) {
  return Array.isArray(value)
    ? value.filter((item) => typeof item === "string").map((item) => item.trim()).filter(Boolean)
    : [];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const app = await buildApp({ logger: true });
  await app.listen({ port: Number(process.env.PORT || 8787), host: process.env.HOST || "127.0.0.1" });
}
