import type { SupabaseClient } from '@supabase/supabase-js'

interface AuditInput {
  schoolId?: string | null
  action: string
  targetType?: string
  targetId?: string
  outcome: 'success' | 'failure' | 'rejected'
  reason?: string
  metadata?: Record<string, unknown>
}

// Every privileged mutation funnels through here so the audit trail is
// complete. Callers pass the actor implicitly via actorId.
export async function logAudit(
  supabase: SupabaseClient,
  actorId: string,
  input: AuditInput
): Promise<void> {
  const { error } = await supabase.from('audit_events').insert({
    school_id: input.schoolId ?? null,
    actor_id: actorId,
    action: input.action,
    target_type: input.targetType ?? null,
    target_id: input.targetId ?? null,
    outcome: input.outcome,
    reason: input.reason ?? null,
    metadata: input.metadata ?? {},
  })
  if (error) {
    // Audit failure must be visible, never silent.
    console.error('AUDIT WRITE FAILED:', input.action, error.message)
    throw new Error(`Audit write failed for ${input.action}: ${error.message}`)
  }
}
