// ============================================================
// TeachCross — FIRST-PART moderation policy (the decision authority).
//
// Vendor moderation (OpenAI `omni-moderation` for text,
// `omni-moderation-latest` for images, APILayer nudity as the image
// fallback) is the SIGNAL SOURCE. This module is the DECISION
// AUTHORITY: it folds raw vendor scores onto school-specific risk
// categories, applies per-audience thresholds, an explicit
// benign-context allowlist, and a multi-signal rule that forbids
// blocking on a single category alone (the only exception is a
// critical category far above its own block threshold).
//
// Why it exists: a blanket "maxScore >= 0.8 => block" over-blocks real
// learning conversations — a student asking about a maths formula, a
// photo of a textbook, "I had a fight with my friend about homework",
// a question about periods, Hinglish, emoji. Those false positives
// BLOCK real learning conversations. Measured by
// tests/moderation_policy.test.mjs; method in docs/MODERATION.md.
//
// Hard rules, all enforced here:
//   1. FAIL CLOSED. `context.providerError` or a missing provider can
//      never produce `approve`. It produces `hold_for_review`.
//   2. MULTI-SIGNAL. Blocking needs either one CRITICAL category above a
//      high threshold, or >= 2 independent categories above their
//      audience-adjusted hold thresholds with an aggregate bar cleared.
//   3. EXPLAINS ITSELF. Every decision returns human-readable `reasons`
//      and machine-readable `matchedRules`.
//   4. THE ALLOWLIST CANNOT MASK A BLOCK. A benign-context match only
//      suppresses a signal that is below its own block threshold.
//   5. AUDIENCE SCALES THE HOLD BAR, NEVER THE BLOCK BAR. Staff using
//      clinical language get a higher flagging bar; nobody gets a lower
//      bar for blocking CSAE or self-harm.
//
// Pure module: no Deno.env, no fetch, no DB. Unit-testable in node.
// ============================================================

export type PolicyAction = "approve" | "hold_for_review" | "block";

export type MediaKind = "text" | "image";

export type SenderRole = "student" | "teacher" | "admin_observer" | "unknown";

/**
 * Conversation audiences, mirroring the live `conversation_type` enum
 * (student_teacher | student_support | staff | class_channel |
 * leadership) plus `student_dm` and `unknown`.
 */
export type ConversationAudience =
  | "student_teacher"
  | "student_support"
  | "staff"
  | "class_channel"
  | "leadership"
  | "student_dm"
  | "unknown";

/** School-specific risk categories. Vendor categories fold into these. */
export type PolicyCategory =
  | "sexual_minors"
  | "sexual_adult"
  | "self_harm"
  | "violence"
  | "graphic_violence"
  | "hate"
  | "bullying"
  | "illicit";

export type CategoryThresholds = {
  /** Score at or above which the category counts as an elevated signal. */
  readonly hold: number;
  /** Score at or above which this category alone may block. */
  readonly block: number;
  /** A single critical category may block on its own (rare, high bar). */
  readonly critical: boolean;
  /**
   * Audience context must never raise the bar for this category. Used for
   * self-harm and CSAE, where a supportive thread is exactly where a
   * disclosure is most likely to appear.
   */
  readonly uncancellable: boolean;
};

export type AudienceCategoryOverride = {
  readonly hold?: number;
  readonly block?: number;
};

export type AudienceProfile = {
  readonly label: string;
  /** Multiplies `hold` only (never `block`). 1.0 = no change. */
  readonly thresholdScale: number;
  readonly allowlistEnabled: boolean;
  readonly categoryOverrides: Readonly<Record<string, AudienceCategoryOverride>>;
  /** Any elevated signal in these sets `escalate` on the decision. */
  readonly forceEscalateCategories: readonly PolicyCategory[];
  readonly notes: string;
};

export type AllowlistEntry = {
  readonly id: string;
  /** ANY of these must be present (word-boundary, case-insensitive). */
  readonly terms: readonly string[];
  /** At least ONE of these must also be present. */
  readonly contextTerms: readonly string[];
  /** If ANY of these are present the entry does NOT match. */
  readonly excludes: readonly string[];
  /** Category signals this entry is allowed to suppress. */
  readonly categories: readonly PolicyCategory[];
  readonly note: string;
};

export type ModerationPolicy = {
  readonly version: string;
  readonly categories: Readonly<Record<PolicyCategory, CategoryThresholds>>;
  readonly audiences: Readonly<Record<ConversationAudience, AudienceProfile>>;
  readonly allowlist: readonly AllowlistEntry[];
  readonly multiSignal: {
    /** Independent categories above `hold` needed to block without a critical hit. */
    readonly minCategoriesToBlock: number;
    /** Mean of the elevated scores must clear this to use the multi-signal path. */
    readonly aggregateBlockScore: number;
  };
  readonly imageRules: {
    /** Nudity is a DIRECT observation, not a semantic guess. 1..5 scale. */
    readonly rejectAtNudity: number;
    readonly quarantineAtNudity: number;
  };
  /** Nudity bands -> a sexual_adult score, so images/text share the table. */
  readonly nudityBands: readonly { readonly atLeast: number; readonly score: number }[];
  /** Categories that force `escalate` whenever they are elevated. */
  readonly escalateAlwaysCategories: readonly PolicyCategory[];
  /** Raw vendor keys (and policy-native names) -> policy category. */
  readonly vendorMapping: Readonly<Record<string, PolicyCategory>>;
};

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value as Record<string, unknown>)) deepFreeze(child);
  }
  return value;
}

export const DEFAULT_POLICY: ModerationPolicy = deepFreeze({
  version: "1.0.0",

  // ------------------------------------------------------------
  // Per-category thresholds.
  //
  // `hold`  — flag for a human. Deliberately HIGH relative to raw vendor
  //           scores: OpenAI hands out 0.3-0.6 on benign school text far
  //           more often than a school wants a review queue.
  // `block` — auto-block. Only `critical` categories reach it alone.
  // ------------------------------------------------------------
  categories: {
    // CSAE. Escalation is near-automatic; blocking only when the vendor is
    // very confident. `hold` is low on purpose and is never scaled up.
    sexual_minors: { hold: 0.08, block: 0.55, critical: true, uncancellable: true },
    // Self-harm disclosure. The block bar stays very high so a disclosure
    // is never destroyed before a safeguarding lead sees it; the hold bar
    // gets the message to a human.
    self_harm: { hold: 0.55, block: 0.9, critical: true, uncancellable: true },
    // Adult sexual content — in a school this is also an adult-conduct matter.
    sexual_adult: { hold: 0.62, block: 0.9, critical: true, uncancellable: false },
    hate: { hold: 0.55, block: 0.88, critical: true, uncancellable: false },
    // Graphic gore: a wound photo, a stabbing description.
    graphic_violence: { hold: 0.45, block: 0.8, critical: true, uncancellable: false },
    // Plain violence/threats: a second signal, never enough alone.
    violence: { hold: 0.6, block: 0.92, critical: false, uncancellable: false },
    // Bullying/harassment. The most over-blocked category in a school
    // ("you idiot", "I fought with my friend", "he hits me at home" as a
    // disclosure). Highest hold bar of all categories.
    bullying: { hold: 0.62, block: 0.93, critical: false, uncancellable: false },
    illicit: { hold: 0.7, block: 0.95, critical: false, uncancellable: false },
  },

  // ------------------------------------------------------------
  // Per-audience overrides. `thresholdScale` moves the HOLD bar only.
  // ------------------------------------------------------------
  audiences: {
    student_support: {
      label: "Student support / wellbeing thread",
      thresholdScale: 1.35,
      allowlistEnabled: true,
      // A support thread is lower risk for AMBIGUOUS signals (vocabulary,
      // banter, clinical wording) but HIGHER stakes for DISCLOSURE signals.
      // A student saying "he keeps following me home" in the wellbeing thread
      // is raising a safeguarding matter, not attacking anyone, so the
      // bullying/violence bars go DOWN while everything else lifts.
      categoryOverrides: {
        bullying: { hold: 0.55, block: 0.93 },
        violence: { hold: 0.5, block: 0.92 },
      },
      forceEscalateCategories: ["self_harm", "sexual_minors"],
      notes:
        "Lower-risk audience: general hold bars rise 35% because students use loose vocabulary in a support thread. Exception: bullying and violence bars are LOWERED to 0.55/0.50 because a disclosure in this thread is the single most important thing the moderation layer can catch. Self-harm and CSAE holds are never scaled (uncancellable) and are force-escalated to safeguarding.",
    },
    student_teacher: {
      label: "Student <-> teacher conversation",
      thresholdScale: 1.15,
      allowlistEnabled: true,
      categoryOverrides: {},
      forceEscalateCategories: [],
      notes:
        "1:1 academic thread. Slight lift: a student describing a teacher's tone, or quoting a rude comment, should reach the teacher, not the safeguarding queue.",
    },
    staff: {
      label: "Staff-only conversation",
      thresholdScale: 1.2,
      allowlistEnabled: true,
      categoryOverrides: {},
      forceEscalateCategories: [],
      notes:
        "Staff use clinical, statutory and anatomical vocabulary (safeguarding, self-harm, boundaries). Hold bar lifts 20%. Block bar unchanged.",
    },
    leadership: {
      label: "Leadership conversation",
      thresholdScale: 1.2,
      allowlistEnabled: true,
      categoryOverrides: {},
      forceEscalateCategories: [],
      notes: "As staff — incident reports and policy language are routine here.",
    },
    class_channel: {
      label: "Whole-class broadcast channel",
      thresholdScale: 0.95,
      allowlistEnabled: true,
      categoryOverrides: {
        // Bullying has more reach here: one message is seen by 40 students.
        bullying: { hold: 0.55, block: 0.93 },
      },
      forceEscalateCategories: [],
      notes:
        "Broadcast reach means bullying counts for more: the bullying hold bar drops to 0.55 even though the general hold bar tightens.",
    },
    student_dm: {
      label: "Direct student-to-student DM",
      thresholdScale: 0.85,
      allowlistEnabled: true,
      categoryOverrides: {},
      forceEscalateCategories: [],
      notes:
        "Highest-risk audience: no staff visibility, so adult-supervision assumptions do not hold. Hold bar drops 15%.",
    },
    unknown: {
      label: "Unknown / not supplied",
      thresholdScale: 1.0,
      allowlistEnabled: true,
      categoryOverrides: {},
      forceEscalateCategories: [],
      notes:
        "Neutral default. It can only make the policy LESS strict, so it is never the basis for a block.",
    },
  },

  // ------------------------------------------------------------
  // Benign-context allowlist.
  //
  // Rationale: the vendor sees a word, not a school. These entries encode
  // the contexts in which a flagged word is doing legitimate work in a
  // school. An entry fires when at least one `terms` entry and at least
  // one `contextTerms` entry are present and NO `excludes` entry is; and it
  // can only suppress signals still below their own block threshold.
  // ------------------------------------------------------------
  allowlist: [
    {
      id: "argument_between_peers",
      terms: [
        "fight", "fighting", "fought", "argue", "argued", "arguing", "argument", "arguments",
        "quarrel", "quarrelled", "quarreled", "quarrelling", "quarreling", "bicker", "bickering",
        "row", "rows", "clash", "clashed", "scrap", "tiff", "disagree", "disagreed", "silly",
      ],
      contextTerms: [
        "homework", "friend", "friends", "teacher", "miss", "sir", "maam", "mum", "mom", "dad",
        "bhai", "dost", "paper", "mistake", "match", "game", "football", "cricket", "kabaddi",
        "volleyball", "election", "project", "deadline", "exam", "test", "assignment", "seat",
        "lunch", "group", "lunchbox", "presentation", "stupid", "silly",
      ],
      excludes: [
        "hurt", "kill", "beat", "blood", "bleed", "break your", "make you", "shut up", "die",
        "dead", "hospital", "police", "arrest", "weapon", "gun", "knife", "punch", "slap",
        "kick", "threat", "after school", "find you", "come outside", "settle this",
        "scared", "afraid", "following me", "follows me", "stalking", "hits me", "hit me",
        "hitting me", "touches me", "uncomfortable", "won't leave me",
      ],
      categories: ["violence", "bullying"],
      note:
        "'fight'/'argument' used about homework, marks, a match or a seat is a normal school conversation. Hard violence cues veto the entry, and so do personal-safety cues — an argument framing never explains a report of being followed or hit.",
    },
    {
      id: "kill_time_idiom",
      terms: ["kill", "killing", "killed"],
      contextTerms: [
        "time", "it", "this", "that", "boring", "bored", "revision", "boredom", "waiting",
        "traffic", "presentation", "exam prep", "my turn", "the test", "the holiday", "homework",
      ],
      excludes: [
        "kill myself", "kill yourself", "kill him", "kill her", "kill them", "kill you",
        "killing myself", "killing yourself", "suicide", "end my life", "hang myself", "overdose",
        "self harm", "self-harm", "cut myself", "harm myself",
      ],
      categories: ["violence", "self_harm"],
      note:
        "'kill time', 'this is killing me', 'I killed it in the test' are idioms. Any self-directed or third-party kill phrase vetoes the entry.",
    },
    {
      id: "academic_reference",
      terms: [
        "suicide", "murder", "violence", "weapon", "gun", "gunshot", "blood", "sex", "drugs",
        "drug", "abuse", "torture", "war", "porn", "bomb", "bombing", "attack", "smoking",
        "alcohol", "graphic",
      ],
      contextTerms: [
        "chapter", "chapters", "textbook", "book", "homework", "assignment", "question", "exam",
        "test", "quiz", "project", "worksheet", "notes", "note", "lesson", "syllabus", "vocabulary",
        "essay", "definition", "history", "biology", "chemistry", "physics", "psychology",
        "revision", "class", "activity", "presentation", "poem", "novel", "documentary", "topic",
        "slide", "period 4", "period 5", "film", "movie", "video", "scene", "pshe", "watch",
        "alternative", "scene",
      ],
      excludes: [
        "kill myself", "end my life", "how to do it", "show me how", "send photos", "send pics",
        "give me", "you first", "do it for me", "right now", "tonight", "might do it", "i will",
        "i want to", "im going to", "gonna", "i need to know how", "send me", "teach me",
      ],
      categories: [
        "self_harm", "violence", "graphic_violence", "sexual_adult", "illicit", "hate", "bullying",
      ],
      note:
        "Referencing a violent or sexual topic as syllabus content is normal teaching. Vetoed by first-person intent or solicitation, which is what an actual disclosure or a groom looks like.",
    },
    {
      id: "health_and_medication",
      terms: [
        "period", "periods", "menstruation", "menstrual", "anxiety", "panic attack", "insomnia",
        "depression", "adhd", "autism", "dyslexia", "epilepsy", "diabetes", "insulin", "asthma",
        "migraine", "medicine", "medicines", "tablet", "tablets", "paracetamol", "ibuprofen",
        "antibiotic", "antibiotics", "therapy", "therapist", "counsellor", "counselor",
        "psychiatrist", "symptom", "symptoms", "diagnosis", "prescription", "contraception",
        "condom",         "pregnant", "pregnancy", "pcos", "fever", "ache", "pain", "sick", "grief", "grieving",
        "died", "death", "passed away", "funeral", "bereaved", "loss",
      ],
      contextTerms: [
        "doctor", "dr", "clinic", "hospital", "nurse", "fever", "pain", "painful", "ache",
        "medicine", "tablet", "tablets", "dose", "help", "advice", "symptom", "symptoms", "period",
        "absent", "sick", "ill", "parent", "mom", "mum", "dad", "school", "miss", "maam", "sir",
        "appointment", "prescription", "diagnosis", "pharmacy", "sick leave", "maths", "math",
        "exam", "tell", "tell someone", "can i", "should i", "go to", "talk to", "grandfather",
        "grandmother", "mother", "father", "family", "sorry", "condolences", "focus", "low", "sad",
      ],
      excludes: [
        "suicide", "kill myself", "end my life", "self harm", "self-harm", "overdose",
        "hurt myself", "cut myself", "harm myself",
      ],
      categories: ["self_harm", "illicit"],
      note:
        "Period, contraception, mental-health and medication questions are exactly the messages a school platform must NOT block, and they do raise illicit/self-harm noise (buying tablets, 'I am so anxious I could die'). Deliberately does NOT suppress bullying or violence: a health complaint never explains 'he keeps hitting me'. Vetoed by explicit self-harm intent.",
    },
    {
      id: "sports_contact",
      terms: [
        "fight", "fought", "hit", "hits", "hitting", "blow", "blows", "knee", "knocked", "bruise",
        "bruised", "blood", "crack", "cracked", "tackle", "concussion", "sprain", "stumble", "ankle",
      ],
      contextTerms: [
        "match", "game", "football", "cricket", "hockey", "kabaddi", "kho kho", "karate",
        "volleyball", "basketball", "athletics", "training", "practice", "practise", "coach",
        "tournament", "field", "ball", "turf", "ground", "sports", "friendly", "pitch", "ice",
      ],
      excludes: [
        "kill", "rape", "hospital", "ambulance", "police", "bleeding", "deep cut", "unconscious",
        "explode", "stab", "knife", "throat", "firearm", "shooting",
        "scared", "afraid", "following me", "follows me", "stalking", "hits me", "hit me",
        "hitting me", "touches me", "uncomfortable",
      ],
      categories: ["violence", "graphic_violence", "bullying"],
      note:
        "Contact sport produces 'hit', 'bruised', 'blood' and 'fight' constantly. Vetoed by hard-harm cues that imply a real assault rather than a game.",
    },
    {
      id: "exam_stress",
      terms: [
        "stress", "stressed", "stressing", "anxious", "anxiety", "panic", "panicking",
        "overwhelmed", "burnout", "depressed", "pressure", "cant sleep", "can't sleep", "cannot sleep",
        "nervous", "scared", "not sleeping", "sleepless",
      ],
      contextTerms: [
        "exam", "exams", "test", "tests", "homework", "school", "college", "marks", "result",
        "results", "boards", "assignment", "deadline", "revision", "future", "career", "teacher",
        "sir", "miss", "parents", "grades", "semester", "practical", "portfolio",
      ],
      excludes: [
        "kill myself", "end my life", "hate myself", "worthless", "suicide", "hurt myself",
        "cut myself", "hate my life", "harm myself",
      ],
      categories: ["self_harm", "hate"],
      note:
        "Exam stress is the biggest false-positive source in a school, and it explains exactly two things: a self-directed self-harm signal ('I am so stressed I cannot cope') and self-directed hate ('I hate my life'). It deliberately does NOT suppress bullying — stress explains nothing about 'he keeps following me home'. Vetoed by self-directed harm or self-hatred.",
    },
    {
      id: "friendly_insult",
      terms: ["idiot", "idiots", "stupid", "dumb", "fool", "moron", "loser", "bewakoof", "pagal", "joker", "nerd", "geek", "hangiya"],
      contextTerms: [
        "friend", "friends", "joke", "joking", "jokes", "kidding", "lol", "haha", "hahaha",
        "funny", "mate", "yaar", "goofing", "banter", "rofl", "buddy",
      ],
      excludes: [
        "kill", "die", "dead", "fat", "ugly", "hate you", "shut up", "nobody likes you",
        "worthless", "should die", "every day", "always", "you lot",
      ],
      categories: ["bullying", "hate"],
      note:
        "Peer banter between friends. Vetoed by degrading identity attacks, which are the bullying pattern we actually care about.",
    },
    {
      id: "peer_pressure_disclosure",
      terms: [
        "smoke", "smoking", "smoked", "cigarette", "cigarettes", "vape", "vaping", "joint",
        "booze", "drink", "drinks", "drank", "shisha", "hookah", "gutka", "pan masala",
        "alcohol", "wine", "beer",
      ],
      contextTerms: [
        "friend", "friends", "pressure", "pressured", "peer", "peers", "party", "refuse",
        "refused", "said no", "didnt", "didn t", "did not", "never", "not going to", "convinced",
        "forced", "bacche", "yaar", "pressure de", "samjhaya", "nahi", "kiya nahi",
      ],
      excludes: ["where can i buy", "how to buy", "how do i buy", "where to get", "best place to buy"],
      categories: ["illicit"],
      note:
        "A student refusing, or asking for help about, peer pressure is the system working. Vetoed when the message is actually sourcing the product.",
    },
    {
      id: "staff_case_note",
      terms: [
        "self-harm", "self harm", "selfharm", "disclosure", "safeguarding", "safeguard",
        "wellbeing", "incident", "pastoral", "child protection", "abuse", "referral",
      ],
      contextTerms: [
        "year", "form", "class", "thread", "case", "review", "lead", "policy", "referral", "refer",
        "handover", "head", "pastoral", "mentor", "tutor", "disclosure", "raised", "reported",
        "concern", "update", "student", "pupil", "on my caseload", "on my case", "meet", "file",
        "note", "notes", "log", "record",
      ],
      excludes: [
        "kill myself", "end my life", "i want to", "i am going to", "im going to", "my own",
        "suicidal", "hurt myself", "i feel like", "i keep thinking",
      ],
      categories: ["self_harm", "bullying"],
      note:
        "Staff writing a safeguarding handover in clinical register ('year 9 has a self-harm disclosure in the wellbeing thread') is the system working, not a disclosure. Vetoed by first-person intent.",
    },
  ],

  multiSignal: {
    minCategoriesToBlock: 2,
    aggregateBlockScore: 0.62,
  },

  imageRules: {
    rejectAtNudity: 4,
    quarantineAtNudity: 3,
  },

  nudityBands: [
    { atLeast: 5, score: 0.97 },
    { atLeast: 4, score: 0.88 },
    { atLeast: 3, score: 0.66 },
    { atLeast: 2, score: 0.3 },
    { atLeast: 1, score: 0.05 },
  ],

  escalateAlwaysCategories: ["sexual_minors", "self_harm"],

  // Sub-keys roll UP into their parent (max, not sum — scores are
  // per-category probabilities, summing double-counts).
  vendorMapping: {
    "sexual/minors": "sexual_minors",
    sexual: "sexual_adult",
    "self-harm": "self_harm",
    "self-harm/intent": "self_harm",
    "self-harm/instructions": "self_harm",
    "self-harm/graphic": "self_harm",
    hate: "hate",
    "hate/threatening": "hate",
    harassment: "bullying",
    "harassment/threatening": "bullying",
    violence: "violence",
    "violence/graphic": "graphic_violence",
    illicit: "illicit",
    "illicit/violent": "illicit",
    // Policy-native names, so a future first-party classifier can be fed
    // in without re-mapping. (`hate`, `violence`, `illicit` already map
    // to themselves from the vendor block above.)
    sexual_minors: "sexual_minors",
    sexual_adult: "sexual_adult",
    self_harm: "self_harm",
    graphic_violence: "graphic_violence",
    bullying: "bullying",
  },
});

export const POLICY_CATEGORIES = Object.keys(DEFAULT_POLICY.categories) as PolicyCategory[];

/** Category keys of an arbitrary policy (the threshold sweep reads its own table). */
export function policyCategories(policy: ModerationPolicy): PolicyCategory[] {
  return Object.keys(policy.categories) as PolicyCategory[];
}

// ============================================================
// Input / output contracts
// ============================================================

export type PolicyContext = {
  readonly media?: MediaKind;
  readonly audience?: ConversationAudience;
  readonly senderRole?: SenderRole;
  /** Vendor provider id ("openai", "openai_omni", "apilayer_nudity", "none"). */
  readonly provider?: string;
  /** Any provider failure. A non-empty value alone forces fail-closed. */
  readonly providerError?: string | null;
  /** APILayer / omni nudity observation on the 1..5 scale (images only). */
  readonly nudityScore?: number | null;
  /** Vendor's own hard flag; recorded for the audit trail only. */
  readonly flagged?: boolean;
};

export type PolicyInput = {
  readonly categories: Readonly<Record<string, number>>;
  readonly text: string;
  readonly context?: PolicyContext;
};

export type PolicySignal = {
  readonly category: PolicyCategory;
  readonly score: number;
  /** Vendor keys that contributed to this signal. */
  readonly sources: readonly string[];
  /** Audience-adjusted thresholds actually used. */
  readonly hold: number;
  readonly block: number;
  readonly elevated: boolean;
  /** Cap applied by the allowlist, or null. */
  readonly suppressedBy: number | null;
};

export type PolicyDecision = {
  readonly action: PolicyAction;
  /** 0..1 policy risk score: the aggregate the ladder used. */
  readonly score: number;
  /** Highest raw signal score, whatever the policy decided. */
  readonly rawMaxScore: number;
  readonly reasons: readonly string[];
  readonly matchedRules: readonly string[];
  readonly signals: readonly PolicySignal[];
  /**
   * Set when a safeguarding/conduct escalation should be attached
   * regardless of action (CSAE, self-harm, or a force-escalate
   * audience). Handlers map this to the `escalated` verdict.
   */
  readonly escalate: boolean;
  readonly policyVersion: string;
  readonly audience: ConversationAudience;
  readonly audienceScale: number;
  readonly allowlistMatches: readonly string[];
};

export type AllowlistMatch = {
  readonly id: string;
  readonly matchedTerm: string;
  readonly matchedContext: string;
  readonly categories: readonly PolicyCategory[];
  readonly note: string;
};

// ============================================================
// Text helpers
// ============================================================

const ZERO_WIDTH = /[\u200B-\u200D\u2060\uFEFF]/g;
const EMOJI =
  /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE00}-\u{FE0F}\u{2190}-\u{21FF}\u{2900}-\u{297F}]/gu;
const NON_WORD = /[^\p{L}\p{N}\s'’]/gu;

export function normaliseText(text: string): string {
  return String(text ?? "")
    .toLowerCase()
    .replace(ZERO_WIDTH, "")
    .replace(EMOJI, " ")
    .replace(NON_WORD, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isLetter(ch: string | undefined): boolean {
  return typeof ch === "string" && /\p{L}/u.test(ch);
}

/** Word-boundary-aware substring test on already-normalised text. */
export function containsPhrase(haystack: string, phrase: string): boolean {
  const needle = phrase.trim().toLowerCase();
  if (!needle) return false;
  let from = 0;
  for (;;) {
    const idx = haystack.indexOf(needle, from);
    if (idx < 0) return false;
    const before = idx > 0 ? haystack[idx - 1] : " ";
    const after = idx + needle.length < haystack.length ? haystack[idx + needle.length] : " ";
    if (!isLetter(before) && !isLetter(after)) return true;
    from = idx + 1;
  }
}

function anyPhrase(text: string, phrases: readonly string[]): string | null {
  for (const p of phrases) if (containsPhrase(text, p)) return p;
  return null;
}

function round4(n: number): number {
  return Math.round(n * 10000) / 10000;
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}

function truncate(s: string, max: number): string {
  return s.length <= max ? s : `${s.slice(0, max - 1)}…`;
}

// ============================================================
// Signal collection
// ============================================================

type RawAccumulator = { score: number; sources: string[] };

/** Fold raw vendor scores into policy categories (max per category). */
export function collectSignals(
  categories: Readonly<Record<string, number>> | undefined | null,
  media: MediaKind = "text",
  policy: ModerationPolicy = DEFAULT_POLICY,
): Map<PolicyCategory, RawAccumulator> {
  const out = new Map<PolicyCategory, RawAccumulator>();
  for (const [key, rawValue] of Object.entries(categories ?? {})) {
    const value = typeof rawValue === "number" ? rawValue : Number(rawValue);
    if (!Number.isFinite(value) || value <= 0) continue;
    const mapped = policy.vendorMapping[key];
    if (!mapped) continue;
    // A picture of violence is graphic by nature: fold `violence` upward.
    const target: PolicyCategory = media === "image" && mapped === "violence" ? "graphic_violence" : mapped;
    const prev = out.get(target);
    if (!prev) out.set(target, { score: value, sources: [key] });
    else if (value > prev.score) out.set(target, { score: value, sources: [key] });
    else prev.sources.push(key);
  }
  return out;
}

function nudityToScore(nudityScore: number, policy: ModerationPolicy): number {
  for (const band of policy.nudityBands) {
    if (nudityScore >= band.atLeast) return band.score;
  }
  return 0;
}

// ============================================================
// Thresholds
// ============================================================

export function resolveAudience(
  context: PolicyContext | undefined,
  policy: ModerationPolicy = DEFAULT_POLICY,
): ConversationAudience {
  const explicit = context?.audience;
  if (explicit && explicit in policy.audiences) return explicit;
  // Fall back to the sender's role: staff write in a professional register
  // even where the conversation type is unknown.
  const role = context?.senderRole;
  if (role === "teacher" || role === "admin_observer") return "staff";
  if (role === "student") return "student_teacher";
  return "unknown";
}

export function effectiveThresholds(
  audience: ConversationAudience,
  policy: ModerationPolicy = DEFAULT_POLICY,
): Record<PolicyCategory, { hold: number; block: number }> {
  const profile = policy.audiences[audience] ?? policy.audiences.unknown;
  const out = {} as Record<PolicyCategory, { hold: number; block: number }>;
  for (const cat of policyCategories(policy)) {
    const spec = policy.categories[cat];
    const override = profile.categoryOverrides[cat] ?? {};
    // RULE: audience scales the hold bar only. `block` is never scaled, and
    // uncancellable categories are never scaled at all.
    const hold = override.hold ?? (spec.uncancellable ? spec.hold : spec.hold * profile.thresholdScale);
    out[cat] = {
      hold: clamp(hold, 0.02, 0.9),
      block: clamp(override.block ?? spec.block, 0.05, 0.995),
    };
  }
  return out;
}

// ============================================================
// Allowlist
// ============================================================

export function matchAllowlist(
  text: string,
  enabled: boolean,
  policy: ModerationPolicy = DEFAULT_POLICY,
): AllowlistMatch[] {
  if (!enabled) return [];
  const norm = normaliseText(text);
  if (!norm) return [];
  const matches: AllowlistMatch[] = [];
  for (const entry of policy.allowlist) {
    const term = anyPhrase(norm, entry.terms);
    if (!term) continue;
    const ctx = anyPhrase(norm, entry.contextTerms);
    if (!ctx) continue;
    // A hard-term veto wins over everything else in the entry.
    if (anyPhrase(norm, entry.excludes)) continue;
    matches.push({
      id: entry.id,
      matchedTerm: term,
      matchedContext: ctx,
      categories: entry.categories,
      note: entry.note,
    });
  }
  return matches;
}

// ============================================================
// The decision
// ============================================================

export function applyPolicy(
  input: PolicyInput,
  policy: ModerationPolicy = DEFAULT_POLICY,
): PolicyDecision {
  const context: PolicyContext = input.context ?? {};
  const media: MediaKind = context.media ?? "text";
  const audience = resolveAudience(context, policy);
  const profile = policy.audiences[audience] ?? policy.audiences.unknown;
  const thresholds = effectiveThresholds(audience, policy);
  const categories = policyCategories(policy);

  const reasons: string[] = [];
  const matchedRules: string[] = [];

  const raw = collectSignals(input.categories, media, policy);
  let rawMaxScore = 0;
  for (const acc of raw.values()) rawMaxScore = Math.max(rawMaxScore, acc.score);

  // Nudity is a direct physical observation, injected as a sexual_adult
  // signal so images and text share one threshold table.
  const nudity = typeof context.nudityScore === "number" && Number.isFinite(context.nudityScore)
    ? clamp(context.nudityScore, 1, 5)
    : null;
  if (media === "image" && nudity !== null) {
    const score = nudityToScore(nudity, policy);
    const prev = raw.get("sexual_adult");
    if (!prev || score > prev.score) raw.set("sexual_adult", { score, sources: [`nudity:${nudity}`] });
  }

  const buildSignals = (suppressed: Map<PolicyCategory, number>): PolicySignal[] =>
    categories.map((cat) => {
      const acc = raw.get(cat);
      const t = thresholds[cat];
      const score = acc?.score ?? 0;
      const cap = suppressed.get(cat);
      const effective = cap === undefined ? score : Math.min(score, cap);
      return {
        category: cat,
        score: round4(effective),
        sources: acc?.sources ?? [],
        hold: t.hold,
        block: t.block,
        elevated: effective >= t.hold,
        suppressedBy: cap === undefined ? null : cap,
      };
    });

  const summarise = (list: readonly PolicySignal[]): string =>
    list.map((s) => `${s.category}=${s.score}`).join(", ");

  const finish = (
    action: PolicyAction,
    signals: PolicySignal[],
    matches: readonly AllowlistMatch[],
    score: number,
    escalate: boolean,
  ): PolicyDecision => ({
    action,
    score: round4(clamp(score, 0, 1)),
    rawMaxScore: round4(rawMaxScore),
    reasons,
    matchedRules,
    signals,
    escalate,
    policyVersion: policy.version,
    audience,
    audienceScale: profile.thresholdScale,
    allowlistMatches: matches.map((m) => m.id),
  });

  // ---- RULE 0: FAIL CLOSED -------------------------------------
  // A provider failure, a missing provider, or a provider that returned
  // no usable categories is a hold. Never an approval.
  const providerFailed = typeof context.providerError === "string" && context.providerError.trim() !== "";
  const noProvider = !context.provider || context.provider === "none";
  if (providerFailed || noProvider) {
    reasons.push(
      `held: category=provider score=1 threshold=1 (fail-closed: ${
        providerFailed ? `provider error: ${context.providerError}` : "no moderation provider available"
      })`,
    );
    matchedRules.push("fail_closed");
    return finish("hold_for_review", buildSignals(new Map()), [], 1, false);
  }

  // ---- Non-verbal / empty text (TEXT ONLY) ---------------------
  // An image has no text: this rule must never fire for attachments, or a
  // nude photo with no caption would sail through as "no lexical content".
  const normText = normaliseText(input.text);
  if (media === "text" && !/\p{L}/u.test(normText)) {
    reasons.push(
      normText
        ? "approved: no lexical content (emoji/symbol-only message) — no category can be evidenced"
        : "approved: empty text — attachment-only message, nothing to moderate",
    );
    matchedRules.push("rule:no_lexical_content");
    return finish("approve", buildSignals(new Map()), [], rawMaxScore, false);
  }

  // ---- Allowlist ----------------------------------------------
  const allowlistMatches = matchAllowlist(input.text, profile.allowlistEnabled && media === "text", policy);
  for (const m of allowlistMatches) {
    matchedRules.push(`allowlist:${m.id}`);
    reasons.push(
      `allowlist '${m.id}' matched: term='${m.matchedTerm}' + context='${m.matchedContext}' in "${truncate(normText, 90)}"`,
    );
  }

  const preliminary = buildSignals(new Map());
  const suppressed = new Map<PolicyCategory, number>();
  const covering = new Map<PolicyCategory, string>();

  for (const s of preliminary) {
    const coveringEntry = allowlistMatches.find((m) => m.categories.includes(s.category));
    if (!coveringEntry) continue;
    // RULE 4: an allowlist entry may never mask a signal already at or
    // above its own block threshold.
    if (s.score >= s.block) {
      reasons.push(
        `allowlist '${coveringEntry.id}' REFUSED for ${s.category}: score=${s.score} >= block threshold=${s.block} — benign context cannot mask a block-level signal`,
      );
      matchedRules.push(`allowlist_refused:${s.category}`);
      continue;
    }
    suppressed.set(s.category, 0);
    covering.set(s.category, coveringEntry.id);
  }

  const signals = buildSignals(suppressed);
  const preliminaryElevated = preliminary.filter((s) => s.elevated);
  const elevated = signals.filter((s) => s.elevated);
  for (const s of elevated) matchedRules.push(`signal:${s.category}`);

  const aggregate = elevated.length
    ? elevated.reduce((sum, s) => sum + s.score, 0) / elevated.length
    : rawMaxScore;

  // ---- Approve: everything elevated was allowlisted ------------
  if (preliminaryElevated.length && preliminaryElevated.every((s) => suppressed.has(s.category))) {
    for (const s of preliminaryElevated) {
      reasons.push(
        `approved via allowlist: '${covering.get(s.category)}' — ${s.category} score=${s.score} threshold=${s.hold} suppressed as benign school context`,
      );
    }
    matchedRules.push("allowlist_approve");
    return finish("approve", signals, allowlistMatches, aggregate, false);
  }

  // ---- Approve: nothing elevated -------------------------------
  if (!elevated.length) {
    const active = signals.filter((s) => s.score > 0);
    reasons.push(
      `approved: no category above its hold threshold (signals: ${summarise(active) || "none"}, audience=${audience} scale=${profile.thresholdScale})`,
    );
    if (allowlistMatches.length) {
      // The allowlist did work, or would have: say so explicitly so a
      // reviewer reading the audit trail never has to guess.
      matchedRules.push("allowlist_approve");
      if (suppressed.size > 0) {
        for (const s of preliminary) {
          if (!suppressed.has(s.category)) continue;
          reasons.push(
            `approved via allowlist: '${covering.get(s.category)}' — ${s.category} score=${s.score} threshold=${s.hold} suppressed as benign school context`,
          );
        }
      } else {
        reasons.push(
          `approved via allowlist: ${allowlistMatches.map((m) => `'${m.id}'`).join(", ")} matched, but no category was above its hold threshold for audience=${audience} in the first place`,
        );
      }
    } else {
      matchedRules.push("rule:no_elevated_signal");
    }
    return finish("approve", signals, allowlistMatches, aggregate, false);
  }

  // ---- Escalation flag (independent of the action) ------------
  const escalateCategories = new Set<PolicyCategory>([
    ...policy.escalateAlwaysCategories,
    ...profile.forceEscalateCategories,
  ]);
  const escalateHit = elevated.filter((s) => escalateCategories.has(s.category));
  const escalate = escalateHit.length > 0;
  if (escalate) {
    reasons.push(
      `escalate: ${summarise(escalateHit)} — safeguarding/conduct review required regardless of action`,
    );
    matchedRules.push("rule:escalate_critical");
  }

  // ---- Images: nudity is a direct observation ------------------
  if (media === "image" && nudity !== null) {
    if (nudity >= policy.imageRules.rejectAtNudity) {
      reasons.push(
        `blocked: category=image_nudity score=${nudity} threshold=${policy.imageRules.rejectAtNudity} (direct physical observation, not a semantic guess)`,
      );
      matchedRules.push("image:nudity_reject");
      return finish("block", signals, allowlistMatches, 1, escalate);
    }
    if (nudity >= policy.imageRules.quarantineAtNudity) {
      reasons.push(
        `held: category=image_nudity score=${nudity} threshold=${policy.imageRules.quarantineAtNudity} (direct physical observation, not a semantic guess)`,
      );
      matchedRules.push("image:nudity_quarantine");
      return finish("hold_for_review", signals, allowlistMatches, aggregate, escalate);
    }
  }

  const top = [...elevated].sort((a, b) => b.score - a.score)[0];

  // ---- RULE 2a: one CRITICAL category far above its block bar --
  const criticalHit = elevated.find((s) => policy.categories[s.category].critical && s.score >= s.block);
  if (criticalHit) {
    reasons.push(
      `blocked: category=${criticalHit.category} score=${criticalHit.score} threshold=${criticalHit.block} (critical single-signal rule; sources: ${criticalHit.sources.join("+") || "policy"})`,
    );
    matchedRules.push(`critical_single:${criticalHit.category}`);
    return finish("block", signals, allowlistMatches, 1, escalate);
  }

  // ---- RULE 2b: two or more independent signals -----------------
  if (elevated.length >= policy.multiSignal.minCategoriesToBlock) {
    const bar = policy.multiSignal.aggregateBlockScore;
    if (aggregate >= bar) {
      reasons.push(
        `blocked: multi-signal — ${elevated.length} independent categories (${summarise(elevated)}) aggregate=${round4(aggregate)} >= bar=${bar}`,
      );
      matchedRules.push("multisignal:block");
      return finish("block", signals, allowlistMatches, aggregate, escalate);
    }
    reasons.push(
      `not blocked: multi-signal bar missed — ${summarise(elevated)} aggregate=${round4(aggregate)} < bar=${bar}`,
    );
    matchedRules.push("multisignal:below_bar");
  }

  // ---- Hold: elevated, but not enough to block -----------------
  reasons.push(
    `held: category=${top.category} score=${top.score} threshold=${top.hold} (${elevated.length} elevated signal(s) below the block bar — a single category never blocks)`,
  );
  if (context.flagged) {
    reasons.push(`note: vendor flagged=true at rawMax=${round4(rawMaxScore)}; policy overrode`);
  }
  matchedRules.push("rule:hold_single_signal");
  return finish("hold_for_review", signals, allowlistMatches, aggregate, escalate);
}

// ============================================================
// Verdict mapping for the handlers
// ============================================================

export type TextVerdict = "approved" | "warned" | "held" | "blocked" | "escalated";
export type ImageVerdict = "approved" | "rejected" | "quarantined";

export function toTextVerdict(decision: PolicyDecision): TextVerdict {
  if (decision.escalate && decision.action !== "approve") return "escalated";
  if (decision.action === "block") return "blocked";
  if (decision.action === "hold_for_review") return "held";
  // An approve that arrived with an allowlist-suppressed signal is
  // "warned": still deliverable, visible in the audit trail.
  return decision.signals.some((s) => s.suppressedBy !== null) ? "warned" : "approved";
}

export function toImageVerdict(decision: PolicyDecision): ImageVerdict {
  if (decision.action === "block") return "rejected";
  if (decision.action === "hold_for_review") return "quarantined";
  return "approved";
}

/** One-line human summary for a safeguarding lead / review queue. */
export function explainDecision(decision: PolicyDecision): string {
  const head = decision.action === "approve" ? "approved" : decision.action === "block" ? "blocked" : "held";
  const body = decision.reasons.length ? decision.reasons.join(" | ") : "no signals";
  return `${head}: ${body} [rules: ${decision.matchedRules.join(", ") || "none"}]`;
}
