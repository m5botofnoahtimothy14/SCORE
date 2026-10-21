// ============================================================
// Edge Function: score-moderation
// Backend ML/scoring processing for the moderation pipeline.
//
// Computes per-category, per-audience precision / recall / F1 from
// moderation_results (model predictions) vs moderation_review_cases
// (human ground truth) and stores one snapshot per school in
// moderation_score_snapshots so the admin dashboard can chart the
// metrics over time.
//
// Positive class = "content needs review".
//   predicted positive : the model raised this category above threshold
//   actual positive    : a human reviewer confirmed it (rejected/escalated)
// Unreviewed content is excluded — there is no ground truth for it.
//
// Auth: internal shared secret (x-webhook-secret) OR a platform
// Super-Admin service-role bearer token.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEYS") ?? "";
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

/** A category counts as "predicted" once the model scores it at/above this. */
const CATEGORY_THRESHOLD = 0.15;

interface CategoryMetrics {
  school_id: string;
  category: string;
  audience: string;
  tp: number;
  fp: number;
  fn: number;
  tn: number;
  precision: number;
  recall: number;
  f1: number;
  support: number;
}

interface ModerationResult {
  id: string;
  school_id: string;
  verdict: string;
  confidence: number | null;
  categories: Record<string, unknown> | null;
  raw_response: Record<string, unknown> | null;
  processed_at: string;
}

interface ReviewCase {
  moderation_result_id: string | null;
  status: string;
  reason_code: string | null;
  school_id: string;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Human outcomes that confirm the model was right to flag the content. */
function isPositiveReview(status: string): boolean {
  return status === "rejected" || status === "escalated";
}

/**
 * Normalise OpenAI moderation category keys to the canonical names used by
 * the policy engine. Rows stored by earlier runs use the raw provider keys
 * ("sexual/minors", "self-harm"), so both shapes are accepted.
 */
function normaliseCategories(raw: Record<string, unknown> | null): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [key, value] of Object.entries(raw ?? {})) {
    const score = Number(value);
    if (!Number.isFinite(score)) continue;
    out[key.replace(/\//g, "_").replace(/-/g, "_").toLowerCase()] = score;
  }
  if (out.sexual_minors === undefined && out.sexual_minor !== undefined) {
    out.sexual_minors = out.sexual_minor;
  }
  return out;
}

/** Read the audience tier recorded on the scoring event. */
function audienceOf(raw: Record<string, unknown> | null): string {
  const a = raw?.audience;
  return typeof a === "string" && a.length > 0 ? a : "unknown";
}

serve(async (req: Request) => {
  const secret = req.headers.get("x-webhook-secret");
  const auth = req.headers.get("authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  // Supabase issues two shapes of service credential: the legacy
  // `role=service_role` JWT and the newer `sb_secret_…` key. Accept
  // whichever this project is configured with.
  const isServiceRole =
    (bearer && (bearer === SUPABASE_SERVICE_ROLE_KEY || bearer === SUPABASE_SECRET_KEY)) === true;

  if (secret !== INTERNAL_WEBHOOK_SECRET && !isServiceRole) {
    return json({ error: "unauthorized" }, 401);
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── Fetch predictions (model output) ──────────────────────
    const { data: mods, error: modsErr } = await supabase
      .from("moderation_results")
      .select("id, school_id, verdict, confidence, categories, raw_response, processed_at")
      .order("processed_at", { ascending: false })
      .limit(20000);
    if (modsErr) throw new Error(`moderation_results: ${modsErr.message}`);

    // ── Fetch ground truth (human review outcomes) ────────────
    const { data: reviews, error: revErr } = await supabase
      .from("moderation_review_cases")
      .select("moderation_result_id, status, reason_code, school_id")
      .not("moderation_result_id", "is", null);
    if (revErr) throw new Error(`moderation_review_cases: ${revErr.message}`);

    const reviewByResult = new Map<string, { status: string; reason_code: string | null }>();
    for (const r of (reviews ?? []) as ReviewCase[]) {
      if (r.moderation_result_id) {
        reviewByResult.set(r.moderation_result_id, {
          status: r.status,
          reason_code: r.reason_code,
        });
      }
    }

    // ── Group by (school, category, audience) ─────────────────
    const buckets = new Map<string, CategoryMetrics>();
    const schoolCounts = new Map<string, { reviews: number; predictions: number }>();

    for (const m of (mods ?? []) as ModerationResult[]) {
      const perSchool = schoolCounts.get(m.school_id) ?? { reviews: 0, predictions: 0 };
      perSchool.predictions++;
      schoolCounts.set(m.school_id, perSchool);

      const review = reviewByResult.get(m.id);
      // Unreviewed content has no ground truth — it cannot be scored.
      if (!review) continue;

      perSchool.reviews++;
      const actualPositive = isPositiveReview(review.status);

      const raw = (m.raw_response ?? {}) as Record<string, unknown>;
      const audience = audienceOf(raw);
      const cats = normaliseCategories((m.categories ?? {}) as Record<string, unknown>);

      for (const [cat, rawScore] of Object.entries(cats)) {
        const score = Number(rawScore);
        if (!Number.isFinite(score)) continue;
        // Only score categories the model actually flagged.
        if (score < CATEGORY_THRESHOLD) continue;

        const key = `${m.school_id}|${cat}|${audience}`;
        let bucket = buckets.get(key);
        if (!bucket) {
          bucket = {
            school_id: m.school_id,
            category: cat,
            audience,
            tp: 0, fp: 0, fn: 0, tn: 0,
            precision: 0, recall: 0, f1: 0, support: 0,
          };
          buckets.set(key, bucket);
        }

        const predictedPositive = score >= CATEGORY_THRESHOLD;
        if (predictedPositive && actualPositive) bucket.tp++;
        else if (predictedPositive && !actualPositive) bucket.fp++;
        else if (!predictedPositive && actualPositive) bucket.fn++;
        else bucket.tn++;

        bucket.support++;
      }
    }

    // ── Compute precision / recall / F1 ────────────────────────
    const bySchool = new Map<string, CategoryMetrics[]>();
    for (const bucket of buckets.values()) {
      const precision = bucket.tp + bucket.fp > 0 ? bucket.tp / (bucket.tp + bucket.fp) : 0;
      const recall = bucket.tp + bucket.fn > 0 ? bucket.tp / (bucket.tp + bucket.fn) : 0;
      const f1 = precision + recall > 0 ? (2 * precision * recall) / (precision + recall) : 0;

      const existing = bySchool.get(bucket.school_id) ?? [];
      existing.push({ ...bucket, precision, recall, f1 });
      bySchool.set(bucket.school_id, existing);
    }

    // ── Persist one snapshot per school ───────────────────────
    const computedAt = new Date().toISOString();
    const rows: Record<string, unknown>[] = [];

    for (const [schoolId, metrics] of bySchool) {
      metrics.sort((a, b) => b.f1 - a.f1);
      const counts = schoolCounts.get(schoolId) ?? { reviews: 0, predictions: 0 };
      rows.push({
        school_id: schoolId,
        computed_at: computedAt,
        total_reviews: counts.reviews,
        total_predictions: counts.predictions,
        metrics,
      });
    }

    if (rows.length > 0) {
      const { error: insertErr } = await supabase
        .from("moderation_score_snapshots")
        .insert(rows);
      if (insertErr) throw new Error(`moderation_score_snapshots: ${insertErr.message}`);
    }

    return json({
      success: true,
      computed_at: computedAt,
      schools_scored: rows.length,
      total_reviews: (reviews ?? []).length,
      total_predictions: (mods ?? []).length,
      metrics: rows.length,
    });
  } catch (err) {
    console.error("score-moderation error:", err);
    return json({ error: "server_error", detail: String(err) }, 500);
  }
});
