// Google Cloud Vision SafeSearch integration.
//
// Two ways to authenticate, in order of preference:
//   1. GOOGLE_CLOUD_VISION_API_KEY — a plain API key on the Vision API.
//   2. The project's service account (FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY)
//      with the cloud-platform scope, which works when the service account
//      has the Cloud Vision API enabled on the project.
//
// The result is normalised into the same category scores the policy engine
// already understands, so the policy thresholds do not change.
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";

const VISION_ENDPOINT = "https://vision.googleapis.com/v1/images:annotate";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/cloud-platform";

export interface VisionResult {
  /** Normalised category scores, 0..1. */
  categories: Record<string, number>;
  /** Which credential actually answered. */
  provider: string;
  /** Present when the call failed — the caller then falls back. */
  error?: string;
}

let cachedToken: string | null = null;
let cachedTokenExp = 0;

/** Reads a Vision probability into a 0..1 score. */
function probability(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value !== "string") return 0;
  switch (value.toUpperCase()) {
    case "VERY_UNLIKELY":
    case "UNLIKELY":
      return 0.05;
    case "POSSIBLE":
      return 0.5;
    case "LIKELY":
      return 0.8;
    case "VERY_LIKELY":
      return 0.98;
    default:
      return 0;
  }
}

/**
 * Runs SafeSearch detection on the image bytes.
 * Returns an error instead of throwing — the caller decides what to do.
 */
export async function detectSafeSearch(
  bytes: Uint8Array,
  opts: {
    apiKey?: string;
    clientEmail?: string;
    privateKey?: string;
  },
): Promise<VisionResult> {
  const dataUrl = base64Encode(bytes);
  const body = JSON.stringify({
    requests: [
      {
        image: { content: dataUrl },
        features: [{ type: "SAFE_SEARCH_DETECTION" }],
      },
    ],
  });

  // 1. API key.
  if (opts.apiKey) {
    const res = await fetch(`${VISION_ENDPOINT}?key=${encodeURIComponent(opts.apiKey)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    if (res.ok) {
      const parsed = await res.json();
      const normalised = normalise(parsed);
      if (normalised) return { categories: normalised, provider: "google_vision" };
      return { categories: {}, provider: "google_vision", error: "no safeSearchAnnotation" };
    }
    const detail = (await res.text()).slice(0, 200);
    // Fall through to the service-account attempt.
    if (!opts.clientEmail || !opts.privateKey) {
      return { categories: {}, provider: "google_vision", error: `HTTP ${res.status}: ${detail}` };
    }
  }

  // 2. Service account.
  if (!opts.clientEmail || !opts.privateKey) {
    return { categories: {}, provider: "none", error: "no Vision credentials configured" };
  }

  try {
    const token = await getAccessToken(opts.clientEmail, opts.privateKey);
    const res = await fetch(VISION_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body,
    });
    if (!res.ok) {
      const detail = (await res.text()).slice(0, 200);
      return { categories: {}, provider: "google_vision", error: `HTTP ${res.status}: ${detail}` };
    }
    const parsed = await res.json();
    const normalised = normalise(parsed);
    if (!normalised) {
      return { categories: {}, provider: "google_vision", error: "no safeSearchAnnotation" };
    }
    return { categories: normalised, provider: "google_vision" };
  } catch (e) {
    return {
      categories: {},
      provider: "google_vision",
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

/** Maps the SafeSearch annotation onto the policy engine's category names. */
function normalise(parsed: any): Record<string, number> | null {
  const annotation =
    parsed?.responses?.[0]?.safeSearchAnnotation ??
    parsed?.responses?.[0]?.error ??
    null;
  if (!annotation || annotation.adult === undefined) return null;

  return {
    // Vision's "adult" covers sexual content; "racy" is suggestive content.
    sexual: probability(annotation.adult),
    sexual_minors: probability(annotation.adult) * probability(annotation.racy),
    violence: probability(annotation.violence),
    harassment: probability(annotation.racy) * 0.5,
    illicit: probability(annotation.medical) * 0.25,
    self_harm: probability(annotation.violence) * 0.5,
  };
}

async function getAccessToken(clientEmail: string, privateKey: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedTokenExp > now + 60) return cachedToken;

  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: clientEmail,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;

  const key = await importPrivateKey(privateKey);
  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(signature))}`;

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`token endpoint ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const data = await res.json();
  cachedToken = data.access_token;
  cachedTokenExp = now + (data.expires_in ?? 3600);
  return cachedToken!;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const normalized = pem.replace(/\\n/g, "\n");
  const body = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function b64url(s: string): string {
  return b64urlBytes(new TextEncoder().encode(s));
}

function b64urlBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
