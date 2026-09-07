import Fastify from "fastify";
import multipart from "@fastify/multipart";
import { pathToFileURL } from "node:url";
import { catalogVersion, localCatalogMatch, responseForCatalogItem } from "./catalog.mjs";

const maxImageBytes = 3_000_000;
const wellnessAgentSchemaVersion = 1;
const wellnessAgentTools = new Set([
  "record_water",
  "record_jump_rope",
  "start_sedentary",
  "stop_sedentary",
  "record_sedentary",
  "record_weight",
  "query_today_summary"
]);

export async function buildApp(options = {}) {
  const app = Fastify({ logger: options.logger ?? false });
  const wellnessAgentEnvironment = options.wellnessAgentEnvironment ?? process.env;
  const fetchImpl = options.fetchImpl ?? fetch;
  const wellnessAgentCompletion = options.wellnessAgentCompletion
    ?? (wellnessAgentEnvironment.DEEPSEEK_API_URL && wellnessAgentEnvironment.DEEPSEEK_API_KEY
      ? (input) => completeWellnessAgentWithDeepSeek(input, wellnessAgentEnvironment, fetchImpl)
      : null);
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

  app.post("/v1/wellness/agent", async (request, reply) => {
    let input;
    try {
      input = validateWellnessAgentRequest(request.body);
    } catch {
      return reply.code(400).send({ error: "invalid_agent_request" });
    }

    if (!wellnessAgentCompletion) {
      return reply.code(503).send({ error: "agent_not_configured" });
    }

    try {
      const result = validateWellnessAgentResponse(await wellnessAgentCompletion(input));
      return {
        schemaVersion: wellnessAgentSchemaVersion,
        ...result,
        needsConfirmation: result.proposal?.tool !== "query_today_summary" && result.proposal != null,
        source: "deepseek"
      };
    } catch (error) {
      request.log.error({ error }, "wellness agent failed");
      return reply.code(502).send({ error: "agent_response_invalid" });
    }
  });

  return app;
}

function validateWellnessAgentRequest(value) {
  if (!value || value.schemaVersion !== wellnessAgentSchemaVersion) throw new Error("invalid_schema");
  if (!Array.isArray(value.messages) || value.messages.length === 0 || value.messages.length > 8) {
    throw new Error("invalid_messages");
  }
  const messages = value.messages.map((message) => {
    if (!message || !["user", "assistant"].includes(message.role)) throw new Error("invalid_role");
    const content = String(message.content ?? "").trim();
    if (!content || content.length > 600) throw new Error("invalid_content");
    return { role: message.role, content };
  });
  if (messages.at(-1)?.role !== "user") throw new Error("last_message_must_be_user");

  const today = value.context?.today;
  if (!today || !Number.isInteger(today.waterMilliliters) || !Number.isInteger(today.jumpRopeCount)
      || !Number.isInteger(today.sedentaryMinutes)) {
    throw new Error("invalid_context");
  }
  return {
    schemaVersion: wellnessAgentSchemaVersion,
    locale: typeof value.locale === "string" ? value.locale.slice(0, 20) : "zh-Hans",
    messages,
    context: {
      localTimeISO: String(value.context.localTimeISO ?? "").slice(0, 40),
      today: {
        waterMilliliters: Math.max(0, today.waterMilliliters),
        jumpRopeCount: Math.max(0, today.jumpRopeCount),
        sedentaryMinutes: Math.max(0, today.sedentaryMinutes),
        activeSedentaryStartedAt: typeof today.activeSedentaryStartedAt === "string"
          ? today.activeSedentaryStartedAt.slice(0, 40)
          : null,
        latestWeightKg: Number.isFinite(today.latestWeightKg) ? Number(today.latestWeightKg) : null
      }
    }
  };
}

function validateWellnessAgentResponse(value) {
  if (!value || typeof value.reply !== "string" || !value.reply.trim()) throw new Error("missing_reply");
  if (value.proposal == null) return { reply: value.reply.trim().slice(0, 800), proposal: null };
  if (!wellnessAgentTools.has(value.proposal.tool)) throw new Error("unsupported_tool");
  const args = value.proposal.arguments;
  if (!args || typeof args !== "object" || Array.isArray(args)) throw new Error("invalid_arguments");
  return {
    reply: value.reply.trim().slice(0, 800),
    proposal: {
      tool: value.proposal.tool,
      arguments: validateWellnessArguments(value.proposal.tool, args)
    }
  };
}

function validateWellnessArguments(tool, args) {
  switch (tool) {
    case "record_water":
      if (!integerInRange(args.milliliters, 1, 5000)) throw new Error("invalid_water");
      return { milliliters: args.milliliters };
    case "record_jump_rope": {
      if (!integerInRange(args.count, 1, 100_000)) throw new Error("invalid_jump_count");
      if (args.durationMinutes != null && !integerInRange(args.durationMinutes, 1, 1440)) {
        throw new Error("invalid_jump_duration");
      }
      return {
        count: args.count,
        ...(args.durationMinutes == null ? {} : { durationMinutes: args.durationMinutes })
      };
    }
    case "record_sedentary":
      if (!integerInRange(args.durationMinutes, 1, 1440)) throw new Error("invalid_sedentary_duration");
      return { durationMinutes: args.durationMinutes };
    case "record_weight":
      if (!Number.isFinite(args.kilograms) || args.kilograms <= 0 || args.kilograms > 500) {
        throw new Error("invalid_weight");
      }
      return { kilograms: Number(args.kilograms) };
    case "start_sedentary":
    case "stop_sedentary":
    case "query_today_summary":
      return {};
    default:
      throw new Error("unsupported_tool");
  }
}

function integerInRange(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

async function completeWellnessAgentWithDeepSeek(input, environment, fetchImpl) {
  const systemPrompt = [
    "你是 X-Fit 的健康记录意图理解器，不是医生或自由执行 Agent。",
    "只处理喝水、跳绳、久坐、体重记录与今日汇总。信息不完整时只追问，不猜数值。",
    "只返回 JSON：reply 为简短中文；proposal 为 null，或包含 tool 与 arguments。",
    `tool 只能是：${Array.from(wellnessAgentTools).join(", ")}。`,
    "禁止输出 SQL、代码、URL 或白名单外动作。写操作只是待确认提案，绝不声称已经写入。",
    `本机最小摘要：${JSON.stringify(input.context)}`
  ].join("\n");
  const response = await fetchImpl(environment.DEEPSEEK_API_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${environment.DEEPSEEK_API_KEY}`,
      "Content-Type": "application/json",
      "Accept": "application/json"
    },
    body: JSON.stringify({
      model: environment.DEEPSEEK_MODEL || "deepseek-v4-flash",
      temperature: 0,
      response_format: { type: "json_object" },
      messages: [{ role: "system", content: systemPrompt }, ...input.messages]
    }),
    signal: AbortSignal.timeout(Number(environment.DEEPSEEK_TIMEOUT_MS || 20_000))
  });
  if (!response.ok) throw new Error(`deepseek_http_${response.status}`);
  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content;
  if (typeof content === "string") return JSON.parse(content);
  if (content && typeof content === "object") return content;
  throw new Error("deepseek_content_missing");
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
