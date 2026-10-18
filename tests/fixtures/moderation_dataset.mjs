// ============================================================
// TeachCross moderation policy — labelled evaluation dataset.
//
// Each case is:
//   {
//     id, label: 'benign' | 'positive',
//     text, audience?, senderRole?, media?, nudityScore?, edge?: true,
//     categories: <recorded vendor category_scores>,
//     note
//   }
//
// WHAT `categories` IS
// -------------------
// The raw moderation-model score vector for `text`, using the exact
// category keys the live pipeline writes into `moderation_results.categories`
// (verified against the `omni-moderation` response shape stored in the live
// database: hate, sexual, illicit, violence, self-harm, harassment,
// sexual/minors, illicit/violent, hate/threatening, self-harm/intent,
// violence/graphic, harassment/threatening, self-harm/instructions).
//
// The scores are RECORDED, not live: reproducing them requires an
// OPENAI_API_KEY, and a test suite must be deterministic. They are
// authored to sit inside the observed distribution of real scores
// (benign school text sits at 1e-6..0.6 depending on wording, which is
// precisely the false-positive pressure this policy exists to absorb).
//
// The unit under test is the POLICY, not the vendor. What is being
// measured is: "given these signals, does our decision layer flag or
// block benign school content?" Re-recording against a live vendor is
// documented in docs/MODERATION.md § Re-tuning.
//
// Positive-positive metric convention: a case is PREDICTED FLAGGED when the
// policy returns hold_for_review or block. A hold is a correct outcome for a
// positive case (it reaches a human) but is a FALSE POSITIVE for a benign
// case (it interrupts a learning conversation).
// ============================================================

/** Every key the vendor emits. Present on every case so shapes are realistic. */
export const VENDOR_KEYS = [
  "hate",
  "sexual",
  "illicit",
  "violence",
  "self-harm",
  "harassment",
  "sexual/minors",
  "illicit/violent",
  "hate/threatening",
  "self-harm/intent",
  "violence/graphic",
  "harassment/threatening",
  "self-harm/instructions",
];

/** Build a full, realistic vendor vector from the handful of keys that matter. */
export function vendorScores(spec) {
  const out = {};
  for (const key of VENDOR_KEYS) out[key] = 0.000002;
  for (const [key, value] of Object.entries(spec ?? {})) {
    if (!VENDOR_KEYS.includes(key)) throw new Error(`unknown vendor category "${key}"`);
    out[key] = value;
  }
  return out;
}

// ------------------------------------------------------------
// BENIGN — school content that a generic vendor over-blocks or
// that the policy must let through untouched. 40 cases.
// ------------------------------------------------------------
const BENIGN = [
  // --- academic: maths / science / homework ---
  {
    id: "b01",
    label: "benign",
    text: "Sir how do we solve this quadratic equation x2 - 5x + 6 = 0 by factorisation?",
    audience: "student_teacher",
    categories: vendorScores({ harassment: 0.012 }),
    note: "plain maths help",
  },
  {
    id: "b02",
    label: "benign",
    text: "What is the formula for the area of a trapezium? I forgot it again.",
    audience: "student_teacher",
    categories: vendorScores({}),
    note: "geometry question",
  },
  {
    id: "b03",
    label: "benign",
    text: "Can you explain the difference between mitosis and meiosis? The board exam had this.",
    audience: "student_teacher",
    categories: vendorScores({ sexual: 0.021, "self-harm": 0.008 }),
    note: "biology, vendor noise on 'meiosis'",
  },
  {
    id: "b04",
    label: "benign",
    text: "Homework sir: chapter 4 questions 1 to 12, I have attached my answers in the photo.",
    audience: "student_teacher",
    categories: vendorScores({}),
    note: "homework submission",
  },
  {
    id: "b05",
    label: "benign",
    text: "Miss, the smart board in class 9 is not working again, can you tell the IT department?",
    audience: "student_teacher",
    categories: vendorScores({ harassment: 0.014 }),
    note: "facility complaint",
  },

  // --- the classic false positive: 'fight' ---
  {
    id: "b06",
    label: "benign",
    edge: true,
    text: "I had a fight with my friend about homework, it is so silly",
    audience: "student_support",
    categories: vendorScores({ violence: 0.41, harassment: 0.22, "violence/graphic": 0.03 }),
    note: "THE canonical benign 'fight' case",
  },
  {
    id: "b07",
    label: "benign",
    edge: true,
    text: "me and my friend fought over the last seat in the bus lol",
    audience: "student_dm",
    categories: vendorScores({ violence: 0.52, harassment: 0.19 }),
    note: "'fought' + seat, highest-risk audience",
  },
  {
    id: "b08",
    label: "benign",
    edge: true,
    text: "We argued about who has to present the project and now nobody wants to talk",
    audience: "class_channel",
    categories: vendorScores({ harassment: 0.44, violence: 0.28 }),
    note: "'argued' + project",
  },
  {
    id: "b09",
    label: "benign",
    text: "bhai yaar tu bewakoof hai 😂 it was just a joke",
    audience: "student_dm",
    categories: vendorScores({ harassment: 0.47, hate: 0.18 }),
    note: "friendly insult, Hinglish",
  },

  // --- 'kill time' idiom ---
  {
    id: "b10",
    label: "benign",
    edge: true,
    text: "How do I kill time during the long holiday? I finished all my books already",
    audience: "student_support",
    categories: vendorScores({ violence: 0.45, "self-harm": 0.3 }),
    note: "'kill time' idiom with real vendor noise",
  },
  {
    id: "b11",
    label: "benign",
    text: "This assignment is killing me, I have been stuck on it since Monday",
    audience: "student_teacher",
    categories: vendorScores({ "self-harm": 0.26, violence: 0.18 }),
    note: "'killing me' idiom",
  },
  {
    id: "b12",
    label: "benign",
    text: "I killed it in the maths test! 98/100 🎉",
    audience: "class_channel",
    categories: vendorScores({ violence: 0.31 }),
    note: "'killed it' idiom",
  },

  // --- health / period / medical ---
  {
    id: "b13",
    label: "benign",
    edge: true,
    text: "Ma'am I missed my period and I am really scared, what should I do?",
    audience: "student_support",
    categories: vendorScores({ "self-harm": 0.38, harassment: 0.15 }),
    note: "period question — must never be blocked",
  },
  {
    id: "b14",
    label: "benign",
    edge: true,
    text: "I have a fever and stomach ache since morning, may I go to the clinic?",
    audience: "student_teacher",
    categories: vendorScores({ "self-harm/instructions": 0.31, violence: 0.14 }),
    note: "sick leave request",
  },
  {
    id: "b15",
    label: "benign",
    text: "Ma'am can I take my insulin/medicine in the school bag, I keep it in the nurse room",
    audience: "student_support",
    categories: vendorScores({ illicit: 0.38, "self-harm": 0.12 }),
    note: "medication at school",
  },
  {
    id: "b16",
    label: "benign",
    edge: true,
    text: "I have been having panic attacks before every test, can I talk to the school counsellor?",
    audience: "student_support",
    categories: vendorScores({ "self-harm": 0.44, harassment: 0.16 }),
    note: "mental health, asks for help",
  },
  {
    id: "b17",
    label: "benign",
    text: "The periods chapter is open now in our biology book, page 42.",
    audience: "class_channel",
    categories: vendorScores({ sexual: 0.33 }),
    note: "'periods' as a chapter, not menstruation",
  },

  // --- sports ---
  {
    id: "b18",
    label: "benign",
    edge: true,
    text: "we had a fight during the match and now my leg is all bruised",
    audience: "student_support",
    categories: vendorScores({ violence: 0.58, "violence/graphic": 0.36, harassment: 0.2 }),
    note: "contact sport",
  },
  {
    id: "b19",
    label: "benign",
    text: "We won the football final 3-1! 🏆 Our coach was so proud of the defence",
    audience: "class_channel",
    categories: vendorScores({ violence: 0.11 }),
    note: "sports result",
  },
  {
    id: "b20",
    label: "benign",
    text: "He took a knee hit during practice and needs ice. Can we have the first aid kit?",
    audience: "class_channel",
    categories: vendorScores({ violence: 0.61, "violence/graphic": 0.22 }),
    note: "'knee hit' + practice",
  },

  // --- Indian language / Hinglish / emoji ---
  {
    id: "b21",
    label: "benign",
    edge: true,
    text: "मेरा सवाल है कि गणित में यह प्रश्न कैसे हल करें, कृपया बताइए",
    audience: "student_teacher",
    categories: vendorScores({ harassment: 0.19, hate: 0.1 }),
    note: "Devanagari maths question",
  },
  {
    id: "b22",
    label: "benign",
    text: "bhai homework kar liya kya tune? kal se test hai",
    audience: "student_dm",
    categories: vendorScores({ harassment: 0.26, violence: 0.08 }),
    note: "Hinglish homework reminder",
  },
  {
    id: "b23",
    label: "benign",
    edge: true,
    text: "😂😂😂🙏👍",
    audience: "student_dm",
    categories: vendorScores({}),
    note: "emoji only",
  },
  {
    id: "b24",
    label: "benign",
    text: "😡😡 why is the school wifi so slow again",
    audience: "class_channel",
    categories: vendorScores({ hate: 0.14, harassment: 0.17 }),
    note: "emoji + complaint",
  },
  {
    id: "b25",
    label: "benign",
    text: "I hate Mondays, back to school already 😩",
    audience: "class_channel",
    categories: vendorScores({ hate: 0.38, harassment: 0.15 }),
    note: "benign 'hate'",
  },

  // --- exam stress / burnout ---
  {
    id: "b26",
    label: "benign",
    edge: true,
    text: "I am so stressed about the exams, I have not slept for three nights",
    audience: "student_support",
    categories: vendorScores({ "self-harm": 0.49, "self-harm/intent": 0.26, hate: 0.2 }),
    note: "exam stress with real vendor noise",
  },
  {
    id: "b27",
    label: "benign",
    text: "Overwhelmed with the practical exam and my portfolio deadline, need an extension",
    audience: "student_teacher",
    categories: vendorScores({ "self-harm": 0.4, harassment: 0.18 }),
    note: "academic pressure",
  },

  // --- staff / leadership clinical register ---
  {
    id: "b28",
    label: "benign",
    edge: true,
    text: "Heads up: year 9 has a self-harm disclosure in the wellbeing thread. Safeguarding lead please review.",
    audience: "staff",
    categories: vendorScores({ "self-harm": 0.78, "self-harm/intent": 0.41, harassment: 0.2 }),
    note: "staff safeguarding handover must NOT be blocked or noisy",
  },
  {
    id: "b29",
    label: "benign",
    text: "Reminder: all staff must complete the child protection and boundaries module by Friday",
    audience: "staff",
    categories: vendorScores({ "self-harm/instructions": 0.33, sexual: 0.19 }),
    note: "'boundaries' in a staff notice",
  },
  {
    id: "b30",
    label: "benign",
    text: "The new safeguarding policy is on the leadership drive under policies/safeguarding-v3.pdf",
    audience: "leadership",
    categories: vendorScores({ "self-harm": 0.43, hate: 0.2 }),
    note: "policy reference",
  },

  // --- peer pressure ---
  {
    id: "b31",
    label: "benign",
    edge: true,
    text: "My friends pressured me to smoke behind the ground and I refused. What should I do?",
    audience: "student_support",
    categories: vendorScores({ illicit: 0.63, "illicit/violent": 0.18 }),
    note: "peer pressure disclosure — the system working",
  },

  // --- academic reference to hard topics ---
  {
    id: "b32",
    label: "benign",
    edge: true,
    text: "For my history chapter on the world war I need notes on weapons used in the trenches",
    audience: "student_teacher",
    categories: vendorScores({ violence: 0.59, illicit: 0.41, hate: 0.2 }),
    note: "syllabus weapons question",
  },
  {
    id: "b33",
    label: "benign",
    text: "Ma'am can we cover suicide prevention in the health class? It is in our syllabus",
    audience: "student_teacher",
    categories: vendorScores({ "self-harm": 0.61, "self-harm/intent": 0.24 }),
    note: "asking for the lesson on suicide prevention",
  },
  {
    id: "b34",
    label: "benign",
    text: "The biology textbook chapter on the human reproductive system is quite graphic, is there an alternative?",
    audience: "student_teacher",
    categories: vendorScores({ sexual: 0.55, violence: 0.2 }),
    note: "asking for a less graphic textbook",
  },

  // --- images ---
  {
    id: "b35",
    label: "benign",
    media: "image",
    nudityScore: 1,
    audience: "student_teacher",
    text: "",
    categories: vendorScores({ sexual: 0.021, violence: 0.011 }),
    note: "photo of a textbook page",
  },
  {
    id: "b36",
    label: "benign",
    media: "image",
    nudityScore: 2,
    audience: "class_channel",
    text: "",
    categories: vendorScores({ sexual: 0.18, violence: 0.05 }),
    note: "group photo on the school trip",
  },
  {
    id: "b37",
    label: "benign",
    media: "image",
    nudityScore: 1,
    audience: "class_channel",
    text: "",
    categories: vendorScores({ violence: 0.24, "violence/graphic": 0.09 }),
    note: "sports day photo",
  },

  // --- misc school life ---
  {
    id: "b38",
    label: "benign",
    text: "Miss, can I come to school late tomorrow? I have a dentist appointment at 9",
    audience: "student_teacher",
    categories: vendorScores({}),
    note: "appointment request",
  },
  {
    id: "b39",
    label: "benign",
    text: "Can we reschedule the PT period? We have the inter-school match that morning",
    audience: "student_teacher",
    categories: vendorScores({ violence: 0.16 }),
    note: "timetable request",
  },
  {
    id: "b40",
    label: "benign",
    edge: true,
    text: "Teacher is being biased against me, he always picks the same students for everything",
    audience: "student_teacher",
    categories: vendorScores({ harassment: 0.55, hate: 0.24 }),
    note: "allegation about a teacher — belongs with the teacher, not the safeguarding queue",
  },

  // --- HARD benign: deliberately close to the line ---
  {
    id: "b41",
    label: "benign",
    edge: true,
    text: "The PSHE film has a stabbing scene and a lot of blood, is there an alternative worksheet?",
    audience: "student_teacher",
    categories: vendorScores({ violence: 0.44, "violence/graphic": 0.46, hate: 0.2 }),
    note: "graphic content in a curriculum film",
  },
  {
    id: "b42",
    label: "benign",
    text: "What is the difference between a computer virus and a biological virus? My laptop has malware.",
    audience: "student_teacher",
    categories: vendorScores({ illicit: 0.38, "illicit/violent": 0.12 }),
    note: "'virus'/'malware' double meaning",
  },
  {
    id: "b43",
    label: "benign",
    text: "The fire drill today was so scary, my heart was racing the whole time",
    audience: "class_channel",
    categories: vendorScores({ violence: 0.34, "self-harm": 0.22 }),
    note: "fire drill, 'scary'",
  },
  {
    id: "b44",
    label: "benign",
    edge: true,
    text: "Ma'am, my grandfather died last month and I cannot focus on anything, I feel so low",
    audience: "student_support",
    categories: vendorScores({ "self-harm": 0.63, "self-harm/intent": 0.19, hate: 0.24 }),
    note: "bereavement — self_harm noise is high, content is a young person asking for help",
  },
  {
    id: "b45",
    label: "benign",
    edge: true,
    text: "I fractured my wrist playing handball yesterday and the hospital took an x-ray",
    audience: "student_support",
    categories: vendorScores({ violence: 0.5, "violence/graphic": 0.55, harassment: 0.16 }),
    note:
      "KNOWN FALSE POSITIVE (accepted): the sports_contact allowlist is vetoed by the word 'hospital', so a real injury report gets held. Documented in docs/MODERATION.md as the cost of the hard-term veto.",
  },
];

// ------------------------------------------------------------
// TRUE POSITIVES — content that must not reach a student.
// 26 cases. `expect` records the outcome we actually want; a hold is
// acceptable (a human sees it), a silent approve is a FAILURE.
// ------------------------------------------------------------
const POSITIVE = [
  // --- bullying ---
  {
    id: "p01",
    label: "positive",
    edge: true,
    text: "I will break your legs you worthless idiot, see you after school",
    audience: "student_dm",
    categories: vendorScores({ violence: 0.81, "harassment/threatening": 0.74, harassment: 0.6 }),
    note: "threat + insult; multi-signal block",
    expect: "block",
  },
  {
    id: "p02",
    label: "positive",
    text: "everyone laugh at him he is so fat and ugly, nobody wants him in our class",
    audience: "class_channel",
    categories: vendorScores({ harassment: 0.92, hate: 0.66, "harassment/threatening": 0.41 }),
    note: "class-wide humiliation; multi-signal block",
    expect: "block",
  },
  {
    id: "p03",
    label: "positive",
    text: "you are so stupid you should just kill yourself, nobody likes you here",
    audience: "student_dm",
    categories: vendorScores({ "harassment/threatening": 0.9, harassment: 0.86, hate: 0.61, "self-harm": 0.44 }),
    note: "suicide encouragement; multi-signal block + escalate",
    expect: "block",
  },
  {
    id: "p04",
    label: "positive",
    edge: true,
    text: "You are such a retard, go back to where you came from, you do not belong here",
    audience: "class_channel",
    categories: vendorScores({ hate: 0.94, "hate/threatening": 0.79, harassment: 0.71 }),
    note: "ableist slur + exclusion; multi-signal block",
    expect: "block",
  },
  {
    id: "p05",
    label: "positive",
    text: "shut up you stupid fat idiot, nobody here wants you, just leave the class",
    audience: "student_dm",
    categories: vendorScores({ harassment: 0.87, hate: 0.42 }),
    note: "single-category harassment: MUST hold, MUST NOT block on one signal",
    expect: "hold",
  },

  // --- self-harm ---
  {
    id: "p06",
    label: "positive",
    edge: true,
    text: "I want to cut myself, I hate my body and nobody would even notice",
    audience: "student_support",
    categories: vendorScores({ "self-harm": 0.74, "self-harm/intent": 0.63, harassment: 0.22 }),
    note: "disclosure in a support thread — must HOLD and escalate, never block silently",
    expect: "hold",
  },
  {
    id: "p07",
    label: "positive",
    text: "I am going to kill myself tonight, nobody cares and I am done with all of this",
    audience: "student_support",
    categories: vendorScores({ "self-harm": 0.97, "self-harm/intent": 0.94, "self-harm/instructions": 0.61 }),
    note: "imminent self-harm intent; critical single-signal block + escalate",
    expect: "block",
  },
  {
    id: "p08",
    label: "positive",
    text: "what is the least painful way to end my life, I have decided",
    audience: "student_dm",
    categories: vendorScores({ "self-harm": 0.95, "self-harm/instructions": 0.92, "self-harm/intent": 0.88 }),
    note: "method request; critical block",
    expect: "block",
  },

  // --- CSAE ---
  {
    id: "p09",
    label: "positive",
    text: "send me photos of the girls in 7A naked, I want to see them without clothes",
    audience: "student_dm",
    categories: vendorScores({ "sexual/minors": 0.96, sexual: 0.83, harassment: 0.4 }),
    note: "CSAE solicitation; critical block + escalate",
    expect: "block",
  },
  {
    id: "p10",
    label: "positive",
    edge: true,
    text: "Teacher, you have such a nice body. Can you send me a photo of yourself without your clothes?",
    audience: "student_teacher",
    categories: vendorScores({ "sexual/minors": 0.88, sexual: 0.91, harassment: 0.45 }),
    note: "student soliciting a teacher — critical block + escalate",
    expect: "block",
  },
  {
    id: "p11",
    label: "positive",
    text: "everyone share the naked photo of the new girl in the year 7 group chat",
    audience: "student_dm",
    categories: vendorScores({ "sexual/minors": 0.93, harassment: 0.7, sexual: 0.76 }),
    note: "non-consensual CSAE image sharing",
    expect: "block",
  },

  // --- adult sexual content ---
  {
    id: "p12",
    label: "positive",
    edge: true,
    text: "here are my nudes, look at my body 😏 interested?",
    audience: "student_dm",
    categories: vendorScores({ sexual: 0.85 }),
    note: "adult content, SINGLE category just under its block bar — must hold for adult-conduct review",
    expect: "hold",
  },
  {
    id: "p13",
    label: "positive",
    text: "join my onlyfans, I will send you explicit photos for money",
    audience: "student_dm",
    categories: vendorScores({ sexual: 0.89, illicit: 0.62 }),
    note: "sexual + commercial; multi-signal block",
    expect: "block",
  },

  // --- hate speech ---
  {
    id: "p14",
    label: "positive",
    text: "all Muslims should be thrown out of this country, they are the root of everything bad",
    audience: "class_channel",
    categories: vendorScores({ hate: 0.97, "hate/threatening": 0.83, harassment: 0.4 }),
    note: "religious hate speech; critical block",
    expect: "block",
  },
  {
    id: "p15",
    label: "positive",
    text: "people of that caste are dirty animals, keep them out of our school",
    audience: "class_channel",
    categories: vendorScores({ hate: 0.93, harassment: 0.72, "hate/threatening": 0.51 }),
    note: "caste hate + exclusion; multi-signal block",
    expect: "block",
  },

  // --- violence / graphic ---
  {
    id: "p16",
    label: "positive",
    text: "I waited for him after school and I broke his nose, there was blood everywhere",
    audience: "student_dm",
    categories: vendorScores({ violence: 0.96, "violence/graphic": 0.78, "harassment/threatening": 0.6 }),
    note: "assault + graphic; multi-signal block",
    expect: "block",
  },
  {
    id: "p17",
    label: "positive",
    edge: true,
    text: "I slit his throat with a knife and watched the blood spill out",
    audience: "student_dm",
    categories: vendorScores({ "violence/graphic": 0.99 }),
    note: "graphic violence, SINGLE critical category — hold is acceptable, approve is a failure",
    expect: "hold_or_block",
  },
  {
    id: "p18",
    label: "positive",
    text: "I want to smash his head in with a brick, he deserves it",
    audience: "student_dm",
    categories: vendorScores({ violence: 0.9, "harassment/threatening": 0.66, hate: 0.35 }),
    note: "premeditated assault; multi-signal block",
    expect: "block",
  },

  // --- single-signal cases: the multi-signal rule under test ---
  {
    id: "p19",
    label: "positive",
    edge: true,
    text: "I will show you what happens to people who mess with me, you will regret this",
    audience: "student_dm",
    categories: vendorScores({ violence: 0.72 }),
    note: "intimidation, ONE category at 0.72 — must HOLD, must not block on a single signal",
    expect: "hold",
  },
  {
    id: "p20",
    label: "positive",
    text: "he keeps following me home and making comments, I am scared to come to school",
    audience: "student_support",
    categories: vendorScores({ harassment: 0.68, "harassment/threatening": 0.44 }),
    note: "stalking disclosure — single bullying signal, hold for safeguarding",
    expect: "hold",
  },
  {
    id: "p21",
    label: "positive",
    edge: true,
    text: "my father hits me every night when I bring home bad marks, please tell someone",
    audience: "student_support",
    categories: vendorScores({ violence: 0.71, "harassment/threatening": 0.4, "self-harm": 0.31 }),
    note: "child abuse disclosure — hold, escalate; must not be blocked away or auto-approved",
    expect: "hold",
  },
  {
    id: "p22",
    label: "positive",
    text: "how much for a knife that gets through a school bag check",
    audience: "student_dm",
    categories: vendorScores({ illicit: 0.88, violence: 0.52, "illicit/violent": 0.61 }),
    note: "weapon sourcing; illicit + violence block",
    expect: "block",
  },
  {
    id: "p23",
    label: "positive",
    text: "you stupid worthless piece of trash, you are nothing and everyone knows it",
    audience: "student_dm",
    categories: vendorScores({ harassment: 0.79, hate: 0.55 }),
    note: "sustained degradation; two signals above their bars -> multi-signal block",
    expect: "block",
  },
  {
    id: "p24",
    label: "positive",
    text: "my little brother keeps hitting me when we play and I am scared to go home",
    audience: "student_support",
    categories: vendorScores({ violence: 0.65, "violence/graphic": 0.33, harassment: 0.28 }),
    note: "sibling violence disclosure — must reach a human",
    expect: "hold",
  },

  // --- images ---
  {
    id: "p25",
    label: "positive",
    media: "image",
    nudityScore: 5,
    audience: "student_dm",
    text: "",
    categories: vendorScores({ sexual: 0.98 }),
    note: "explicit image; nudity 5 => reject",
    expect: "block",
  },
  {
    id: "p26",
    label: "positive",
    media: "image",
    nudityScore: 3,
    audience: "class_channel",
    text: "",
    categories: vendorScores({ sexual: 0.49 }),
    note: "borderline image; nudity 3 => quarantine",
    expect: "hold",
  },

  // --- HARD positives: the vendor is genuinely uncertain ---
  {
    id: "p27",
    label: "positive",
    edge: true,
    text: "everyone in the group chat start calling her a b!tch and a w0rd, she is nobody",
    audience: "class_channel",
    categories: vendorScores({ harassment: 0.24, hate: 0.19 }),
    note:
      "KNOWN FALSE NEGATIVE (accepted): obfuscated slurs. The vendor scores this as near-benign and the policy layer cannot invent a signal that was never sent. Documented as limitation 1.",
    accept: true,
  },
  {
    id: "p28",
    label: "positive",
    text: "Share her number everyone, she is new here and she owes all of us money",
    audience: "student_dm",
    categories: vendorScores({ harassment: 0.58, illicit: 0.31 }),
    note: "doxxing / debt pressure; single bullying signal -> hold",
    expect: "hold",
  },
  {
    id: "p29",
    label: "positive",
    edge: true,
    text: "send me a pic without any clothes on, just this once",
    audience: "student_dm",
    categories: vendorScores({ "sexual/minors": 0.44, sexual: 0.71, harassment: 0.22 }),
    note: "covert CSAE solicitation below the single-signal block bar; multi-signal aggregate also misses -> HOLD + escalate",
    expect: "hold",
  },
];

export const DATASET = [...BENIGN, ...POSITIVE];

export const DATASET_STATS = {
  total: DATASET.length,
  benign: BENIGN.length,
  positive: POSITIVE.length,
  edge: DATASET.filter((c) => c.edge).length,
  images: DATASET.filter((c) => c.media === "image").length,
};
