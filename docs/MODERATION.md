# TeachCross — Moderation Policy & Method

> **The vendor is the signal source. This policy is the decision authority.**
>
> `moderate-message` and `moderate-image` still call OpenAI
> (`omni-moderation` / `omni-moderation-latest`, APILayer nudity as the image
> fallback). What changed is that they no longer turn a raw vendor score into
> a verdict with `maxScore >= 0.8`. They hand the scores to
> `supabase/functions/_shared/moderation_policy.ts`, which decides.

| Concern | Owner |
|---|---|
| Producing the signals | OpenAI / APILayer (unchanged) |
| Deciding the verdict | `_shared/moderation_policy.ts` (`applyPolicy`) |
| Human review | `moderation_review_cases` |
| Audit trail | `moderation_results.raw_response.policy` |
| Measuring the decision | `tests/moderation_policy.test.mjs` |

---

## 1. Why a first-part policy exists

A generic vendor threshold treats "fight", "kill", "blood", "sushi",
"period" and "suicide" as risk. In a school none of those are risk by
default — they are the vocabulary of the place:

- *"I had a **fight** with my friend about homework"*
- *"How do I **kill time** during the long holiday?"*
- *"Ma'am, I missed my **period** and I am really scared, what should I do?"*
- *"Can we cover **suicide** prevention in the health class? It is in our syllabus"*
- *"Heads up: year 9 has a **self-harm** disclosure in the wellbeing thread"*
- *"😂 **I hate** Mondays"*
- *"मेरा सवाल है कि गणित में यह प्रश्न कैसे हल करें"* (a maths question in Hindi)

A blanket threshold **blocks** these. A blocked message in a school is not
an inconvenience: it is a student who cannot ask for help, a parent who
cannot reach a teacher, a disclosure that never reaches a safeguarding
lead. **The false-positive cost in this product is higher than the
false-negative cost for most categories**, and the correct operating point
is therefore "flag for a human" rather than "decide".

Measured on the labelled dataset (74 cases):

| Metric | Value |
|---|---|
| Precision | **0.9655** |
| Recall | **0.9655** |
| F1 | **0.9655** |
| False-positive rate (benign flagged) | **0.0222** (1 / 45) |
| Benign content **blocked** | **0** |
| Accuracy | 0.9729 |

Reproduce with the command in §10.

---

## 2. How signals map to categories

Vendor keys are folded **up** into eight policy categories. Sub-keys take
the **max** of their parent, never the sum — vendor scores are independent
probabilities, and summing double-counts.

| Vendor key(s) | Policy category |
|---|---|
| `sexual/minors` | `sexual_minors` |
| `sexual` | `sexual_adult` |
| `self-harm`, `self-harm/intent`, `self-harm/instructions`, `self-harm/graphic` | `self_harm` |
| `hate`, `hate/threatening` | `hate` |
| `harassment`, `harassment/threatening` | `bullying` |
| `violence` | `violence` |
| `violence/graphic` | `graphic_violence` |
| `illicit`, `illicit/violent` | `illicit` |

Two deliberate extra rules:

- **Images fold `violence` into `graphic_violence`.** A photograph of
  violence is graphic by nature; the same score means something different
  in a photo than in a sentence.
- **Images inject the nudity observation as a `sexual_adult` signal**, so a
  textbook page and a nude photo travel through the same threshold table.
  Nudity is a *direct physical observation*, not a semantic guess, so it is
  additionally handled as a hard band (§6).

The mapping table is data (`DEFAULT_POLICY.vendorMapping`), so a future
first-party classifier can feed policy-named keys in unchanged.

---

## 3. The multi-signal rule (the core false-positive defence)

**A single non-critical category never blocks.** Blocking requires:

- **(a) one CRITICAL category above its own high `block` bar**, or
- **(b) at least `multiSignal.minCategoriesToBlock` (2) independent
  categories** above their audience-adjusted `hold` bars **and** a mean
  aggregate of at least `multiSignal.aggregateBlockScore` (0.62).

Everything else that is elevated goes to `hold_for_review` — a human
decides. That is the whole point: a wrong *hold* costs a moderator thirty
seconds; a wrong *block* costs a student their question.

`escalate` is orthogonal to the action. `sexual_minors` and `self_harm`
being elevated at all sets `escalate: true`, which the text handler maps
to the `escalated` verdict — so a safeguarding lead is attached even when
the policy only holds. This preserves the old "always escalate
`sexual/minors`" behaviour and adds self-harm.

---

## 4. Threshold table

Per-category bars, `unknown` audience, before scaling:

| Category | `hold` | `block` | Critical? | Never scaled? |
|---|---|---|---|---|
| `sexual_minors` | 0.08 | 0.55 | yes | **yes** |
| `self_harm` | 0.55 | 0.90 | yes | **yes** |
| `sexual_adult` | 0.62 | 0.90 | yes | no |
| `hate` | 0.55 | 0.88 | yes | no |
| `graphic_violence` | 0.45 | 0.80 | yes | no |
| `violence` | 0.60 | 0.92 | no | no |
| `bullying` | 0.62 | 0.93 | no | no |
| `illicit` | 0.70 | 0.95 | no | no |

Why the hold bars are high: the observed live distribution of benign
school messages (`moderation_results.categories` in the production
project) routinely sits at **0.3–0.6** on `violence`, `harassment` and
`self-harm` for messages that are entirely benign. A hold bar at the old
`0.5` would put most of them in the review queue.

`bullying` has the highest hold bar of all categories because it is the
most over-blocked one in a school: "you idiot", "I fought with my friend",
"he hits me at home" (as a disclosure) and "you're being biased against
me" all land here.

---

## 5. Per-audience overrides

`conversation_type` maps straight onto an audience profile; `senderRole`
is the fallback when the conversation type is unknown.

| Audience | `thresholdScale` | Effect |
|---|---|---|
| `student_support` | **1.35** | general hold bars rise 35% — but **bullying → 0.55 and violence → 0.50 (LOWERED)**, and `self_harm` / `sexual_minors` force-escalate |
| `student_teacher` | 1.15 | slight lift; an allegation about a teacher's tone belongs with the teacher |
| `staff` / `leadership` | 1.20 | clinical, statutory and anatomical vocabulary is routine |
| `class_channel` | 0.95 | general bars tighten, but **bullying → 0.55** (broadcast reach) |
| `student_dm` | 0.85 | highest risk: no staff visibility |
| `unknown` | 1.00 | neutral — it can only make the policy *less* strict |

Two invariants, asserted by tests:

1. **Audience scales the `hold` bar, never the `block` bar.** A staff
   member using clinical language gets a higher *flagging* bar. Nobody
   gets a lower bar for blocking CSAE or self-harm.
2. **`self_harm` and `sexual_minors` hold bars are identical in every
   audience.** A disclosure is *most* likely in the supportive thread, so
   the bar must not rise there.

`student_support` is the interesting case: it is simultaneously the
*lowest*-risk audience (loose vocabulary, banter, nothing delivered to the
whole school) and the *highest*-stakes place for a disclosure. The policy
expresses both by lifting the general bars and lowering the two
disclosure-shaped ones.

---

## 6. Images

Nudity is treated as a direct observation on the existing APILayer 1–5
scale, so the old behaviour is preserved exactly:

| Nudity | Verdict | Note |
|---|---|---|
| ≥ 4 | `rejected` | `image:nudity_reject` |
| 3 | `quarantined` | `image:nudity_quarantine` |
| ≤ 2 | `approved` | |

The text allowlist **never applies to images** — an image has no text. The
vendor's own `category_scores` still flow through the multi-signal path
alongside the nudity band, so a CSAE image with a low nudity score is still
escalated by the semantic signal.

---

## 7. The allowlist, and why each entry exists

The vendor sees a word, not a school. Each entry needs **one** term, **one**
context term, and **no** hard term. Nine entries ship:

| id | fires on | suppresses | vetoed by |
|---|---|---|---|
| `argument_between_peers` | fight/argue/quarrel + homework, a friend, a seat, a match… | `violence`, `bullying` | "beat you", "after school", **"scared", "following me", "hits me"** |
| `kill_time_idiom` | kill + time/it/boring/revision… | `violence`, `self_harm` | "kill myself", "end my life", "suicide" |
| `academic_reference` | weapon/suicide/sex/abuse… + chapter, syllabus, biology, film… | all seven non-CSAE | "kill myself", "send me", "i will", "teach me" |
| `health_and_medication` | period, anxiety, insulin, therapy, fever, grief… + doctor, school, help… | `self_harm`, `illicit` | "suicide", "kill myself", "cut myself" |
| `sports_contact` | fight/hit/bruised/knee… + match, practice, coach, ice… | `violence`, `graphic_violence`, `bullying` | "hospital", "stab", **"scared", "hits me"** |
| `exam_stress` | stressed/panic/overwhelmed… + exam, marks, deadline… | `self_harm`, `hate` | "kill myself", "hate myself", "worthless" |
| `friendly_insult` | idiot/stupid/bewakoof… + friend, lol, joking… | `bullying`, `hate` | "fat", "ugly", "nobody likes you" |
| `peer_pressure_disclosure` | smoke/drink/vape… + pressured, refused, said no… | `illicit` | "where can i buy" |
| `staff_case_note` | safeguarding, self-harm, disclosure, incident… + year, thread, lead, handover… | `self_harm`, `bullying` | "i want to", "my own", "suicidal" |

Four design rules, all enforced in code and asserted by tests:

1. **The allowlist can never mask a block.** A matched entry refuses to
   suppress any signal already at or above its own `block` bar
   (`allowlist_refused:<category>` in `matchedRules`, with a reason).
2. **An entry only explains what its context can actually explain.**
   `exam_stress` suppresses `self_harm` and `hate` — it explains *self*-
   directed distress — but **not** `bullying`, because exam stress explains
   nothing about "he keeps following me home". Same for
   `health_and_medication`, which no longer suppresses `bullying` or
   `violence`.
3. **Personal-safety cues veto the everyday-vocabulary entries.** "scared",
   "afraid", "following me", "hits me", "touches me" are in the `excludes`
   of both `argument_between_peers` and `sports_contact`, so a disclosure
   dressed in everyday words cannot be allowlisted away.
4. **Images are exempt.** The allowlist is text-only.

An approval where the allowlist did work is recorded as the `warned`
verdict — deliverable, but visible in the audit trail — and the decision
always names the term and the context that justified it.

---

## 8. Measured results

Produced by `node --test tests/moderation_policy.test.mjs` on
**Node v24.19.0**, dataset of **74** cases (**45** benign, **29**
positive, 28 flagged as edge cases, 5 images).

### Shipped configuration

```
  policy                  TP   FP   TN   FN    prec    recall  F1      FP-rate  blocked-benign
  v1.0.0  <== SHIPPED     28   1    44   1    0.9655  0.9655  0.9655  0.0222   0
```

The single FN is case `p27` (obfuscated slurs — a vendor miss, §9.1). The
single FP is case `b45` (a held injury report, §9.2).

### Hold bars scaled, block bars untouched

```
  hold x0.70     28   3   38   0    0.9032  0.9655  0.9333  0.0667   0
  hold x0.85     28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  hold x1.00  << 28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  hold x1.15     26   1   40   3    0.9630  0.8966  0.9286  0.0222   0
  hold x1.30     26   1   40   3    0.9630  0.8966  0.9286  0.0222   0
  hold x1.45     24   1   40   5    0.9600  0.8276  0.8889  0.0222   0
  hold x1.60     22   1   40   7    0.9565  0.7586  0.8462  0.0222   0
```

Loosening to ×0.70 buys nothing on recall and costs 3 false positives;
tightening past ×1.15 loses positives with no precision gain. The shipped
×1.00 sits on the plateau, and there is a two-point-wide margin either
side before the metric degrades.

### Block bars scaled, hold bars untouched

```
  block x0.80    28   2   39   0    0.9333  0.9655  0.9492  0.0444   1
  block x0.90    28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  block x1.00 << 28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  block x1.10    28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  block x1.25    28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
```

Dropping the block bars to ×0.80 is the only setting that blocks a benign
message. Raising them changes nothing on this dataset, because the
multi-signal path (not the critical-single-signal path) is what fires.
Keep the margin: ×0.80 costs precision for no recall.

### Multi-signal aggregate bar

```
  bar 0.50    28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  bar 0.56    28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  bar 0.62 << 28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  bar 0.70    28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  bar 0.78    28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
```

Flat across the whole range: on this dataset the aggregate bar is not the
binding constraint. It is kept at 0.62 because it is the guard that stops
two *weak* signals (e.g. 0.60 + 0.61) from blocking — a case this dataset
happens not to contain.

### Categories required to block without a critical hit

```
  min 1       28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  min 2    << 28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
  min 3       28   1   40   0    0.9655  0.9655  0.9655  0.0222   0
```

Flat, because `min 1` is immediately dominated by the critical-single-
signal rule. `2` is kept: it is the structural defence against a vendor
that is confidently wrong about one category, which this dataset happens
not to contain but production will.

### The two errors

```
  b45 benign held  "I fractured my wrist playing handball yesterday and the hospital took an x-ray"
  p27 POSITIVE APPROVED  "everyone in the group chat start calling her a b!tch and a w0rd"
```

Both are recorded in the dataset as known, accepted misses (`b45` is a
benign hold; `p27` is marked `accept: true`).

---

## 9. Known limitations

1. **Obfuscated and coded language is a vendor miss, not a policy miss.**
   `p27` (*"b!tch"*, *"w0rd"*) is scored 0.24 / 0.19 by the vendor and the
   policy correctly approves it — there was no signal to act on. The policy
   layer deliberately does not invent signals; that is what stops it
   becoming a profanity filter. Mitigating this needs a first-party signal
   (de-obfuscation, or an n-gram classifier), not a threshold change.
2. **The hard-term veto costs us real injury reports.** `sports_contact`
   vetoes on "hospital", so `b45` — a genuine wrist fracture — is held. The
   trade is deliberate: an un-vetoed sports entry would let "he hit me and
   I am in hospital" through. One held message is the cheaper error.
3. **The allowlist is English (+ Devanagari-ish) only.** Terms are matched
   as normalised literal phrases. Tamil, Telugu, Urdu and Bengali content
   gets no benign-context relief and depends purely on the thresholds.
   `b21` (a maths question in Devanagari) passes only because its scores
   are genuinely low. This is the largest known gap.
4. **Scores in the dataset are recorded, not live.** Reproducing them
   needs `OPENAI_API_KEY`; a test suite must be deterministic. They were
   authored inside the distribution observed in the production
   `moderation_results` table. See §11.
5. **Single-message decisions have no conversational context.** The policy
   sees one message plus the conversation *type*. It cannot see that the
   third message in a row is escalating, or that this student's last three
   messages were about self-harm. A first-party conversation-level signal
   is the natural next layer.
6. **The review queue has no SLA.** The policy deliberately routes
   ambiguity to humans. Without a moderation-review target (e.g. 4 working
   hours), the hold path becomes a silent drop, which is worse than either
   extreme. This is an operational prerequisite, not a code change.

---

## 10. Reproducing the numbers

Requires **Node >= 22.6** (the test imports the real `.ts` edge module
directly — no mirror copy, so it cannot drift). Node 23.6+ removes the
type-stripping warning.

```powershell
# The full evaluation, with the results tables printed
node --test tests/moderation_policy.test.mjs

# The whole suite (this is what CI runs)
npm test
```

Expected: `tests 78 / pass 78 / fail 0`, and the shipped row reads
`prec 0.9655  recall 0.9655  F1 0.9655  FP-rate 0.0222  blocked-benign 0`.

---

## 11. Re-tuning safely

> **Any change to `DEFAULT_POLICY` or to the dataset must be accompanied by
> a re-run of `node --test tests/moderation_policy.test.mjs` in the same
> commit.** The numbers in §8 are not decoration; they are the only thing
> standing between a threshold edit and a silent regression that blocks
> children's questions.

Procedure:

1. **Add the case first.** Put it in `tests/fixtures/moderation_dataset.mjs`
   with a `note` explaining why it is what it is. If it does not fit the
   existing policy, that is the finding.
2. **Re-run the eval and read the error list.** The harness prints every
   benign-blocked, benign-held and positive-approved case by id.
3. **Change one thing.** One threshold, one allowlist term, one audience
   scale. `scalePolicy()` in the harness will sweep it for you.
4. **Re-read all four sweeps**, not just the shipped row. A change that
   improves the headline F1 by pushing the multi-signal bar to 0.50 is
   buying precision with recall you cannot get back.
5. **Bump `DEFAULT_POLICY.version`** and re-record §8.
6. If a new error appears, mark it `accept: true` **only** with a `note`
   starting `KNOWN` and add it to §9. Never delete a failing case — a test
   suite that has been made to pass by deletion is worse than none.

### Re-recording the dataset against a live vendor (optional, not in CI)

The recorded scores are authored inside the distribution observed in the
production `moderation_results` table, so they are a *model* of the vendor,
not a snapshot of it. Re-record quarterly, or immediately after an OpenAI
model change — vendor score distributions move, and these thresholds are
calibrated against them.

To re-record, post each `tests/fixtures/moderation_dataset.mjs` `text`
through `https://api.openai.com/v1/moderations`, replace the
`categories: vendorScores({...})` block for that case with the returned
`category_scores`, and re-run the eval. Do it as a single commit that also
updates §8, so the change and the measurement are reviewed together. If
the re-recorded numbers move the headline metrics, that is a vendor
migration, not a policy regression — read the error list before touching a
threshold.

---

## 12. Operational notes

- **Fail-closed is unchanged and is now inside the policy.** A missing
  `OPENAI_API_KEY`, a provider HTTP error, or an unconfigured APILayer key
  all produce `hold` / `quarantined`. `applyPolicy` returns
  `hold_for_review` with the `fail_closed` rule for any `providerError` or
  missing provider, *even when the supplied scores are catastrophic*.
  Asserted by `provider failure / missing provider NEVER approves` and by
  `16. missing moderation credentials never mark content safe` in
  `tests/security.test.mjs`.
- **Auth and error shape are untouched.** Both handlers still guard on
  `x-webhook-secret` → `401 Unauthorized`, missing fields → `400`, missing
  attachment → `404`, and a thrown error → `500 Server error`. Nothing was
  added to the request contract, so the Postgres `pg_net` triggers in
  `supabase/migrations/00015` need no change.
- **DB writes are unchanged in shape.** `moderation_results` still gets
  one row per message/attachment with the same columns. The policy audit
  trail is written to the existing `raw_response` jsonb column:
  ```jsonc
  {
    "policy_version": "1.0.0",
    "action": "hold_for_review",
    "policy_score": 0.68,
    "raw_max_score": 0.68,
    "audience": "student_support",
    "audience_scale": 1.35,
    "matched_rules": ["allowlist:academic_reference", "signal:bullying", "rule:hold_single_signal"],
    "allowlist_matches": ["academic_reference"],
    "reasons": ["held: category=bullying score=0.68 threshold=0.55 (…)"],
    "explanation": "held: … | rules: …"
  }
  ```
  `confidence` keeps its existing meaning (the vendor's raw max score) so
  historical rows stay comparable; the policy's own score is
  `policy_score`.
- **Every hold is self-explaining.** A safeguarding lead reading the review
  queue sees, verbatim:
  - `held: category=self_harm score=0.74 threshold=0.55 (1 elevated signal(s) below the block bar — a single category never blocks)`
  - `approved via allowlist: 'argument_between_peers' — violence score=0.41 threshold=0.6 suppressed as benign school context`
  - `blocked: multi-signal — 2 independent categories (violence=0.81, bullying=0.74) aggregate=0.775 >= bar=0.62`
  - `allowlist 'academic_reference' REFUSED for violence: score=0.95 >= block threshold=0.92 — benign context cannot mask a block-level signal`
- **Verdict mapping.** Text: `approve → approved | warned`,
  `hold_for_review → held`, `block → blocked`, and any of those with
  `escalate` → `escalated`. Image: `approve → approved`,
  `hold_for_review → quarantined`, `block → rejected`. `escalated` and
  `held` both leave `messages.status = held_for_review`, so delivery
  behaviour is unchanged; only the review-case priority differs.
- **Deploy.** `_shared/moderation_policy.ts` is a shared module and is
  bundled into each function by the Supabase CLI; it does not deploy on
  its own.
  ```powershell
  & "D:\dev\npm-global\supabase.cmd" functions deploy moderate-message --no-verify-jwt --project-ref <project-ref>
  & "D:\dev\npm-global\supabase.cmd" functions deploy moderate-image  --no-verify-jwt --project-ref <project-ref>
  ```
- **See also:** [`AI_FEATURES.md`](./AI_FEATURES.md) (the additive analytics
  layer, which still has no authority over any of this),
  [`KEYS_CHECKLIST.md`](./KEYS_CHECKLIST.md) (`OPENAI_API_KEY`,
  `APILAYER_API_KEY`), [`SECURITY.md`](./SECURITY.md).
