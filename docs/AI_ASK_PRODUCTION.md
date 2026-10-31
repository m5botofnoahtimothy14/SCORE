# AI Ask production runbook

## Product boundary

AI Ask is a *grounded supplementary learning assistant*, not a general-purpose
chatbot. It is available only to active, authenticated students in an enrolled
Class 10–12 subject. Its Edge Function retrieves only approved curriculum
chunks, requires citations, and returns an explicit teacher-help fallback when
the retrieval evidence is weak. The app must never present a generated answer
as an official school instruction, an examination answer key, or a substitute
for a teacher.

The authoritative implementation is:

- `supabase/functions/curriculum-rag/index.ts` — authentication, entitlements,
  quota reservation, retrieval, grounding validation and safe failure
- `supabase/migrations/00023_learning_quotas_rag.sql` — reviewed corpus,
  vector index, audit/approval boundary and concurrent-safe quota ledger
- `apps/mobile/lib/features/ai_ask/` — student UI only; it makes no permission
  or quota decisions

## Required secrets

Set these in each Supabase project; do not put any of them in Flutter
`--dart-define` values or in source control.

| Secret | Required | Example |
| --- | --- | --- |
| `LEARNING_AI_API_KEY` | yes | provider API key |
| `LEARNING_AI_BASE_URL` | yes | `https://api.openai.com` or an OpenAI-compatible gateway |
| `LEARNING_AI_CHAT_MODEL` | yes | approved production chat model |
| `LEARNING_AI_EMBEDDING_MODEL` | yes | 1536-dimension embedding model |

The embedding model **must return exactly 1536 dimensions** because that is the
database index contract. Change the schema and re-embed the whole corpus before
changing this model family.

```powershell
supabase secrets set `
  LEARNING_AI_API_KEY=<secret> `
  LEARNING_AI_BASE_URL=<provider-base-url> `
  LEARNING_AI_CHAT_MODEL=<model> `
  LEARNING_AI_EMBEDDING_MODEL=<embedding-model> `
  --project-ref <project-ref>

supabase functions deploy curriculum-rag --no-verify-jwt --project-ref <project-ref>
```

`--no-verify-jwt` is intentional: the function validates the bearer token with
the user-scoped Supabase client so that RPCs run under the caller's RLS context.
Do not replace that check with a service-role client.

## Corpus release gate

Do not enable the AI Ask navigation for a school until all of the following are
true:

1. Original learning material has a recorded source URL, licence name and
   licence URL in `curriculum_documents`.
2. A qualified reviewer has checked chunks, citations and intended class/subject
   scope, then used `approve_curriculum_document`.
3. `curriculum_evaluation_cases` has representative reviewed questions for each
   released subject and grade, including no-answer and prompt-injection cases.
4. A staging run meets the agreed quality target and has no uncited factual
   answers. Weak retrieval must return the teacher-help response.
5. Schools have named a teacher/help channel for students whose question is not
   answered by the corpus.

The corpus is deliberately empty by default. That is a safety control, not a
defect: an empty or weak corpus must produce a truthful refusal rather than an
invented answer.

## Production controls

- Keep dev, staging and production in separate Supabase projects and provider
  accounts/keys.
- Set an individual school cap with `mentor_desk_settings.max_ai_requests` and
  review `student_ai_usage` for unexpected volume, latency and failures.
- Keep the function timeout below the platform limit; the provider client has a
  25-second abort timeout and does not log student questions or provider bodies.
- Preserve idempotency keys for retries made by a future queued/offline client;
  do not reuse one key for a different question.
- Verify RLS and function authorization on staging before each release. A
  student must not query a subject they are not enrolled in or retrieve a
  private/unapproved document.
- Treat model/prompt/corpus changes as releases: version, test, approve, stage,
  then roll out. Keep a rollback to the prior function and corpus version.

## Smoke test

Use a real staging student session, with an enrolled subject and at least one
approved chunk. The expected response has `success: true`, one or more source
citations, a remaining quota count, and no provider credential or question text
in logs. Test these negative paths too:

- wrong/missing token -> `401`
- subject not enrolled -> `403`
- repeat quota exhaustion -> `429`
- empty corpus/weak match -> `200` with `uncertain: true` and teacher help
- provider unavailable -> `503`, and its reservation becomes `failed`

