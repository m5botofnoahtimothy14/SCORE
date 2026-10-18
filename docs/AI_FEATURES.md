# TeachCross — AI Features (Gemini)

> **This layer is ADDITIVE.**
> The moderation layer (`moderate-message`, `moderate-image`) is and remains
> the **safety authority**. OpenAI / APILayer supply the *signals*; the
> verdict is decided by our own policy in
> [`_shared/moderation_policy.ts`](../supabase/functions/_shared/moderation_policy.ts)
> (method and measured precision/recall in [`MODERATION.md`](./MODERATION.md)).
> It is fail-closed: if `OPENAI_API_KEY` is missing or the provider errors,
> messages are **held for human review** — never approved.
> Nothing described on this page can approve, block, moderate, escalate or
> overwrite a moderation decision. If Gemini is unavailable, every AI feature
> returns an error and the platform behaves exactly as it did before this layer
> was added.

The three functions below are analytics and writing assistance:

| Function | Audience | Writes to DB? | Can it affect safety? |
|---|---|---|---|
| `score-conversation` | conversation member, school admin, head teacher | yes — `conversation_scores` | **No** (reporting only) |
| `ai-smart-reply` | conversation member | no | **No** (suggestions; the sent message is still moderated) |
| `ai-school-insights` | platform owner, school admin, head teacher | no | **No** (aggregate counts only) |

---

## 1. `score-conversation`

Scores one conversation with Gemini and upserts into `conversation_scores`.

**How it works**

1. Requires `Authorization: Bearer <user JWT>`. A user-scoped client is built and
   `auth.getUser()` is called — otherwise `401 unauthorized`.
2. Authorisation (via `.rpc()` on the *user* client, so the caller's own identity
   is what `SECURITY DEFINER` evaluates):
   - `tc_is_conversation_member(conversation_id)`, **or**
   - `tc_is_school_admin(school_id)`, **or**
   - `tc_has_school_role(school_id, 'head_teacher')`
   Otherwise `403 forbidden`.
3. Loads the **last 60 `status = 'approved'`, `is_deleted = false`** messages.
   Held/blocked/deleted messages are never read. Each body is truncated to
   **1000 chars** and senders are pseudonymised to `Participant 1..N` — the model
   never sees raw user ids.
4. Calls Gemini with `responseMimeType: "application/json"` and a strict schema
   prompt, then clamps all four scores to `0..100` server-side and strips
   ```json fences before parsing.
5. Upserts on `conversation_id` (service-role client), writing `model` as the
   model + transport actually used and `scored_at = now()`.

**Safety floor:** `flagged` is set to `true` if the model says so **or** if the
reported `safety_risk >= 70`. The model can raise a flag but cannot clear a high
risk it itself reported.

**Request**

```jsonc
POST https://<project-ref>.supabase.co/functions/v1/score-conversation
Authorization: Bearer <user access token>
Content-Type: application/json

{ "conversation_id": "de408209-0f0b-4481-a59b-4f1654f05e25" }
```

**Success**

```jsonc
{
  "success": true,
  "conversation_id": "de408209-0f0b-4481-a59b-4f1654f05e25",
  "score": {
    "overall": 72.5,
    "sentiment": 64,
    "safety_risk": 18,
    "resolution": 80,
    "flagged": false,
    "topics": ["homework", "attendance"],
    "summary": "Teacher and student agreed a catch-up plan for missed coursework."
  },
  "messages_considered": 14,
  "model": "gemini-2.0-flash@google_api"
}
```

**Errors** (all are `{"success": false, "error": "<code>"}`)

| Status | `error` | Cause |
|---|---|---|
| 400 | `invalid_conversation_id` | not a uuid |
| 400 | `invalid_json` | body was not JSON |
| 401 | `unauthorized` | missing/invalid JWT |
| 403 | `forbidden` | not a member, admin or head teacher |
| 404 | `conversation_not_found` | no such conversation |
| 422 | `no_approved_messages` | thread has nothing approved to analyse |
| 502 | `ai_provider_error` | Gemini reachable but returned an error |
| 503 | `ai_unavailable` | no Gemini credential configured at all |
| 500 | `server_error` | DB failure |

---

## 2. `ai-smart-reply`

Three short suggested replies for the person composing a message.

- Same auth pattern; the caller **must** be an active member of the conversation
  (`tc_is_conversation_member`), otherwise `403 forbidden`.
- Reads the **last 12 approved, non-deleted** messages as context. The caller's own
  messages are rendered as `You`.
- `tone` is optional (default `friendly-professional`) and must be one of:
  `friendly-professional`, `warm-empathetic`, `concise-direct`, `encouraging`, `formal`.
  Anything else is `400 invalid_tone`.
- Model output is validated server-side: only plain strings are kept, list numbering
  and wrapping quotes are stripped, duplicates dropped, entries over **180 chars**
  rejected, and at most **3** returned. If nothing survives validation the call
  fails with `502 ai_provider_error` rather than returning an empty list.

**Request**

```jsonc
POST https://<project-ref>.supabase.co/functions/v1/ai-smart-reply
Authorization: Bearer <user access token>
Content-Type: application/json

{
  "conversation_id": "de408209-0f0b-4481-a59b-4f1654f05e25",
  "draft": "Thanks for letting me know, I will",
  "tone": "warm-empathetic"
}
```

`draft` is optional and truncated to 500 chars.

**Success**

```jsonc
{
  "success": true,
  "suggestions": [
    "Thanks for the update — I'll pick this up before the end of the week.",
    "Appreciate you letting me know. I'll have a look and come back to you.",
    "Got it, thank you. I'll follow up once I've checked with the class teacher."
  ],
  "model": "gemini-2.0-flash@google_api"
}
```

**Errors**

| Status | `error` | Cause |
|---|---|---|
| 400 | `invalid_conversation_id` / `invalid_tone` / `invalid_draft` / `invalid_json` | validation |
| 401 | `unauthorized` | missing/invalid JWT |
| 403 | `forbidden` | not a member of the conversation |
| 422 | `no_approved_messages` | no approved context |
| 502 | `ai_provider_error` | Gemini error, or output failed validation |
| 503 | `ai_unavailable` | no Gemini credential configured |

---

## 3. `ai-school-insights`

A leadership-level school-health summary.

**Auth:** `tc_is_platform_owner()` **or** `tc_is_school_admin(school_id)` **or**
`tc_has_school_role(school_id, 'head_teacher')`. The response includes
`"scope": "admin" | "leadership"` so the caller knows which view it got. Head
teachers get the aggregate view only — never per-conversation detail.

`school_id` is optional; if omitted it is resolved from the caller's single
active `school_memberships` row, otherwise `400 invalid_school_id`.

**Privacy — aggregates only.** These are the *only* things sent to Gemini:
counts (students, teachers, classes, open safeguarding incidents, open moderation
cases, failed notification jobs), averages of the 10 most recent
`conversation_scores`, and up to 5 frequency-ranked **model-generated topic
labels**. No message text, no conversation titles, no user ids, no student names
and no incident descriptions are ever transmitted.

**Request**

```jsonc
POST https://<project-ref>.supabase.co/functions/v1/ai-school-insights
Authorization: Bearer <user access token>
Content-Type: application/json

{ "school_id": "11111111-1111-1111-1111-111111111111" }
```

**Success**

```jsonc
{
  "success": true,
  "school_id": "11111111-1111-1111-1111-111111111111",
  "scope": "admin",
  "metrics": {
    "students": 412,
    "teachers": 38,
    "classes": 19,
    "safeguarding_open": 2,
    "safeguarding_open_high_or_critical": 1,
    "moderation_cases_open": 3,
    "notification_jobs_failed": 0,
    "conversations_scored_recent": 10,
    "conversation_flagged_recent": 1,
    "avg_overall": 71.4,
    "avg_sentiment": 63.8,
    "avg_safety_risk": 22.1,
    "avg_resolution": 68.0,
    "top_topics": ["attendance (4)", "homework (3)", "wellbeing (2)"]
  },
  "summary": "Communication volume is steady with no systemic issues this week. Two safeguarding matters remain open, one at high severity, and three moderation cases are awaiting a reviewer.",
  "actions": [
    "Clear the three moderation cases awaiting review today.",
    "Confirm ownership and a target date for the open high-severity safeguarding matter.",
    "Spot-check attendance conversation threads before the end of the week."
  ],
  "model": "gemini-2.0-flash@google_api"
}
```

**Errors**

| Status | `error` | Cause |
|---|---|---|
| 400 | `invalid_school_id` / `invalid_json` | validation |
| 401 | `unauthorized` | missing/invalid JWT |
| 403 | `forbidden` | not owner/admin/head teacher |
| 502 | `ai_provider_error` | Gemini error, or output failed validation |
| 503 | `ai_unavailable` | no Gemini credential configured |

---

## Secrets

| Secret | Required | Purpose |
|---|---|---|
| `SUPABASE_URL` | yes (auto) | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | yes (auto) | service-role client for the `conversation_scores` upsert |
| `SUPABASE_ANON_KEY` | yes (auto) | builds the user-scoped client so RLS applies |
| `GOOGLE_API_KEY` | **recommended** | primary Gemini credential |
| `FIREBASE_API_KEY` | optional | overrides the compiled-in Firebase web key |
| `FIREBASE_PROJECT_ID` | optional | overrides the compiled-in `teachcross-38f29` |
| `FIREBASE_AI_LOCATION` | optional | defaults to `us-central1` |
| `GEMINI_MODEL` | optional | defaults to `gemini-2.0-flash` |
| `OPENAI_API_KEY` | already set | **moderation only — not used by these three functions** |

### Provider order

`supabase/functions/_shared/gemini.ts` picks the first configured transport:

1. **`GOOGLE_API_KEY`** → Generative Language API
   `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`
2. **Firebase fallback** → Firebase AI Logic (Vertex AI)
   `https://firebasevertexai.googleapis.com/v1beta/projects/teachcross-38f29/locations/us-central1/publishers/google/models/<model>:generateContent`
   using the Firebase **web** API key. This key is a public, client-shipped
   identifier (it is already in the mobile bundle), so compiling it in as a
   fallback default is acceptable — but set `FIREBASE_API_KEY` as a secret if you
   would rather not rely on that.
3. Neither configured → **`503 ai_unavailable`**. The functions never invent a
   result and never write a partial/fabricated score.

> **Note:** because the Firebase fallback is compiled in, `ai_unavailable` is not
> reachable in the current build. If a credential *is* present but Google rejects
> it, you get `502 ai_provider_error` instead. The two codes mean different
> things — do not treat them as interchangeable.

### Getting a `GOOGLE_API_KEY` (recommended — makes provider 1 live)

1. Open <https://aistudio.google.com/apikey> and click **Create API key**, or in
   Google Cloud Console open
   **APIs & Services → Library → "Generative Language API" → Enable**, then
   **Credentials → Create credentials → API key**.
2. Restrict the key (API restriction → *Generative Language API*; application
   restriction → your Supabase egress IP if you know it).
3. Set it:
   ```powershell
   & "D:\dev\npm-global\supabase.cmd" secrets set GOOGLE_API_KEY=<key> `
     --project-ref <project-ref>
   ```

### Enabling the Firebase fallback

The Firebase key is real but, on the current GCP project
(`587525976197`, `teachcross-38f29`), **both** APIs return
`403 SERVICE_DISABLED`:

- *Gemini API* (`generativelanguage.googleapis.com`) — not enabled
- *Firebase AI Logic API* (`firebasevertexai.googleapis.com`) — not enabled

To make the fallback work, enable the API in Google Cloud Console for that
project, then confirm:

```powershell
curl "https://firebasevertexai.googleapis.com/v1beta/projects/teachcross-38f29/locations/us-central1/publishers/google/models/gemini-2.0-flash:generateContent?key=<FIREBASE_API_KEY>" `
  -H "Content-Type: application/json" `
  -d '{"contents":[{"parts":[{"text":"Reply with the single word: OK"}]}]}'
```

Until one of the two transports returns `200`, all three functions correctly
return `502 ai_provider_error` and **no** row is written to `conversation_scores`.

---

## Calling from the app / web

Use the caller's own session token — the functions do their own auth and role
checks, so never call them with the service-role key from a client.

```ts
// supabase-js (mobile / admin DMS)
const { data, error } = await supabase.functions.invoke("ai-smart-reply", {
  body: { conversation_id, draft: composerText, tone: "warm-empathetic" },
});
// data = { success: true, suggestions: string[], model: string }
```

```ts
// plain fetch
const res = await fetch(
  `${SUPABASE_URL}/functions/v1/score-conversation`,
  {
    method: "POST",
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ conversation_id }),
  },
);
const body = await res.json();
if (!res.ok) console.warn("AI unavailable:", body.error);
```

**UI guidance**

- Always `await` these behind an explicit user action (a "Suggest replies"
  button, a "Refresh score" action). Do **not** auto-fire on every keystroke or
  on conversation open — that burns quota for no benefit.
- Handle `503 ai_unavailable` by **hiding** the AI affordance, not by showing a
  scary error. These features are optional.
- Never render a suggestion as if it were sent text, and never let a suggestion
  bypass the normal send path (which is still moderated).
- Treat `metrics`/`summary` as indicative, not as a compliance record.

---

## Cost & latency

- Model: **`gemini-2.0-flash`** (override with `GEMINI_MODEL`). It is the
  cheapest current Gemini tier and is ample for classification and short
  copywriting.
- Realistic end-to-end latency: **~0.6–2 s** per call, dominated by the model.
  Never block a UI thread on it; show a skeleton/pending state.
- Token usage per call, roughly:
  - `score-conversation`: 60 messages x 1000 chars worst case ≈ 15k input
    tokens + ~300 output. Typical threads are far smaller.
  - `ai-smart-reply`: 12 messages + draft ≈ 3k input + ~150 output.
  - `ai-school-insights`: a few hundred input + ~300 output — effectively free.
- Cheap insurance: cap context (already done), keep `temperature` low for scoring
  and insights, and prefer batch scoring on a schedule over scoring every thread
  on every message.
- `conversation_scores` is keyed on `conversation_id`, so re-scoring a thread
  **upserts** rather than duplicating.

## Rate limiting

There is no per-caller limiter in the functions themselves, so the client and/or
Supabase platform settings must provide it:

| Function | Suggested client-side limit | Why |
|---|---|---|
| `ai-smart-reply` | ≤ 3 per user per conversation per minute; debounce 2 s after typing stops | highest user-triggered volume |
| `score-conversation` | ≤ 1 per conversation per 10 min; prefer an hourly/nightly scheduled job | expensive (largest context) |
| `ai-school-insights` | ≤ 1 per school per 15 min; cache client-side | cheap but leads to angry-refresh loops |

Additional guidance:

- Add a client-side cache keyed on `conversation_id` / `school_id` + `scored_at`.
- Treat `502 ai_provider_error` as retryable with exponential backoff; treat
  `503 ai_unavailable` as **not** retryable until a key is configured.
- Consider raising the Supabase project's rate-limit ceiling rather than adding
  per-request auth work.
- Log every AI invocation (`function_id`, `user`, `duration`, `status`) so quota
  can be attributed to a caller before you scale up usage.

---

## Deploy

All three are deployed with `--no-verify-jwt` and validate the caller themselves
by reading the JWT, exactly like `publish-announcement`.

```powershell
& "D:\dev\npm-global\supabase.cmd" functions deploy score-conversation  --no-verify-jwt --project-ref <project-ref>
& "D:\dev\npm-global\supabase.cmd" functions deploy ai-smart-reply     --no-verify-jwt --project-ref <project-ref>
& "D:\dev\npm-global\supabase.cmd" functions deploy ai-school-insights --no-verify-jwt --project-ref <project-ref>
```

`supabase/functions/_shared/gemini.ts` is a shared module, not a function — the
CLI bundles it into each of the three automatically and does not deploy it on its
own.

> If you also want them listed under `[functions.*]` in `supabase/config.toml`
> with `verify_jwt = false` (matching the existing seven functions), add:
> ```toml
> [functions.score-conversation]
> verify_jwt = false
>
> [functions.ai-smart-reply]
> verify_jwt = false
>
> [functions.ai-school-insights]
> verify_jwt = false
> ```

---

## Manual smoke test

```powershell
$BASE = "https://<project-ref>.supabase.co/functions/v1"
$H = @{ Authorization = "Bearer $env:SUPABASE_ACCESS_TOKEN"; "Content-Type" = "application/json" }

Invoke-RestMethod "$BASE/score-conversation" -Method Post -Headers $H `
  -Body '{"conversation_id":"<uuid>"}'

Invoke-RestMethod "$BASE/ai-smart-reply" -Method Post -Headers $H `
  -Body '{"conversation_id":"<uuid>","tone":"warm-empathetic"}'

Invoke-RestMethod "$BASE/ai-school-insights" -Method Post -Headers $H `
  -Body '{"school_id":"<uuid>"}'
```

A conversation with no approved messages returns `422 no_approved_messages` —
that is a correct, expected result, not a bug.

## Relationship to moderation

| Concern | Owner |
|---|---|
| Message / image safety **signals** | `moderate-message`, `moderate-image` (OpenAI omni-moderation, APILayer fallback) |
| Message / image safety **verdicts** | the TeachCross moderation policy — [`MODERATION.md`](./MODERATION.md) |
| Escalation to a human reviewer | `moderation_review_cases` |
| Conversation analytics scores | `score-conversation` (this layer) |
| Reply drafting | `ai-smart-reply` (this layer) |
| Leadership reporting | `ai-school-insights` (this layer) |

If the two layers ever disagree, **moderation wins, always**. See
[`SECURITY.md`](./SECURITY.md) and [`KEYS_CHECKLIST.md`](./KEYS_CHECKLIST.md).