// ============================================================
// Edge Function: score-moderation
// Backend ML/scoring processing for moderation pipeline.
//
// Computes per-category, per-audience F1 scores from
// moderation_results (model predictions) vs
// moderation_review_cases (human ground truth).
//
// Stores metric snapshots in moderation_score_snapshots so the
// admin dashboard can display precision / recall / F1 over time.
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

type Category = "sexual" | "sexual_minors" | "hate" | "harassment" | "harassment_threatening" | "violence" | "self_harm" | "illicit";

interface CategoryMetrics {
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

serve(async (req: Request) => {
  const secret = req.headers.get("x-webhook-secret");
  if (secret !== INTERNAL_WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── Fetch predictions (model output) ──────────────────────
    const { data: mods } = await supabase
      .from("moderation_results")
      .select("message_id, attachment_id, verdict, confidence, categories, raw_response, school_id, created_at")
      .order("created_at", { ascending: false });

    // ── Fetch ground truth (human review outcomes) ────────────
    const { data: reviews } = await supabase
      .from("moderation_review_cases")
      .select("status, reason_code, moderation_result_id, school_id, created_at")
      .not("moderation_result_id", "is", null);

    if (!mods) return new Response("No moderation data", { status: 200 });

    // Build lookup: moderation_result_id -> review
    const reviewByResult = new Map<string, { status: string; reason_code: string }>();
    for (const r of reviews ?? []) {
      if (r.moderation_result_id) {
        reviewByResult.set(r.moderation_result_id, { status: r.status, reason_code: r.reason_code });
      }
    }

    // ── Group predictions by (category, audience) ─────────────
    const buckets = new Map<string, CategoryMetrics>();

    for (const m of mods) {
      const raw = m.raw_response as any;
      const audience = raw?.audience ?? "unknown";
      const cats = (m.categories as CategoryScores) ?? {};

      // Only evaluate categories that have a signal score >= 0.1
      const relevantCats: string[] = [];
      for (const [cat, score] of Object.entries(categories)) {
        if (Number(score) >= 0.15) relevantCats.push(cat);
      }

      const review = reviewByResult.get(m.id);
      const actualApproved = review
        ? review.status === "approved" || review.reason_code === "approved"
        : null; // null = unreviewed, skip for F1

      if (actualApproved === null) continue; // unreviewed — cannot score

      for (const cat of relevantCats) {
        const key = `${cat}|${audience}`;
        let m = buckets.get(key);
        if (!m) {
          m = { category: cat, audience, tp: 0, fp: 0, fn: 0, tn: 0, precision: 0, recall: 0, f1: 0, support: 0 };
          buckets.set(key, m);
        }

        const predictedApproved = m.action === "approved" || m.action === "warned";
        const score = Number(cats[cat]) || 0;

        if (predictedApproved && actualApproved) m.tp++;
        else if (predictedApproved && !actualApproved) m.fp++;
        else if (!predictedApproved && actualApproved) m.fn++;
        else if (!predictedApproved && !actualApproved) m.tn++;

        m.support++;
      }
    }

    // ── Compute precision/recall/F1 ───────────────────────────
    const results: CategoryMetrics[] = [];
    for (const m of buckets.values()) {
      const precision = m.tp + m.fp > 0 ? m.tp / (m.tp + m.fp) : 0;
      const recall = m.tp + m.fn > 0 ? m.tp / (m.tp + m.fn) : 0;
      const f1 = precision + recall > 0 ? 2 * (precision * recall) / (precision + recall) : 0;
      results.push({ ...m, precision, recall, f1 });
    }

    results.sort((a, b) => b.f1 - a.f1);

    // ── Persist snapshot ──────────────────────────────────────
    const snapshot = {
      computed_at: new Date().toISOString(),
      total_reviews: reviews?.length ?? 0,
      total_predictions: mods?.length ?? 0,
      results,
    };

    const { error } = await supabase
      .from("moderation_score_snapshots")
      .insert({
        school_id: "all",
        computed_at: snapshot.computed_at,
        total_reviews: snapshot.total_reviews,
        total_predictions: snapshot.total_predictions,
        metrics: snapshot.results,
      });

    if (error) {
      console.error("snapshot insert error:", error);
      // Non-fatal — still return results
    }

    return new Response(JSON.stringify(snapshot), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("score-moderation error:", err);
    return new Response("Server error", { status: 500 });
  }
});
