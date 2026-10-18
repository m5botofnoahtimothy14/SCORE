// ============================================================
// TeachCross moderation policy — evaluation harness.
//
//   node --test tests/moderation_policy.test.mjs
//
// The module under test is the REAL edge module:
//   supabase/functions/_shared/moderation_policy.ts
// (node >= 22.6 strips its types natively; there is no mirror copy to
// drift out of sync).
//
// This file is an evaluation, not a smoke test: it runs a labelled
// dataset, prints precision / recall / F1 / false-positive rate at
// several threshold scalings, and asserts that the SHIPPED defaults
// clear the stated bar:
//     F1 >= 0.90  AND  false-positive rate <= 0.10 on benign cases.
// Any change to DEFAULT_POLICY must re-run this. See docs/MODERATION.md.
// ============================================================
import test from "node:test";
import assert from "node:assert/strict";
import { DATASET, DATASET_STATS } from "./fixtures/moderation_dataset.mjs";

// --- load the real module -------------------------------------------------
// Native type stripping is required. If it is unavailable the metric tests
// skip (with a reason), but the very first test below still FAILS LOUDLY so a
// genuine syntax error can never hide behind a skip.
let policyMod = null;
let importError = null;
try {
  policyMod = await import("../supabase/functions/_shared/moderation_policy.ts");
} catch (err) {
  importError = err;
}
const SKIP = importError
  ? `requires native TypeScript type stripping (Node >= 22.6, ideally >= 23.6): ${importError.message}`
  : false;

const {
  DEFAULT_POLICY,
  applyPolicy,
  effectiveThresholds,
  matchAllowlist,
  normaliseText,
  toTextVerdict,
  toImageVerdict,
  explainDecision,
  resolveAudience,
} = policyMod ?? {};

// --- the bar --------------------------------------------------------------
const BAR_F1 = 0.9;
const BAR_FPR = 0.1;

// ============================================================
// Harness
// ============================================================

function decide(tc, policy = DEFAULT_POLICY) {
  return applyPolicy(
    {
      categories: tc.categories,
      text: tc.text ?? "",
      context: {
        media: tc.media ?? "text",
        audience: tc.audience ?? "unknown",
        senderRole: tc.senderRole ?? "student",
        provider: "openai",
        nudityScore: tc.nudityScore ?? null,
      },
    },
    policy,
  );
}

function isFlagged(action) {
  // A hold reaches a human; a block does not reach a student. Both are
  // "flagged" for the precision/recall maths, because both stop delivery.
  return action !== "approve";
}

/**
 * Confusion matrix.
 *   positive case + flagged  -> TP   (correctly surfaced)
 *   positive case + approve  -> FN   (DANGEROUS: bad content delivered)
 *   benign   case + flagged  -> FP   (learning conversation interrupted)
 *   benign   case + approve  -> TN
 */
function metrics(results) {
  let tp = 0;
  let fp = 0;
  let tn = 0;
  let fn = 0;
  let blockedBenign = 0;
  let heldBenign = 0;
  const errors = [];

  for (const r of results) {
    const flagged = isFlagged(r.action);
    const actual = r.label === "positive";
    if (actual && flagged) tp++;
    else if (actual) fn++;
    else if (flagged) fp++;
    else tn++;
    if (!actual && r.action === "block") {
      blockedBenign++;
      errors.push(`${r.id} BENIGN BLOCKED "${truncate(r.text || `[image nudity=${r.nudityScore}]`, 58)}" -> ${r.action}`);
    }
    if (!actual && r.action === "hold_for_review") {
      heldBenign++;
      errors.push(`${r.id} benign held "${truncate(r.text || `[image nudity=${r.nudityScore}]`, 58)}" -> ${r.action}`);
    }
    if (actual && r.action === "approve") {
      errors.push(`${r.id} POSITIVE APPROVED "${truncate(r.text, 58)}" -> ${r.action} (${r.rules.join(", ")})`);
    }
  }

  const benign = fp + tn;
  const positive = tp + fn;
  const precision = tp + fp > 0 ? tp / (tp + fp) : 0;
  const recall = positive > 0 ? tp / positive : 0;
  const f1 = precision + recall > 0 ? (2 * precision * recall) / (precision + recall) : 0;

  return {
    tp,
    fp,
    tn,
    fn,
    benign,
    positive,
    precision: r4(precision),
    recall: r4(recall),
    f1: r4(f1),
    accuracy: r4((tp + tn) / (tp + fp + tn + fn)),
    fpr: r4(benign > 0 ? fp / benign : 0),
    fnr: r4(positive > 0 ? fn / positive : 0),
    blockedBenign,
    heldBenign,
    fprBlock: r4(benign > 0 ? blockedBenign / benign : 0),
    errors,
  };
}

const r4 = (n) => Math.round(n * 10000) / 10000;
const truncate = (s, n) => (s && s.length > n ? `${s.slice(0, n - 1)}…` : (s ?? ""));

/** Build a tuned copy of the policy with globally scaled thresholds. */
function scalePolicy(base, { hold = 1, block = 1, aggregate = null, minCategories = null } = {}) {
  const categories = {};
  for (const [key, spec] of Object.entries(base.categories)) {
    categories[key] = {
      ...spec,
      hold: clamp01(spec.hold * hold),
      block: clamp01(spec.block * block),
    };
  }
  return {
    ...base,
    version: `${base.version}+hold${hold}/block${block}`,
    categories,
    multiSignal: {
      minCategoriesToBlock: minCategories ?? base.multiSignal.minCategoriesToBlock,
      aggregateBlockScore: aggregate ?? base.multiSignal.aggregateBlockScore,
    },
  };
}

const clamp01 = (n) => Math.min(0.995, Math.max(0.001, n));

function run(policy = DEFAULT_POLICY) {
  return DATASET.map((tc) => {
    const d = decide(tc, policy);
    return {
      id: tc.id,
      label: tc.label,
      expect: tc.expect,
      note: tc.note,
      edge: tc.edge,
      media: tc.media ?? "text",
      nudityScore: tc.nudityScore,
      text: tc.text,
      audience: d.audience,
      action: d.action,
      verdict: tc.media === "image" ? toImageVerdict(d) : toTextVerdict(d),
      escalate: d.escalate,
      score: d.score,
      reasons: [...d.reasons],
      rules: [...d.matchedRules],
      allowlist: [...d.allowlistMatches],
      decision: d,
    };
  });
}

function pad(s, n, right = false) {
  const str = String(s);
  const out = str.length >= n ? str.slice(0, n) : str + " ".repeat(n - str.length);
  return right ? out : out;
}

function printTable(title, rows) {
  console.log("");
  console.log(title);
  console.log(
    pad("  policy", 26) +
      pad("TP", 5, true) +
      pad("FP", 5, true) +
      pad("TN", 5, true) +
      pad("FN", 5, true) +
      pad("prec", 8, true) +
      pad("recall", 8, true) +
      pad("F1", 8, true) +
      pad("FP-rate", 9, true) +
      pad("blocked-benign", 16, true),
  );
  console.log("  " + "-".repeat(96));
  for (const r of rows) {
  console.log(
    "  " +
      pad(r.policy, 32) +
        pad(r.tp, 5, true) +
        pad(r.fp, 5, true) +
        pad(r.tn, 5, true) +
        pad(r.fn, 5, true) +
        pad(r.precision.toFixed(4), 8, true) +
        pad(r.recall.toFixed(4), 8, true) +
        pad(r.f1.toFixed(4), 8, true) +
        pad(r.fpr.toFixed(4), 9, true) +
        pad(r.blockedBenign, 16, true),
    );
  }
}

function sweepReport() {
  const holdScales = [0.7, 0.85, 1.0, 1.15, 1.3, 1.45, 1.6];
  const rows = holdScales.map((s) => {
    const m = metrics(run(scalePolicy(DEFAULT_POLICY, { hold: s })));
    return { policy: `hold x${s.toFixed(2)}${s === 1 ? "  <== SHIPPED" : ""}`, ...m };
  });
  printTable("THRESHOLD SWEEP  (hold bars scaled; block bars untouched)", rows);

  const blockScales = [0.8, 0.9, 1.0, 1.1, 1.25];
  const rows2 = blockScales.map((s) => {
    const m = metrics(run(scalePolicy(DEFAULT_POLICY, { block: s })));
    return { policy: `block x${s.toFixed(2)}${s === 1 ? "  <== SHIPPED" : ""}`, ...m };
  });
  printTable("THRESHOLD SWEEP  (block bars scaled; hold bars untouched)", rows2);

  const aggs = [0.5, 0.56, 0.62, 0.7, 0.78];
  const rows3 = aggs.map((a) => {
    const m = metrics(run(scalePolicy(DEFAULT_POLICY, { aggregate: a })));
    return { policy: `multisignal bar ${a.toFixed(2)}${a === 0.62 ? "  <== SHIPPED" : ""}`, ...m };
  });
  printTable("THRESHOLD SWEEP  (multi-signal aggregate bar)", rows3);

  const mins = [1, 2, 3];
  const rows4 = mins.map((n) => {
    const m = metrics(run(scalePolicy(DEFAULT_POLICY, { minCategories: n })));
    return { policy: `min categories ${n}${n === 2 ? "  <== SHIPPED" : ""}`, ...m };
  });
  printTable("MULTI-SIGNAL RULE  (categories required to block without a critical hit)", rows4);

  return rows;
}

// ============================================================
// 1. The module must load
// ============================================================
test("moderation_policy.ts loads (no syntax/type errors)", () => {
  assert.equal(
    importError,
    null,
    `moderation_policy.ts failed to load: ${importError?.stack ?? ""}`,
  );
  assert.equal(typeof applyPolicy, "function");
});

// ============================================================
// 2. Dataset shape
// ============================================================
test("dataset has >= 60 labelled cases and covers both classes", { skip: SKIP }, () => {
  assert.ok(DATASET.length >= 60, `dataset has only ${DATASET.length} cases`);
  assert.ok(DATASET_STATS.benign >= 30, `only ${DATASET_STATS.benign} benign cases`);
  assert.ok(DATASET_STATS.positive >= 20, `only ${DATASET_STATS.positive} positive cases`);
  const ids = new Set(DATASET.map((c) => c.id));
  assert.equal(ids.size, DATASET.length, "duplicate case ids");
  for (const c of DATASET) {
    assert.ok(c.label === "benign" || c.label === "positive", `${c.id} has no label`);
    assert.ok(typeof c.note === "string" && c.note.length > 0, `${c.id} has no note`);
  }
});

// ============================================================
// 3. THE MEASUREMENT — prints the results tables
// ============================================================
test("policy evaluation: precision / recall / F1 / false-positive rate", { skip: SKIP }, () => {
  console.log("");
  console.log("TeachCross moderation policy evaluation");
  console.log("======================================");
  console.log(
    `dataset: ${DATASET_STATS.total} cases (${DATASET_STATS.benign} benign, ${DATASET_STATS.positive} positive, ${DATASET_STATS.edge} flagged edge, ${DATASET_STATS.images} image)`,
  );
  console.log(`policy version: ${DEFAULT_POLICY.version}`);
  console.log(`bar: F1 >= ${BAR_F1} AND false-positive rate <= ${BAR_FPR} on benign cases`);

  const results = run();
  const m = metrics(results);

  printTable("SHIPPED DEFAULT POLICY", [{ policy: `v${DEFAULT_POLICY.version}  <== SHIPPED`, ...m }]);
  sweepReport();

  console.log("");
  console.log(`errors (blocked benign / held benign / approved positive): ${m.errors.length}`);
  for (const e of m.errors) console.log(`  ${e}`);
  console.log("");

  // Every case must land on one of the three actions.
  for (const r of results) {
    assert.ok(["approve", "hold_for_review", "block"].includes(r.action), `${r.id}: bad action ${r.action}`);
  }

  // --- the bar ---
  assert.ok(m.f1 >= BAR_F1, `F1 ${m.f1} < ${BAR_F1}`);
  assert.ok(m.fpr <= BAR_FPR, `false-positive rate ${m.fpr} > ${BAR_FPR}`);
  // Stricter than the bar: benign content must not be BLOCKED at all in
  // the shipped config beyond a 5% tolerance.
  assert.ok(m.fprBlock <= 0.05, `benign block rate ${m.fprBlock} > 0.05`);

  // The sharp invariant. A positive case may be approved if the VENDOR
  // simply never sent a signal (documented limitation, case p27), but the
  // POLICY LAYER must never actively allowlist harm away. This is the
  // property that would catch a bad allowlist edit immediately.
  const allowlistedHarm = results.filter(
    (r) => r.label === "positive" && r.action === "approve" && r.rules.includes("allowlist_approve"),
  );
  assert.deepEqual(
    allowlistedHarm.map((r) => `${r.id}: ${r.rules.join(", ")}`),
    [],
    "the allowlist approved a labelled positive case",
  );
  // And the allowlist must not be a loophole for CSAE / self-harm.
  for (const r of results.filter((x) => x.label === "positive")) {
    for (const s of r.decision.signals) {
      if ((s.category === "sexual_minors" || s.category === "self_harm") && s.score >= s.block) {
        assert.equal(s.suppressedBy, null, `${r.id}: allowlist suppressed a block-level ${s.category}`);
      }
    }
  }
});

// ============================================================
// 4. Per-case expected outcomes (the intent behind each positive)
// ============================================================
test("labelled positives reach the intended outcome", { skip: SKIP }, () => {
  const results = run();
  const byId = new Map(results.map((r) => [r.id, r]));
  const failures = [];

  for (const tc of DATASET) {
    if (!tc.expect || tc.accept) continue;
    const r = byId.get(tc.id);
    // The dataset writes "hold" for readability; the policy's action name
    // is hold_for_review.
    const want = tc.expect === "hold" ? "hold_for_review" : tc.expect;
    const ok = want === "hold_or_block" ? r.action === "hold_for_review" || r.action === "block" : r.action === want;
    if (!ok) failures.push(`${tc.id} expected ${want}, got ${r.action} — ${tc.note}`);
  }
  assert.deepEqual(failures, [], `\n  ${failures.join("\n  ")}`);

  // `accept: true` marks a case as a knowingly-accepted miss. Those must
  // never be quietly removed from the dataset — they are the documented
  // limitations in docs/MODERATION.md.
  const accepted = DATASET.filter((c) => c.accept);
  assert.ok(accepted.length > 0, "no accepted-miss cases left; limitations docs would go stale");
  for (const tc of accepted) {
    assert.ok(tc.note.startsWith("KNOWN"), `${tc.id} is marked accept:true but is not a known limitation`);
  }
});

// ============================================================
// 5. Explainability — every hold must justify itself
// ============================================================
test("every hold_for_review decision explains itself", { skip: SKIP }, () => {
  const results = run();
  const holds = results.filter((r) => r.action === "hold_for_review");
  assert.ok(holds.length > 0, "no holds produced — the dataset does not exercise the path");

  for (const r of holds) {
    assert.ok(r.reasons.length > 0, `${r.id}: hold with no reasons`);
    assert.ok(r.rules.length > 0, `${r.id}: hold with no matchedRules`);
    const cited = r.reasons.some(
      (reason) => /score=/.test(reason) && /threshold=/.test(reason) && /category=\w+/.test(reason),
    );
    assert.ok(cited, `${r.id}: no reason cites category + score + threshold:\n    ${r.reasons.join("\n    ")}`);
    // The top elevated category must be named in a rule id.
    assert.ok(
      r.rules.some((rule) => rule.startsWith("signal:") || rule.startsWith("fail_closed") || rule.startsWith("image:")),
      `${r.id}: hold cites no elevated signal rule: ${r.rules.join(", ")}`,
    );
  }

  // And the reasons must be readable, e.g.
  //   "held: category=self_harm score=0.74 threshold=0.55 (...)"
  const sample = holds[0];
  assert.match(explainDecision(sample.decision), /^held: /);
});

test("allowlist approvals name the term and the benign context", { skip: SKIP }, () => {
  const results = run();
  const allowlisted = results.filter((r) => r.rules.includes("allowlist_approve"));
  assert.ok(allowlisted.length >= 5, `only ${allowlisted.length} allowlist approvals — allowlist is not doing work`);
  for (const r of allowlisted) {
    assert.ok(
      r.reasons.some((reason) => /approved via allowlist: '.*'/.test(reason)),
      `${r.id}: allowlist approval does not name the rule: ${r.reasons.join(" | ")}`,
    );
    assert.ok(r.allowlist.length > 0, `${r.id}: allowlist_approve with no allowlistMatches`);
  }
});

// ============================================================
// 6. The multi-signal rule — the core false-positive defence
// ============================================================
test("a single non-critical category NEVER blocks", { skip: SKIP }, () => {
  const cases = [
    { label: "bullying at 0.87", categories: { harassment: 0.87 }, expect: "hold_for_review" },
    { label: "violence at 0.72", categories: { violence: 0.72 }, expect: "hold_for_review" },
    { label: "illicit at 0.88", categories: { illicit: 0.88 }, expect: "hold_for_review" },
    { label: "bullying just under block", categories: { harassment: 0.92 }, expect: "hold_for_review" },
  ];
  for (const c of cases) {
    const d = applyPolicy({
      categories: c.categories,
      text: "no context words at all",
      context: { provider: "openai", audience: "student_dm" },
    });
    assert.equal(d.action, c.expect, `${c.label}: expected ${c.expect}, got ${d.action} — ${explainDecision(d)}`);
    assert.ok(d.reasons.length > 0);
  }
});

test("one CRITICAL category far above its bar DOES block alone", { skip: SKIP }, () => {
  const cases = [
    { label: "sexual/minors 0.96", categories: { "sexual/minors": 0.96 }, cat: "sexual_minors" },
    { label: "self-harm 0.97", categories: { "self-harm": 0.97 }, cat: "self_harm" },
    { label: "graphic violence 0.99", categories: { "violence/graphic": 0.99 }, cat: "graphic_violence" },
    { label: "hate 0.97", categories: { hate: 0.97 }, cat: "hate" },
  ];
  for (const c of cases) {
    const d = applyPolicy({ categories: c.categories, text: "x", context: { provider: "openai" } });
    assert.equal(d.action, "block", `${c.label}: expected block, got ${d.action}`);
    assert.ok(
      d.matchedRules.some((r) => r === `critical_single:${c.cat}`),
      `${c.label}: blocked without the critical_single rule`,
    );
  }
});

test("two independent signals clear the multi-signal bar and block", { skip: SKIP }, () => {
  const d = applyPolicy({
    categories: { violence: 0.81, "harassment/threatening": 0.74 },
    text: "no context words at all",
    context: { provider: "openai", audience: "student_dm" },
  });
  assert.equal(d.action, "block");
  assert.ok(d.matchedRules.includes("multisignal:block"));
});

// ============================================================
// 7. Fail-closed — must never regress
// ============================================================
test("provider failure / missing provider NEVER approves", { skip: SKIP }, () => {
  const contexts = [
    { provider: "none" },
    { provider: "none", providerError: "OPENAI_API_KEY not configured" },
    { provider: "openai", providerError: "OpenAI API error: 503" },
    { provider: "apilayer_nudity", providerError: "Nudity API unavailable: timeout" },
    { providerError: "" },
  ];
  for (const context of contexts) {
    // Even with catastrophic scores in hand, a failed provider holds.
    const d = applyPolicy({
      categories: { "sexual/minors": 0.99, violence: 0.99 },
      text: "obviously terrible content",
      context,
    });
    assert.equal(d.action, "hold_for_review", `${JSON.stringify(context)} -> ${d.action}`);
    assert.ok(d.matchedRules.includes("fail_closed"));
  }
});

// ============================================================
// 8. Audience overrides
// ============================================================
test("student_support is lower risk than a random student DM", { skip: SKIP }, () => {
  const cats = { harassment: 0.55, violence: 0.45 };
  const support = applyPolicy({
    categories: cats,
    text: "i am worried about what is happening at home",
    context: { provider: "openai", audience: "student_support" },
  });
  const dm = applyPolicy({
    categories: cats,
    text: "i am worried about what is happening at home",
    context: { provider: "openai", audience: "student_dm" },
  });
  assert.equal(support.audience, "student_support");
  assert.equal(dm.audience, "student_dm");
  assert.ok(
    support.audienceScale > dm.audienceScale,
    `student_support scale ${support.audienceScale} must exceed student_dm ${dm.audienceScale}`,
  );
});

test("audience scales the HOLD bar but NEVER the BLOCK bar", { skip: SKIP }, () => {
  for (const audience of Object.keys(DEFAULT_POLICY.audiences)) {
    const t = effectiveThresholds(audience, DEFAULT_POLICY);
    for (const [cat, spec] of Object.entries(DEFAULT_POLICY.categories)) {
      const override = DEFAULT_POLICY.audiences[audience].categoryOverrides[cat];
      const expectedBlock = override?.block ?? spec.block;
      assert.equal(t[cat].block, expectedBlock, `${audience}/${cat}: block bar was scaled`);
      if (spec.uncancellable) {
        assert.equal(t[cat].hold, spec.hold, `${audience}/${cat}: uncancellable hold bar was scaled`);
      }
    }
  }
});

test("self-harm and CSAE holds are identical in every audience", { skip: SKIP }, () => {
  const holds = new Set();
  for (const audience of Object.keys(DEFAULT_POLICY.audiences)) {
    const t = effectiveThresholds(audience, DEFAULT_POLICY);
    holds.add(t.self_harm.hold);
    holds.add(t.sexual_minors.hold);
  }
  assert.equal(holds.size, 2, `expected exactly 2 distinct hold bars (one per category), got ${[...holds]}`);
});

test("class_channel tightens the bullying bar below the general bar", { skip: SKIP }, () => {
  const general = effectiveThresholds("unknown", DEFAULT_POLICY);
  const classCh = effectiveThresholds("class_channel", DEFAULT_POLICY);
  assert.ok(classCh.bullying.hold < general.bullying.hold);
  assert.equal(classCh.bullying.block, general.bullying.block);
});

test("senderRole is the fallback when the conversation type is unknown", { skip: SKIP }, () => {
  assert.equal(resolveAudience({ audience: "unknown" }, DEFAULT_POLICY), "unknown");
  assert.equal(resolveAudience({ senderRole: "teacher" }, DEFAULT_POLICY), "staff");
  assert.equal(resolveAudience({ senderRole: "student" }, DEFAULT_POLICY), "student_teacher");
  assert.equal(resolveAudience({}, DEFAULT_POLICY), "unknown");
});

// ============================================================
// 9. Allowlist behaviour
// ============================================================
test("the allowlist suppresses benign context but cannot mask a block", { skip: SKIP }, () => {
  const benign = applyPolicy({
    categories: { violence: 0.41, harassment: 0.22 },
    text: "I had a fight with my friend about homework, it is so silly",
    context: { provider: "openai", audience: "student_support" },
  });
  assert.equal(benign.action, "approve");
  assert.ok(benign.allowlistMatches.includes("argument_between_peers"));
  assert.ok(
    benign.reasons.some((r) => /approved via allowlist: 'argument_between_peers'/.test(r)),
    `unexplained allowlist approval: ${benign.reasons.join(" | ")}`,
  );

  // Same allowlist trigger, but the violence signal is now block-level: the
  // entry must REFUSE, and the hate signal (which no entry covers) must
  // carry the decision through to a block.
  const masked = applyPolicy({
    categories: { violence: 0.95, hate: 0.7, harassment: 0.4 },
    text: "I had a fight with my friend about homework",
    context: { provider: "openai", audience: "unknown" },
  });
  assert.equal(masked.action, "block");
  assert.ok(
    masked.matchedRules.some((r) => r === "allowlist_refused:violence"),
    `allowlist masked a block-level signal: ${masked.reasons.join(" | ")}`,
  );
  assert.ok(
    masked.reasons.some((r) => /REFUSED for violence/.test(r)),
    `refusal is not explained: ${masked.reasons.join(" | ")}`,
  );
});

test("hard-term veto stops the allowlist", { skip: SKIP }, () => {
  const d = applyPolicy({
    categories: { violence: 0.8, harassment: 0.7 },
    text: "I had a fight with my friend about homework and I will beat you up after school",
    context: { provider: "openai", audience: "student_dm" },
  });
  assert.deepEqual([...d.allowlistMatches], [], `veto failed: ${d.allowlistMatches.join(", ")}`);
  assert.equal(d.action, "block");
});

test("personal-safety cues veto the argument and sports allowlists", { skip: SKIP }, () => {
  // The dangerous false negative: a disclosure framed inside everyday
  // vocabulary must never be allowlisted away.
  for (const text of [
    "he keeps following me home after school and I am scared",
    "he hits me every day during practice and I am afraid",
    "I had a fight with my friend about homework but now he keeps following me and I am scared",
  ]) {
    for (const categories of [{ harassment: 0.68 }, { violence: 0.72 }, { harassment: 0.7, violence: 0.6 }]) {
      const d = applyPolicy({
        categories,
        text,
        context: { provider: "openai", audience: "student_support" },
      });
      assert.notEqual(d.action, "approve", `disclosure allowlisted away: "${text}" -> ${explainDecision(d)}`);
    }
  }
});

test("emoji-only and empty text are approved with no lexical signal", { skip: SKIP }, () => {
  for (const text of ["😂😂😂🙏👍", "😡😡", "", "   ", "12345"]) {
    const d = applyPolicy({ categories: {}, text, context: { provider: "openai" } });
    assert.equal(d.action, "approve", `"${text}" -> ${d.action}`);
    assert.ok(d.matchedRules.includes("rule:no_lexical_content"));
  }
});

test("allowlist matching is word-boundary and case-insensitive", { skip: SKIP }, () => {
  const on = matchAllowlist("I HAD A FIGHT WITH MY FRIEND ABOUT HOMEWORK", true, DEFAULT_POLICY);
  assert.ok(on.some((m) => m.id === "argument_between_peers"));
  // "fought" must not match "foughton" — a substring hit is not enough.
  assert.equal(matchAllowlist("foughton kid", true, DEFAULT_POLICY).length, 0);
  assert.equal(normaliseText("Hi\u200B 👋"), "hi");
});

// ============================================================
// 10. Image path — nudity is a direct observation
// ============================================================
test("image nudity bands map to reject / quarantine / approve", { skip: SKIP }, () => {
  const bands = [
    { nudity: 5, verdict: "rejected" },
    { nudity: 4, verdict: "rejected" },
    { nudity: 3, verdict: "quarantined" },
    { nudity: 2, verdict: "approved" },
    { nudity: 1, verdict: "approved" },
  ];
  for (const b of bands) {
    const d = applyPolicy({
      categories: {},
      text: "",
      context: { media: "image", provider: "openai_omni", nudityScore: b.nudity },
    });
    assert.equal(toImageVerdict(d), b.verdict, `nudity ${b.nudity} -> ${toImageVerdict(d)}`);
    assert.ok(d.reasons.length > 0, `nudity ${b.nudity}: no reason`);
  }
});

test("an image with a failed provider is quarantined, never approved", { skip: SKIP }, () => {
  const d = applyPolicy({
    categories: {},
    text: "",
    context: { media: "image", provider: "none", nudityScore: 1 },
  });
  assert.equal(toImageVerdict(d), "quarantined");
});

test("the allowlist never applies to images (an image has no text)", { skip: SKIP }, () => {
  const d = applyPolicy({
    categories: { violence: 0.2 },
    text: "",
    context: { media: "image", provider: "openai_omni", nudityScore: 1 },
  });
  assert.deepEqual([...d.allowlistMatches], []);
});

// ============================================================
// 11. Verdict mapping
// ============================================================
test("policy actions map onto the moderation_verdict enum", { skip: SKIP }, () => {
  const mapping = [
    { categories: {}, text: "hello", context: { provider: "openai" }, verdict: "approved" },
    { categories: { violence: 0.81, harassment: 0.74 }, text: "zz", context: { provider: "openai" }, verdict: "blocked" },
    { categories: { harassment: 0.87 }, text: "zz", context: { provider: "openai" }, verdict: "held" },
    {
      categories: { "sexual/minors": 0.96 },
      text: "zz",
      context: { provider: "openai" },
      verdict: "escalated",
    },
    {
      categories: { "self-harm": 0.74, "self-harm/intent": 0.63 },
      text: "zz",
      context: { provider: "openai", audience: "student_support" },
      verdict: "escalated",
    },
  ];
  for (const m of mapping) {
    const d = applyPolicy({ categories: m.categories, text: m.text, context: m.context });
    assert.equal(toTextVerdict(d), m.verdict, `${JSON.stringify(m.categories)} -> ${toTextVerdict(d)} (${d.action})`);
  }
  assert.deepEqual(
    ["approved", "warned", "held", "blocked", "escalated"].sort(),
    ["approved", "warned", "held", "blocked", "escalated"].sort(),
  );
});

test("an allowlist-suppressed approval is recorded as 'warned', not silently approved", { skip: SKIP }, () => {
  const d = applyPolicy({
    categories: { violence: 0.5 },
    text: "i killed time playing cricket with my friends all afternoon",
    context: { provider: "openai", audience: "class_channel" },
  });
  assert.equal(d.action, "approve");
  assert.equal(toTextVerdict(d), "warned");
});

// ============================================================
// 12. The policy object is safe to share
// ============================================================
test("DEFAULT_POLICY is frozen and carries a version", { skip: SKIP }, () => {
  assert.ok(Object.isFrozen(DEFAULT_POLICY));
  assert.ok(Object.isFrozen(DEFAULT_POLICY.categories.violence));
  assert.match(DEFAULT_POLICY.version, /^\d+\.\d+\.\d+$/);
  for (const cat of ["sexual_minors", "self_harm", "bullying", "violence"]) {
    assert.ok(DEFAULT_POLICY.categories[cat], `missing category ${cat}`);
  }
  for (const audience of ["student_support", "class_channel", "student_dm", "staff"]) {
    assert.ok(DEFAULT_POLICY.audiences[audience], `missing audience ${audience}`);
  }
});
