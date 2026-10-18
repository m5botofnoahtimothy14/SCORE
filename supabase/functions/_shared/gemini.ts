// ============================================================
// Shared Google Gemini (AI Logic / Vertex AI) provider.
//
// Used by score-conversation, ai-smart-reply and ai-school-insights.
// This layer is ADDITIVE: analytics + writing assistance only.
// OpenAI moderation remains the safety authority and is never
// replaced or bypassed by anything in this file.
//
// Provider order:
//   1. GOOGLE_API_KEY  -> Generative Language API (v1beta)
//   2. FIREBASE_API_KEY / FIREBASE_PROJECT_ID
//                    -> Firebase AI Logic (Vertex AI) endpoint
// If neither is configured we throw AiUnavailableError so the
// caller can answer 503 ai_unavailable. We never fail open and
// we never fabricate a result when the provider errors.
// ============================================================

export const DEFAULT_MODEL = "gemini-2.0-flash";

const GOOGLE_API_BASE = "https://generativelanguage.googleapis.com/v1beta";
const FIREBASE_VERTEX_BASE = "https://firebasevertexai.googleapis.com/v1beta";
const OPENAI_BASE = "https://api.openai.com/v1";
const DEFAULT_OPENAI_MODEL = "gpt-4o-mini";

// Firebase web config for this app. The web API key is a public,
// client-shipped identifier (it is already in the mobile bundle);
// the edge function still prefers a secret when one is configured.
const DEFAULT_FIREBASE_PROJECT_ID = "teachcross-38f29";
const DEFAULT_FIREBASE_API_KEY = "AIzaSyCtE6cWXQ9xZA0kNY1vp3-V_YwaEbV7szM";
const DEFAULT_FIREBASE_LOCATION = "us-central1";

export type AiProvider = "google_api" | "firebase_vertex" | "openai";

export type AiRoute = {
  provider: AiProvider;
  model: string;
  endpoint: string;
  key: string;
  /// OpenAI uses a chat-completions contract rather than Google's.
  dialect: "gemini" | "openai";
};

export type GeminiResult = {
  text: string;
  model: string;
  provider: AiProvider;
};

/// Thrown when no Gemini credential is configured at all (503).
export class AiUnavailableError extends Error {
  readonly code = "ai_unavailable";
  constructor(message: string) {
    super(message);
    this.name = "AiUnavailableError";
  }
}

/// Thrown when a provider is configured but the call fails (502).
export class AiProviderError extends Error {
  readonly code = "ai_provider_error";
  readonly provider: AiProvider;
  constructor(provider: AiProvider, message: string) {
    super(message);
    this.name = "AiProviderError";
    this.provider = provider;
  }
}

function env(name: string): string | undefined {
  const v = Deno.env.get(name);
  if (v === undefined || v === null) return undefined;
  const t = v.trim();
  return t.length > 0 ? t : undefined;
}

/// Every configured route, most-preferred first:
///   1. GOOGLE_API_KEY        -> Generative Language API (v1beta)
///   2. FIREBASE_API_KEY      -> Firebase AI Logic (Vertex AI)
///   3. OPENAI_API_KEY        -> chat completions (keeps AI alive if the
///                               Firebase project's Google APIs are disabled)
export function resolveAiRoutes(): AiRoute[] {
  const routes: AiRoute[] = [];

  const googleKey = env("GOOGLE_API_KEY");
  if (googleKey) {
    const model = env("GEMINI_MODEL") ?? DEFAULT_MODEL;
    routes.push({
      provider: "google_api",
      model,
      endpoint: `${GOOGLE_API_BASE}/models/${model}`,
      key: googleKey,
      dialect: "gemini",
    });
  }

  const firebaseKey = env("FIREBASE_API_KEY") ?? DEFAULT_FIREBASE_API_KEY;
  const firebaseProject = env("FIREBASE_PROJECT_ID") ?? DEFAULT_FIREBASE_PROJECT_ID;
  const location = env("FIREBASE_AI_LOCATION") ?? DEFAULT_FIREBASE_LOCATION;
  if (firebaseKey && firebaseProject) {
    const model = env("GEMINI_MODEL") ?? DEFAULT_MODEL;
    routes.push({
      provider: "firebase_vertex",
      model,
      endpoint:
        `${FIREBASE_VERTEX_BASE}/projects/${firebaseProject}/locations/${location}` +
        `/publishers/google/models/${model}`,
      key: firebaseKey,
      dialect: "gemini",
    });
  }

  const openaiKey = env("OPENAI_API_KEY");
  if (openaiKey) {
    routes.push({
      provider: "openai",
      model: env("OPENAI_CHAT_MODEL") ?? DEFAULT_OPENAI_MODEL,
      endpoint: `${OPENAI_BASE}/chat/completions`,
      key: openaiKey,
      dialect: "openai",
    });
  }

  if (routes.length === 0) {
    throw new AiUnavailableError(
      "No AI credential configured: set GOOGLE_API_KEY (preferred), FIREBASE_API_KEY + FIREBASE_PROJECT_ID, or OPENAI_API_KEY.",
    );
  }
  return routes;
}

/// Pick the first configured Gemini transport, or throw AiUnavailableError.
export function resolveAiRoute(): AiRoute {
  return resolveAiRoutes()[0];
}

/// True when at least one Gemini transport is configured.
export function isAiConfigured(): boolean {
  try {
    resolveAiRoute();
    return true;
  } catch {
    return false;
  }
}

export type GeminiRequest = {
  systemInstruction: string;
  prompt: string;
  responseMimeType?: "application/json" | "text/plain";
  temperature?: number;
  maxOutputTokens?: number;
};

/// Call the preferred provider; on provider failure fall through to the next
/// configured provider. Only surfaces an error once every route has failed.
export async function callGemini(req: GeminiRequest): Promise<GeminiResult> {
  const routes = resolveAiRoutes();
  let lastError: AiProviderError | null = null;

  for (const route of routes) {
    try {
      return await callOne(route, req);
    } catch (e) {
      if (e instanceof AiProviderError) {
        console.warn(`provider ${route.provider} failed, trying next: ${e.message}`);
        lastError = e;
        continue;
      }
      throw e;
    }
  }
  throw lastError ?? new AiProviderError(routes[0].provider, "all providers failed");
}

async function callOne(route: AiRoute, req: GeminiRequest): Promise<GeminiResult> {
  const temperature = req.temperature ?? 0.2;
  const maxTokens = req.maxOutputTokens ?? 1024;

  let endpoint: string;
  let headers: Record<string, string>;
  let body: unknown;

  if (route.dialect === "openai") {
    endpoint = route.endpoint;
    headers = { "Content-Type": "application/json", Authorization: `Bearer ${route.key}` };
    const messages: { role: string; content: string }[] = [
      { role: "system", content: req.systemInstruction },
      { role: "user", content: req.prompt },
    ];
    body = {
      model: route.model,
      messages,
      temperature,
      max_tokens: maxTokens,
    };
    if (req.responseMimeType === "application/json") {
      body = { ...(body as object), response_format: { type: "json_object" } };
    }
  } else {
    endpoint = `${route.endpoint}:generateContent?key=${encodeURIComponent(route.key)}`;
    headers = { "Content-Type": "application/json" };
    const generationConfig: Record<string, unknown> = {
      temperature,
      maxOutputTokens: maxTokens,
    };
    if (req.responseMimeType) generationConfig.responseMimeType = req.responseMimeType;
    body = {
      systemInstruction: { parts: [{ text: req.systemInstruction }] },
      contents: [{ role: "user", parts: [{ text: req.prompt }] }],
      generationConfig,
    };
  }

  let res: Response;
  try {
    res = await fetch(endpoint, { method: "POST", headers, body: JSON.stringify(body) });
  } catch (e) {
    throw new AiProviderError(route.provider, `network error: ${String((e as Error)?.message ?? e)}`);
  }

  if (!res.ok) {
    const detail = (await res.text()).slice(0, 400);
    throw new AiProviderError(route.provider, `HTTP ${res.status}: ${detail}`);
  }

  let data: any;
  try {
    data = await res.json();
  } catch {
    throw new AiProviderError(route.provider, "unparseable JSON response");
  }

  const text = route.dialect === "openai"
    ? String(data?.choices?.[0]?.message?.content ?? "").trim()
    : extractGeminiText(data, route.provider);

  if (!text) throw new AiProviderError(route.provider, "empty model output");

  return { text, model: route.model, provider: route.provider };
}

function extractGeminiText(data: any, provider: AiProvider): string {
  if (data?.promptFeedback?.blockReason) {
    throw new AiProviderError(provider, `prompt blocked: ${data.promptFeedback.blockReason}`);
  }
  const candidate = data?.candidates?.[0];
  if (!candidate) {
    throw new AiProviderError(provider, `no candidates in response: ${JSON.stringify(data).slice(0, 300)}`);
  }
  if (candidate.finishReason && candidate.finishReason !== "STOP") {
    throw new AiProviderError(provider, `finish reason: ${candidate.finishReason}`);
  }
  const parts = candidate?.content?.parts ?? [];
  return parts
    .map((p: any) => (typeof p?.text === "string" ? p.text : ""))
    .join("")
    .trim();
}

// ============================================================
// Defensive parsing helpers — model output is never trusted.
// ============================================================

/// Strip ```json / ``` fences and surrounding prose.
export function stripJsonFences(raw: string): string {
  let text = raw.trim();
  const fenced = text.match(/^```[a-zA-Z]*\s*([\s\S]*?)\s*```$/);
  if (fenced) return fenced[1].trim();
  // A fence that is never closed (truncated output).
  if (text.startsWith("```")) {
    const stripped = text.replace(/^```[a-zA-Z]*\s*/, "");
    text = stripped;
  }
  return text.trim();
}

function sliceBalanced(text: string): string | null {
  const openers: Record<string, string> = { "{": "}", "[": "]" };
  const firstObj = text.indexOf("{");
  const firstArr = text.indexOf("[");
  let start = -1;
  if (firstObj === -1 && firstArr === -1) return null;
  if (firstObj === -1) start = firstArr;
  else if (firstArr === -1) start = firstObj;
  else start = Math.min(firstObj, firstArr);

  const stack: string[] = [];
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (openers[ch]) stack.push(openers[ch]);
    else if (ch === "}" || ch === "]") {
      const want = stack.pop();
      if (want !== ch) return null;
      if (stack.length === 0) return text.slice(start, i + 1);
    }
  }
  return null;
}

/// Parse model JSON output tolerantly: raw, de-fenced, then balanced-slice.
export function parseLooseJson<T = any>(raw: string): T | null {
  if (!raw) return null;
  const candidates = [raw.trim(), stripJsonFences(raw)];
  const balanced = sliceBalanced(raw);
  if (balanced) candidates.push(balanced);
  const balanced2 = sliceBalanced(stripJsonFences(raw));
  if (balanced2) candidates.push(balanced2);

  for (const c of candidates) {
    if (!c) continue;
    try {
      return JSON.parse(c) as T;
    } catch {
      /* try next strategy */
    }
  }
  return null;
}

/// Force any model-supplied number into 0..100.
/// null/undefined/booleans/blank strings fall back rather than coercing to 0
/// (Number(null) === 0, which would silently read as "no safety risk").
export function clampScore(value: unknown, fallback: number): number {
  if (typeof value === "boolean") return fallback;
  if (typeof value === "string" && value.trim() === "") return fallback;
  if (value === null || value === undefined) return fallback;
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(100, Math.max(0, Math.round(n * 100) / 100));
}

/// Average of a numeric column, ignoring nulls.
export function average(values: Array<number | null | undefined>): number | null {
  const nums = values.filter((v): v is number => typeof v === "number" && Number.isFinite(v));
  if (nums.length === 0) return null;
  const sum = nums.reduce((a, b) => a + b, 0);
  return Math.round((sum / nums.length) * 100) / 100;
}

/// Loose uuid check so we never forward garbage into PostgREST.
export function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

/// Normalise an arbitrary model string into a bounded single-line label.
export function cleanLabel(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/[*_`#>]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!cleaned) return null;
  return cleaned.length > maxLength ? cleaned.slice(0, maxLength - 1).trim() + "…" : cleaned;
}

/// Shared console logger so every function reports the same fields.
export function logAiError(fn: string, err: unknown) {
  if (err instanceof AiUnavailableError) {
    console.error(`${fn}: ai_unavailable — ${err.message}`);
  } else if (err instanceof AiProviderError) {
    console.error(`${fn}: ai_provider_error (${err.provider}) — ${err.message}`);
  } else {
    console.error(`${fn} error:`, err);
  }
}