import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  embedQuery,
  generateGroundedAnswer,
  LearningProviderError,
  providerConfig,
} from '../_shared/learning_ai_provider.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: Record<string, unknown>, status = 200) => new Response(
  JSON.stringify(body), { status, headers: { ...corsHeaders, 'content-type': 'application/json' } },
);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ success: false, error: 'method_not_allowed' }, 405);

  const startedAt = Date.now();
  const authorization = req.headers.get('Authorization');
  if (!authorization) return json({ success: false, error: 'unauthorized' }, 401);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ success: false, error: 'invalid_json' }, 400); }

  const question = typeof body.question === 'string' ? body.question.trim() : '';
  const subject = typeof body.subject === 'string' ? body.subject.trim() : '';
  const key = typeof body.idempotency_key === 'string' ? body.idempotency_key : '';
  if (!question || question.length > 2000) return json({ success: false, error: 'invalid_question' }, 400);
  if (!['Physics', 'Chemistry', 'Biology', 'Mathematics'].includes(subject)) return json({ success: false, error: 'unsupported_subject' }, 400);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(key)) return json({ success: false, error: 'invalid_idempotency_key' }, 400);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !anonKey) return json({ success: false, error: 'server_configuration_error' }, 500);
  const client = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: authData, error: authError } = await client.auth.getUser();
  if (authError || !authData.user || authData.user.is_anonymous) return json({ success: false, error: 'unauthorized' }, 401);

  const { data: context, error: contextError } = await client.rpc('student_learning_context');
  if (contextError || !context || !Array.isArray(context.subjects)) return json({ success: false, error: 'student_context_unavailable' }, 403);
  const grade = Number(context.class_grade);
  if (![10, 11, 12].includes(grade)) return json({ success: false, error: 'unsupported_class' }, 403);
  if (!(context.subjects as Array<{name?: string}>).some((s) => s.name?.toLowerCase() === subject.toLowerCase())) {
    return json({ success: false, error: 'subject_not_enrolled' }, 403);
  }

  const encoder = new TextEncoder();
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(question));
  const questionHash = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
  const { data: reservation, error: reserveError } = await client.rpc('begin_student_ai_request', {
    p_idempotency_key: key,
    p_question_hash: questionHash,
  });
  if (reserveError || !reservation) return json({ success: false, error: 'usage_reservation_failed' }, 503);
  if (reservation.success !== true) {
    if (reservation.error === 'usage_limit_reached') return json({ success: false, error: 'usage_limit_reached', remaining: 0, reset_period: reservation.reset_period }, 429);
    return json({ success: false, error: reservation.error ?? 'request_in_progress' }, 409);
  }
  if (reservation.cached === true) return json({ success: true, ...reservation.answer as Record<string, unknown>, cached: true });

  let successDelivered = false;
  try {
    if (!providerConfig()) {
      await finish(client, key, false, null, startedAt);
      return json({ success: false, error: 'ai_provider_unavailable', retryable: true }, 503);
    }
    const embedding = await embedQuery(question);
    const { data: hits, error: retrievalError } = await client.rpc('match_curriculum_chunks', {
      p_class_grade: grade,
      p_subject: subject,
      p_query: `[${embedding.join(',')}]`,
      p_limit: 6,
    });
    if (retrievalError || !Array.isArray(hits)) {
      await finish(client, key, false, null, startedAt);
      return json({ success: false, error: 'retrieval_unavailable', retryable: true }, 503);
    }

    const evidence = (hits as Array<Record<string, unknown>>)
      .filter((h) => typeof h.content === 'string' && h.content.trim().length > 0)
      .slice(0, 6);
    const bestScore = evidence.reduce((score, hit) => Math.max(score, Number(hit.similarity) || 0), 0);
    if (evidence.length === 0 || bestScore < 0.55) {
      const answer = {
        answer: 'I can’t verify this from the approved learning materials currently available for your class and subject. You can retry later or send this question to your teacher.',
        uncertain: true,
        citations: [],
        teacher_help_available: true,
      };
      await finish(client, key, true, answer, startedAt);
      successDelivered = true;
      return json({ success: true, ...answer, remaining: reservation.remaining, reset_period: reservation.reset_period });
    }

    let raw: string;
    try {
      raw = await generateGroundedAnswer({
        grade,
        subject,
        question,
        passages: evidence.map((h) => ({
          content: String(h.content).slice(0, 6000),
          source_title: String(h.source_title ?? ''),
          document_identifier: String(h.document_identifier ?? ''),
          chapter: typeof h.chapter === 'string' ? h.chapter : null,
          topic: typeof h.topic === 'string' ? h.topic : null,
          page_number: typeof h.page_number === 'number' ? h.page_number : null,
          section: typeof h.section === 'string' ? h.section : null,
        })),
        maxTokens: 800,
      });
    } catch (error) {
      await finish(client, key, false, null, startedAt);
      if (error instanceof LearningProviderError && error.code === 'not_configured') return json({ success: false, error: 'ai_provider_unavailable', retryable: true }, 503);
      return json({ success: false, error: 'ai_provider_error', retryable: true }, 502);
    }

    let parsed: { answer?: unknown; citations?: unknown; uncertain?: unknown };
    try { parsed = JSON.parse(raw); } catch {
      await finish(client, key, false, null, startedAt);
      return json({ success: false, error: 'invalid_ai_response', retryable: true }, 502);
    }
    if (typeof parsed.answer !== 'string' || parsed.answer.length > 6000 || !Array.isArray(parsed.citations)) {
      await finish(client, key, false, null, startedAt);
      return json({ success: false, error: 'invalid_ai_response', retryable: true }, 502);
    }
    const citedIndexes = [...new Set(parsed.citations.filter((n): n is number => Number.isInteger(n) && n >= 1 && n <= evidence.length))];
    const uncertain = parsed.uncertain === true || parsed.answer.trim() === 'INSUFFICIENT_EVIDENCE' || citedIndexes.length === 0;
    const citations = uncertain ? [] : citedIndexes.map((n) => {
      const h = evidence[n - 1];
      return {
        source_title: h.source_title,
        document_identifier: h.document_identifier,
        chapter: h.chapter,
        topic: h.topic,
        page_number: h.page_number,
        section: h.section,
      };
    });
    const answer = uncertain
      ? { answer: 'I can’t verify this from the approved learning materials available for your class and subject. Please retry or ask your teacher.', uncertain: true, citations: [], teacher_help_available: true }
      : { answer: parsed.answer.trim(), uncertain: false, citations, teacher_help_available: true };
    await finish(client, key, true, answer, startedAt);
    successDelivered = true;
    return json({ success: true, ...answer, remaining: reservation.remaining, reset_period: reservation.reset_period });
  } catch (error) {
    console.error('curriculum-rag failed:', error instanceof LearningProviderError ? error.code : 'internal_error');
    if (!successDelivered) await finish(client, key, false, null, startedAt);
    return json({ success: false, error: 'learning_assistant_unavailable', retryable: true }, 503);
  }
});

async function finish(client: ReturnType<typeof createClient>, key: string, ok: boolean, answer: Record<string, unknown> | null, startedAt: number) {
  const { error } = await client.rpc('finish_student_ai_request', {
    p_idempotency_key: key,
    p_success: ok,
    p_answer: answer,
    p_latency_ms: Date.now() - startedAt,
  });
  if (error) console.error('AI usage finalization failed');
}
