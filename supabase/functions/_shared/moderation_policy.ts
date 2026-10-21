// ============================================================
// TeachCross moderation policy — the single source of truth.
//
// This module owns EVERY decision the platform makes about content:
// what is approved, what a human reviews, what is blocked and what is
// escalated to safeguarding. The edge functions (moderate-message,
// moderate-image) call it; the test suite (tests/moderation_policy.test.mjs)
// exercises it against a labelled dataset. There is deliberately no second
// copy of the thresholds anywhere.
//
// Design rules, in priority order:
//
//   1. FAIL CLOSED. A missing or failed provider never approves anything.
//      Catastrophic scores do not survive a provider failure: the content
//      is held for a human, because we cannot tell what it says.
//
//   2. A SINGLE non-critical signal never blocks. Blocking on one vendor
//      score is how benign school life gets censored ("I had a fight with
//      my friend about homework"). Two independent signals are required.
//
//   3. A CRITICAL signal blocks alone. Child sexual abuse material,
//      self-harm intent, graphic violence and hate speech are not subject
//      to the multi-signal rule.
//
//   4. THE ALLOWLIST is the false-positive defence. Everyday idioms
//      ("kill time", "killed it", "we had a fight during the match") are
//      recognised and downgraded to a warned approval. It can never mask
//      a block-level signal, and a hard-term veto (a real injury, a
//      disclosure) stops it dead.
//
//   5. EVERY decision explains itself. Each hold names the category, the
//      score and the threshold that produced it, so a human reviewer can
//      see why the content reached them.
//
// Node >= 22.6 strips the types natively, so this file is imported
// directly by the test suite as well as by the edge functions.
// ============================================================

// ── Types ────────────────────────────────────────────────────────

export type PolicyAction = "approve" | "hold_for_review" | "block";

export type TextVerdict = "approved" | "warned" | "held" | "blocked" | "escalated";

export type ImageVerdict =
  | "approved"
  | "quarantined"
  | "rejected"
  | "held"
  | "blocked"
  | "escalated";

export type MediaKind = "text" | "image";

export interface CategorySpec {
  /** Score at or above which the content is held for a human. */
  hold: number;
  /** Score at or above which the content is blocked. */
  block: number;
  /** Critical categories block on their own, above their block bar. */
  critical?: boolean;
  /** The hold bar is never scaled by the audience (self-harm, CSAE). */
  uncancellable?: boolean;
}

export interface AudienceSpec {
  /** Multiplier applied to every scalable hold bar. */
  holdScale: number;
  /** Explicit per-category overrides for this audience. */
  categoryOverrides?: Record<string, Partial<CategorySpec>>;
}

export interface AllowlistEntry {
  id: string;
  /** Word-boundary patterns, matched case-insensitively. */
  patterns: RegExp[];
  /** Hard terms that veto the entry outright. */
  vetoTerms: RegExp[];
  /**
   * The policy categories this entry may suppress. An entry never touches a
   * category it does not understand — that is how a suppressed argument
   * could otherwise hide a hate-speech signal.
   */
  categories: string[];
  /** Why the entry exists — for the audit trail. */
  note: string;
}

export interface Policy {
  version: string;
  categories: Record<string, CategorySpec>;
  audiences: Record<string, AudienceSpec>;
  multiSignal: {
    minCategoriesToBlock: number;
    aggregateBlockScore: number;
  };
  allowlist: AllowlistEntry[];
  /** Cues that mean "a child is telling us something is wrong". */
  disclosureCues: RegExp[];
  /** Cues that must never be waved away by the allowlist. */
  hardVetoTerms: RegExp[];
  /** Cues that mark a clinical/safeguarding register entry. */
  registerCues: RegExp[];
  /** Audiences that may post a clinical register entry. */
  registerAudiences: string[];
}

export interface PolicyContext {
  media?: MediaKind;
  audience?: string;
  senderRole?: string;
  provider?: string;
  providerError?: string | null;
  /** 1..5 nudity observation for images. */
  nudityScore?: number | null;
}

export interface PolicyInput {
  categories?: Record<string, unknown>;
  text?: string;
  context?: PolicyContext;
}

export interface Signal {
  category: string;
  score: number;
  hold: number;
  block: number;
  /** The allowlist entry that suppressed this signal, if any. */
  suppressedBy: string | null;
}

export interface Decision {
  action: PolicyAction;
  audience: string;
  audienceScale: number;
  escalate: boolean;
  score: number;
  reasons: string[];
  matchedRules: string[];
  allowlistMatches: string[];
  signals: Signal[];
  warnings: string[];
}

// ── The shipped policy ────────────────────────────────────────────

/**
 * Vendor category key -> policy category.
 *
 * The vendor (OpenAI omni-moderation) emits keys like "sexual/minors",
 * "self-harm" and "harassment/threatening". They are folded onto the
 * policy's own categories here, so the thresholds are written once and
 * never depend on a vendor's naming.
 */
export const VENDOR_CATEGORY_MAP: Record<string, string> = {
  hate: "hate",
  "hate/threatening": "hate",
  sexual: "sexual",
  "sexual/minors": "sexual_minors",
  harassment: "bullying",
  "harassment/threatening": "bullying",
  violence: "violence",
  "violence/graphic": "graphic_violence",
  "self-harm": "self_harm",
  "self-harm/intent": "self_harm",
  "self-harm/instructions": "self_harm",
  illicit: "illicit",
  "illicit/violent": "illicit",
};

/** A plain, safe image. */
const IMAGE_APPROVE = 2;
/** Borderline: a human looks at it. */
const IMAGE_HOLD = 3;
/** Explicit: it never reaches a student. */
const IMAGE_BLOCK = 4;

const CATEGORIES: Record<string, CategorySpec> = {
  sexual_minors: { hold: 0.1, block: 0.85, critical: true, uncancellable: true },
  self_harm: { hold: 0.7, block: 0.9, critical: true, uncancellable: true },
  graphic_violence: { hold: 0.56, block: 0.9, critical: true },
  hate: { hold: 0.55, block: 0.85, critical: true },
  bullying: { hold: 0.6, block: 0.93 },
  violence: { hold: 0.6, block: 0.85 },
  sexual: { hold: 0.7, block: 0.9 },
  illicit: { hold: 0.6, block: 0.9 },
};

const AUDIENCES: Record<string, AudienceSpec> = {
  // A support thread is a lower-risk channel: a young person asking for
  // help must not be flagged for the words they use.
  student_support: { holdScale: 1.35, categoryOverrides: {} },
  // A class channel is the most public surface: bullying there reaches
  // everyone, so the bar is the tightest.
  class_channel: {
    holdScale: 0.8,
    categoryOverrides: { bullying: { hold: 0.42 } },
  },
  // A one-to-one DM has no audience buffer at all.
  student_dm: { holdScale: 0.85, categoryOverrides: {} },
  // Staff and leadership are professionals writing a clinical record.
  staff: { holdScale: 1.5, categoryOverrides: {} },
  leadership: { holdScale: 1.5, categoryOverrides: {} },
  student_teacher: { holdScale: 1.05, categoryOverrides: {} },
  unknown: { holdScale: 1.0, categoryOverrides: {} },
};

const ALLOWLIST: AllowlistEntry[] = [
  {
    id: "argument_between_peers",
    note: "A disagreement between students, not an assault.",
    categories: ["violence", "bullying"],
    patterns: [
      /\bfight\b/,
      /\bfought\b/,
      /\bargu(?:e|ed|ing|ment)\b/,
      /\bquarrel(?:ed|ing)?\b/,
    ],
    vetoTerms: [
      /\bbeat (?:you|him|her|them) up\b/,
      /\bbreak (?:your|his|her|their) (?:legs|arm|arms)\b/,
      /\bsmash (?:his|her|their) head\b/,
      /\bhurt (?:you|him|her|them)\b/,
    ],
  },
  {
    id: "sports_contact",
    note: "Contact sport and a knock, not violence.",
    categories: ["violence", "graphic_violence", "bullying"],
    patterns: [
      /\bduring the (?:match|game|fixture|practice|training)\b/,
      /\b(?:knee|head|elbow|ankle|shin) (?:hit|injury|strike)\b/,
      /\b(?:bruis(?:ed|ing)|sprain|twist|strain)\b/,
      /\b(?:football|cricket|kabaddi|handball|hockey|volleyball|athletics) (?:match|practice|final|tournament)\b/,
    ],
    vetoTerms: [
      /\bhospital\b/,
      /\bambulance\b/,
      /\badmitted\b/,
      /\bpolice\b/,
    ],
  },
  {
    id: "kill_time",
    note: "The idiom, not a statement of intent.",
    categories: ["violence", "self_harm"],
    patterns: [/\bkill(?:ed|ing)? time\b/],
    vetoTerms: [/\bkill(?:ing)? (?:myself|yourself|himself|herself|themselves)\b/],
  },
  {
    id: "killed_it",
    note: "Did well, not a killing.",
    categories: ["violence"],
    patterns: [/\bkilled it\b/],
    vetoTerms: [/\bkill(?:ing)? (?:myself|yourself|himself|herself|themselves)\b/],
  },
  {
    id: "killing_me",
    note: "The idiom, not a statement of distress.",
    categories: ["self_harm", "violence"],
    patterns: [/\b(?:killing|kill) me\b/],
    vetoTerms: [/\bkill(?:ing)? (?:myself|yourself|himself|herself|themselves)\b/],
  },
  {
    id: "competition_result",
    note: "Winning a match.",
    categories: ["violence", "bullying"],
    patterns: [/\bwe (?:won|lost|drew)\b/],
    vetoTerms: [],
  },
];

/**
 * Cues that a child is describing harm happening to them. They are never
 * allowlisted away and they always reach a human.
 */
const DISCLOSURE_CUES: RegExp[] = [
  /\bkeeps? following me\b/,
  /\bfollows? me (?:home|to school|everywhere)\b/,
  /\bhits? me\b/,
  /\bhitting me\b/,
  /\bbeats? me\b/,
  /\bbeating me\b/,
  /\bpunish(?:es|ing)? me (?:every|when)\b/,
  /\bnot safe (?:at|to come)\b/,
  /\bplease tell (?:someone|somebody|an adult)\b/,
];

/**
 * Hard terms. Their presence means the content is not everyday school
 * life, whatever else it looks like.
 */
const HARD_VETO_TERMS: RegExp[] = [
  /\bhospital\b/,
  /\bambulance\b/,
  /\badmitted\b/,
  /\bpolice\b/,
  /\bkill(?:ing)? (?:myself|yourself|himself|herself|themselves)\b/,
  /\bbeat (?:you|him|her|them) up\b/,
  /\bbreak (?:your|his|her|their) (?:legs|arm|arms)\b/,
  /\bsmash (?:his|her|their) head\b/,
  /\bkill yourself\b/,
];

/**
 * Clinical / safeguarding register wording. A member of staff filing a
 * safeguarding note is doing their job, and the content must not be
 * turned into a safeguarding alarm.
 */
const REGISTER_CUES: RegExp[] = [
  /\bdisclosure\b/,
  /\bsafeguarding\b/,
  /\bchild protection\b/,
  /\bwellbeing thread\b/,
  /\bpolicy (?:reference|document|pdf)\b/,
  /\bboundaries module\b/,
];

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value as Record<string, unknown>)) {
      deepFreeze((value as Record<string, unknown>)[key]);
    }
  }
  return value;
}

export const DEFAULT_POLICY: Policy = deepFreeze({
  version: "1.0.0",
  categories: CATEGORIES,
  audiences: AUDIENCES,
  multiSignal: {
    minCategoriesToBlock: 2,
    aggregateBlockScore: 0.62,
  },
  allowlist: ALLOWLIST,
  disclosureCues: DISCLOSURE_CUES,
  hardVetoTerms: HARD_VETO_TERMS,
  registerCues: REGISTER_CUES,
  registerAudiences: ["staff", "leadership"],
}) as Policy;

// ── Text helpers ──────────────────────────────────────────────────

/**
 * Lower-cases, drops zero-width characters and non-word symbols (emoji
 * included), and collapses whitespace. Used for allowlist matching so a
 * zero-width joiner or an emoji can never hide a phrase.
 */
export function normaliseText(text: string): string {
  return (text ?? "")
    .toLowerCase()
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/[^\p{L}\p{N}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** True when the text carries no readable words at all. */
function hasLexicalContent(normalised: string): boolean {
  return /\p{L}/u.test(normalised);
}

// ── Audience ──────────────────────────────────────────────────────

/**
 * Resolves the audience tier a decision is made for.
 *
 * The conversation type is NOT an audience: "student_teacher" is a channel
 * shape, not a role. When the type is unknown the sender's role decides.
 */
export function resolveAudience(context: PolicyContext, policy: Policy = DEFAULT_POLICY): string {
  const audience = context?.audience;
  if (audience && Object.prototype.hasOwnProperty.call(policy.audiences, audience)) {
    return audience;
  }
  const role = (context?.senderRole ?? "").toLowerCase();
  if (role === "student") return "student_teacher";
  if (["teacher", "head_teacher", "principal", "admin", "school_admin"].includes(role)) {
    return "staff";
  }
  return "unknown";
}

/**
 * The effective thresholds for an audience.
 *
 * The HOLD bar is scaled by the audience (a support thread is calmer than
 * a DM). The BLOCK bar is never scaled — the bar for actually stopping
 * content does not move because of who is reading. The hold bars of the
 * uncancellable categories (self-harm, CSAE) never move either.
 */
export function effectiveThresholds(
  audience: string,
  policy: Policy = DEFAULT_POLICY,
): Record<string, CategorySpec & { hold: number; block: number }> {
  const spec = policy.audiences[audience] ?? policy.audiences.unknown;
  const scale = spec?.holdScale ?? 1;
  const out: Record<string, CategorySpec & { hold: number; block: number }> = {};

  for (const [name, cat] of Object.entries(policy.categories)) {
    const override = spec?.categoryOverrides?.[name] ?? {};
    const hold = override.hold ?? (cat.uncancellable ? cat.hold : cat.hold * scale);
    const block = override.block ?? cat.block;
    out[name] = {
      ...cat,
      hold: Math.min(0.995, Math.max(0.001, hold)),
      block,
    };
  }
  return out;
}

// ── Allowlist ─────────────────────────────────────────────────────

/**
 * The allowlist entries that match the text.
 *
 * Matching is word-boundary and case-insensitive, so "foughton" is not a
 * "fight". Images never match — an image has no text to read.
 */
export function matchAllowlist(
  text: string,
  isText: boolean,
  policy: Policy = DEFAULT_POLICY,
): AllowlistEntry[] {
  if (!isText) return [];
  const normalised = normaliseText(text ?? "");
  if (!normalised) return [];

  const matches: AllowlistEntry[] = [];
  for (const entry of policy.allowlist) {
    if (entry.patterns.some((p) => p.test(normalised))) {
      matches.push(entry);
    }
  }
  return matches;
}

/** The first hard-veto term present in the text, if any. */
function findVeto(text: string, policy: Policy): string | null {
  const normalised = normaliseText(text ?? "");
  for (const term of policy.hardVetoTerms) {
    if (term.test(normalised)) return term.source;
  }
  return null;
}

/** The first disclosure cue present in the text, if any. */
function findDisclosureCue(text: string, policy: Policy): string | null {
  const normalised = normaliseText(text ?? "");
  for (const cue of policy.disclosureCues) {
    if (cue.test(normalised)) return cue.source;
  }
  return null;
}

/** True when the text reads like a clinical or safeguarding register entry. */
function isRegisterEntry(text: string, audience: string, policy: Policy): boolean {
  if (!policy.registerAudiences.includes(audience)) return false;
  const normalised = normaliseText(text ?? "");
  return policy.registerCues.some((cue) => cue.test(normalised));
}

// ── Signals ────────────────────────────────────────────────────────

/**
 * Folds the vendor's category vector onto the policy's categories and
 * applies the audience thresholds.
 */
function collectSignals(
  categories: Record<string, unknown> | undefined,
  thresholds: Record<string, CategorySpec & { hold: number; block: number }>,
): Signal[] {
  const best = new Map<string, number>();
  for (const [vendorKey, rawScore] of Object.entries(categories ?? {})) {
    const score = Number(rawScore);
    if (!Number.isFinite(score) || score <= 0) continue;
    const name = VENDOR_CATEGORY_MAP[vendorKey] ?? vendorKey;
    if (!thresholds[name]) continue;
    best.set(name, Math.max(best.get(name) ?? 0, score));
  }

  const signals: Signal[] = [];
  for (const [category, score] of best) {
    const t = thresholds[category];
    signals.push({
      category,
      score,
      hold: t.hold,
      block: t.block,
      suppressedBy: null,
    });
  }
  signals.sort((a, b) => b.score - a.score);
  return signals;
}

// ── The decision ───────────────────────────────────────────────────

/**
 * Applies the policy to one piece of content.
 *
 * The decision is explained in full: every hold names the category, the
 * score and the threshold that produced it.
 */
export function applyPolicy(
  input: PolicyInput,
  policy: Policy = DEFAULT_POLICY,
): Decision {
  const context = input?.context ?? {};
  const media: MediaKind = context.media === "image" ? "image" : "text";
  const text = input?.text ?? "";
  const audience = resolveAudience(context, policy);
  const audienceSpec = policy.audiences[audience] ?? policy.audiences.unknown;
  const audienceScale = audienceSpec?.holdScale ?? 1;
  const thresholds = effectiveThresholds(audience, policy);

  const reasons: string[] = [];
  const matchedRules: string[] = [];
  const allowlistMatches: string[] = [];
  const warnings: string[] = [];
  let escalate = false;

  const base = {
    action: "approve" as PolicyAction,
    audience,
    audienceScale,
    escalate,
    score: 0,
    reasons,
    matchedRules,
    allowlistMatches,
    signals: [] as Signal[],
    warnings,
  };

  // ── Fail closed ────────────────────────────────────────────────
  const provider = context.provider ?? "none";
  const providerFailed =
    !provider ||
    provider === "none" ||
    context.providerError !== undefined &&
      context.providerError !== null;
  if (providerFailed) {
    reasons.push(
      `provider unavailable${context.providerError ? `: ${context.providerError}` : ""} — content held for a human`,
    );
    matchedRules.push("fail_closed");
    return { ...base, action: "hold_for_review", escalate: false };
  }

  // ── Images: the nudity observation is the decision ─────────────
  if (media === "image") {
    const nudity = Number(context.nudityScore);
    const signals: Signal[] = [];
    if (!Number.isFinite(nudity) || nudity <= 0) {
      reasons.push("no nudity observation — image quarantined for review");
      matchedRules.push("image:no_observation");
      return { ...base, action: "hold_for_review" };
    }
    signals.push({
      category: "nudity",
      score: nudity,
      hold: IMAGE_HOLD,
      block: IMAGE_BLOCK,
      suppressedBy: null,
    });
    if (nudity >= IMAGE_BLOCK) {
      reasons.push(
        `blocked: category=nudity score=${nudity} threshold=${IMAGE_BLOCK} (explicit content)`,
      );
      matchedRules.push("image:nudity_block");
      return { ...base, action: "block", score: nudity, signals };
    }
    if (nudity >= IMAGE_HOLD) {
      reasons.push(
        `held: category=nudity score=${nudity} threshold=${IMAGE_HOLD} (borderline content)`,
      );
      matchedRules.push("image:nudity_hold");
      return { ...base, action: "hold_for_review", score: nudity, signals };
    }
    reasons.push(`image nudity=${nudity} below the review threshold ${IMAGE_HOLD}`);
    matchedRules.push("image:approved");
    return { ...base, action: "approve", score: nudity, signals };
  }

  // ── Text ───────────────────────────────────────────────────────
  const normalised = normaliseText(text);

  if (!hasLexicalContent(normalised)) {
    reasons.push("no lexical content to assess");
    matchedRules.push("rule:no_lexical_content");
    return { ...base, action: "approve" };
  }

  const signals = collectSignals(input?.categories, thresholds);
  const top = signals[0]?.score ?? 0;

  // The allowlist: everyday idioms are recognised, unless a hard term
  // says otherwise.
  const veto = findVeto(text, policy);
  const disclosureCue = findDisclosureCue(text, policy);
  const registerEntry = isRegisterEntry(text, audience, policy);

  const candidates = matchAllowlist(text, true, policy);
  const allowlistApplies = candidates.length > 0 && !veto && !disclosureCue;

  /** The categories the matched entries are allowed to suppress. */
  const suppressible = new Set<string>();
  for (const entry of candidates) {
    for (const category of entry.categories) suppressible.add(category);
  }

  if (registerEntry) {
    // A member of staff filing a safeguarding note. The self-harm signal
    // is suppressed; anything else still counts.
    for (const signal of signals) {
      if (signal.category === "self_harm") {
        signal.suppressedBy = "clinical_register";
      }
    }
    reasons.push("clinical register entry — self-harm signal suppressed");
    matchedRules.push("rule:clinical_register");
  }

  if (candidates.length > 0 && veto) {
    // The allowlist wanted to approve this, but a hard term says no.
    reasons.push(`allowlist REFUSED for ${veto} — content needs a human`);
    for (const signal of signals) {
      if (signal.score >= signal.block && signal.suppressedBy === null) {
        matchedRules.push(`allowlist_refused:${signal.category}`);
        reasons.push(`allowlist REFUSED for ${signal.category}`);
      }
    }
  } else if (allowlistApplies) {
    for (const signal of signals) {
      // The allowlist may not mask a block-level signal.
      if (signal.score >= signal.block) {
        matchedRules.push(`allowlist_refused:${signal.category}`);
        reasons.push(`allowlist REFUSED for ${signal.category}`);
        continue;
      }
      // Nor may it touch a category it does not understand.
      if (!suppressible.has(signal.category)) continue;
      if (signal.suppressedBy === null) {
        signal.suppressedBy = candidates[0].id;
      }
    }
    allowlistMatches.push(...candidates.map((entry) => entry.id));
    for (const entry of candidates) {
      reasons.push(`approved via allowlist: '${entry.id}'`);
    }
    matchedRules.push("allowlist_approve");
  }

  // ── Escalate ───────────────────────────────────────────────────
  for (const signal of signals) {
    if (signal.suppressedBy !== null) continue;
    if (signal.category === "sexual_minors" && signal.score >= signal.hold) {
      escalate = true;
    }
    if (signal.category === "self_harm" && signal.score >= signal.hold) {
      escalate = true;
    }
  }
  if (/\bkill(?:ing)? (?:myself|yourself|himself|herself|themselves)\b/.test(normalised)) {
    escalate = true;
  }

  // ── Evaluate ───────────────────────────────────────────────────
  const live = signals.filter((s) => s.suppressedBy === null);
  const elevated = live.filter((s) => s.score >= s.hold);
  const criticalBlocks = live.filter(
    (s) => s.score >= s.block && policy.categories[s.category]?.critical,
  );
  const blockLevel = live.filter((s) => s.score >= s.block);

  // A single critical signal blocks on its own.
  if (criticalBlocks.length > 0) {
    const signal = criticalBlocks[0];
    reasons.push(
      `blocked: category=${signal.category} score=${signal.score.toFixed(3)} threshold=${signal.block} (critical signal)`,
    );
    matchedRules.push(`critical_single:${signal.category}`);
    return {
      ...base,
      action: "block",
      escalate,
      score: top,
      reasons,
      matchedRules,
      allowlistMatches,
      signals,
      warnings,
    };
  }

  // The multi-signal rule: two independent signals, and a strong aggregate.
  if (elevated.length >= policy.multiSignal.minCategoriesToBlock) {
    const aggregate =
      elevated.reduce((sum, s) => sum + s.score, 0) / elevated.length;
    if (aggregate >= policy.multiSignal.aggregateBlockScore) {
      const listed = elevated
        .map((s) => `${s.category}=${s.score.toFixed(3)}/${s.hold.toFixed(3)}`)
        .join(", ");
      reasons.push(
        `blocked: ${elevated.length} independent signals (${listed}) aggregate=${aggregate.toFixed(3)} threshold=${policy.multiSignal.aggregateBlockScore}`,
      );
      matchedRules.push("multisignal:block");
      return {
        ...base,
        action: "block",
        escalate,
        score: top,
        reasons,
        matchedRules,
        allowlistMatches,
        signals,
        warnings,
      };
    }
  }

  // A single elevated signal reaches a human.
  if (elevated.length === 1) {
    const signal = elevated[0];
    reasons.push(
      `held: category=${signal.category} score=${signal.score.toFixed(3)} threshold=${signal.hold.toFixed(3)} (single signal, a human decides)`,
    );
    matchedRules.push("rule:hold_single_signal");
    matchedRules.push(`signal:${signal.category}`);
    return {
      ...base,
      action: "hold_for_review",
      escalate,
      score: top,
      reasons,
      matchedRules,
      allowlistMatches,
      signals,
      warnings,
    };
  }

  // Two or more elevated signals whose aggregate did not clear the bar.
  // They still reach a human: the policy is not confident enough to let
  // them through, and it is not confident enough to block them.
  if (elevated.length >= 2) {
    const signal = elevated[0];
    const aggregate = elevated.reduce((sum, s) => sum + s.score, 0) / elevated.length;
    reasons.push(
      `held: category=${signal.category} score=${signal.score.toFixed(3)} threshold=${signal.hold.toFixed(3)} (${elevated.length} signals, aggregate=${aggregate.toFixed(3)} below the block bar ${policy.multiSignal.aggregateBlockScore})`,
    );
    matchedRules.push("rule:hold_multi_signal");
    matchedRules.push(`signal:${signal.category}`);
    return {
      ...base,
      action: "hold_for_review",
      escalate,
      score: top,
      reasons,
      matchedRules,
      allowlistMatches,
      signals,
      warnings,
    };
  }

  // A disclosure never gets waved away.
  if (disclosureCue) {
    const signal = live[0];
    reasons.push(
      signal
        ? `held: category=${signal.category} score=${signal.score.toFixed(3)} threshold=${signal.hold.toFixed(3)} (disclosure cue: ${disclosureCue} — a young person is describing harm)`
        : `held: disclosure cue (${disclosureCue}) — a young person is describing harm`,
    );
    matchedRules.push("rule:disclosure_hold");
    if (signal) matchedRules.push(`signal:${signal.category}`);
    return {
      ...base,
      action: "hold_for_review",
      escalate: true,
      score: top,
      reasons,
      matchedRules,
      allowlistMatches,
      signals,
      warnings,
    };
  }

  // A hard term with nothing else elevated still reaches a human.
  if (veto) {
    const signal = live[0];
    reasons.push(
      signal
        ? `held: category=${signal.category} score=${signal.score.toFixed(3)} threshold=${signal.hold.toFixed(3)} (hard term: ${veto} — content needs a human)`
        : `held: hard term (${veto}) — content needs a human`,
    );
    matchedRules.push("veto:hold");
    if (signal) matchedRules.push(`signal:${signal.category}`);
    return {
      ...base,
      action: "hold_for_review",
      escalate,
      score: top,
      reasons,
      matchedRules,
      allowlistMatches,
      signals,
      warnings,
    };
  }

  // A block-level non-critical signal: still not a single-signal block,
  // but it must not be delivered unremarked.
  if (blockLevel.length > 0) {
    const signal = blockLevel[0];
    reasons.push(
      `held: category=${signal.category} score=${signal.score.toFixed(3)} threshold=${signal.block} (block-level signal, held for a human)`,
    );
    matchedRules.push(`signal:${signal.category}`);
    return {
      ...base,
      action: "hold_for_review",
      escalate,
      score: top,
      reasons,
      matchedRules,
      allowlistMatches,
      signals,
      warnings,
    };
  }

  // Approved. An allowlist approval is recorded as "warned": deliverable,
  // but auditable.
  if (allowlistMatches.length > 0) {
    warnings.push(`approved via allowlist: '${allowlistMatches.join("', '")}'`);
  }
  reasons.push(`approved: no signal above its threshold (top=${top.toFixed(3)})`);
  matchedRules.push("rule:approved");

  return {
    ...base,
    action: "approve",
    escalate,
    score: top,
    reasons,
    matchedRules,
    allowlistMatches,
    signals,
    warnings,
  };
}

// ── Verdict mapping ───────────────────────────────────────────────

/**
 * The `moderation_verdict` enum value for a text decision.
 *
 * The enum is: approved | warned | held | blocked | escalated.
 * An escalation outranks the action, because it is what the reviewer and
 * the safeguarding workflow need to see.
 */
export function toTextVerdict(decision: Decision): TextVerdict {
  if (decision.escalate) return "escalated";
  if (decision.action === "block") return "blocked";
  if (decision.action === "hold_for_review") return "held";
  if (decision.allowlistMatches.length > 0) return "warned";
  return "approved";
}

/**
 * The `attachments.status` enum value for an image decision.
 *
 * The enum is: uploading | pending_scan | approved | quarantined | rejected.
 */
export function toImageVerdict(decision: Decision): ImageVerdict {
  if (decision.action === "block") return "rejected";
  if (decision.action === "hold_for_review") return "quarantined";
  if (decision.escalate) return "quarantined";
  return "approved";
}

/** A one-line, human-readable explanation of a decision. */
export function explainDecision(decision: Decision): string {
  const prefix =
    decision.action === "block"
      ? "blocked"
      : decision.action === "hold_for_review"
        ? "held"
        : "approved";
  const detail = decision.reasons.length > 0
    ? decision.reasons.join("; ")
    : "no reason recorded";
  return `${prefix}: ${detail}`;
}
