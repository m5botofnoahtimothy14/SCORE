'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader, Card, LoadingState, ErrorState, EmptyState, inputCls } from '@/components/ui'

interface Conversation {
  id: string
  type: string
  title: string | null
  school_id: string
  created_at: string
  updated_at: string
  members: { user_id: string; role: string; display_name?: string }[]
  message_count: number
  last_message?: string
}

export default function ConversationsPage() {
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in.')
      const { data: membership } = await supabase
        .from('school_memberships').select('school_id')
        .eq('user_id', user.id).eq('is_active', true).limit(1).maybeSingle()
      const schoolId = (membership as { school_id: string } | null)?.school_id
      if (!schoolId) throw new Error('No school scope.')

      const { data: convs, error: cErr } = await supabase
        .from('conversations')
        .select('id, type, title, school_id, created_at, updated_at')
        .eq('school_id', schoolId)
        .order('updated_at', { ascending: false })
        .limit(200)
      if (cErr) throw cErr

      // Get member info and message counts for each conversation
      const convList: Conversation[] = []
      for (const c of (convs ?? []) as { id: string; type: string; title: string | null; school_id: string; created_at: string; updated_at: string }[]) {
        const { data: members } = await supabase
          .from('conversation_members')
          .select('user_id, role, user_profiles(display_name)')
          .eq('conversation_id', c.id)
        const { data: msgs } = await supabase
          .from('messages')
          .select('body, created_at')
          .eq('conversation_id', c.id)
          .order('created_at', { ascending: false })
          .limit(1)
        const memberList = ((members ?? []) as unknown as { user_id: string; role: string; user_profiles: { display_name: string }[] | { display_name: string } | null }[]).map((m) => ({
          user_id: m.user_id,
          role: m.role,
          display_name: Array.isArray(m.user_profiles) ? m.user_profiles[0]?.display_name : m.user_profiles?.display_name,
        }))
        convList.push({
          ...c,
          members: memberList,
          message_count: 0,
          last_message: (msgs as { body: string }[] | null)?.[0]?.body ?? undefined,
        })
      }
      setConversations(convList)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load conversations.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const filtered = useMemo(() => {
    const q = query.toLowerCase()
    return conversations.filter((c) =>
      !q || (c.title ?? '').toLowerCase().includes(q) ||
      c.members.some((m) => (m.display_name ?? '').toLowerCase().includes(q))
    )
  }, [conversations, query])

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={load} />

  return (
    <div>
      <PageHeader
        title="Chat History"
        subtitle={`${filtered.length} of ${conversations.length} conversations`}
        action={<input className="inputCls" style={{ maxWidth: 260 }} placeholder="Search conversations..." value={query} onChange={(e) => setQuery(e.target.value)} />}
      />
      {filtered.length === 0 ? <EmptyState title="No conversations found" subtitle="Conversations will appear here when students and teachers start chatting." /> : (
        <div className="space-y-3">
          {filtered.map((c) => (
            <div key={c.id} className="card bg-white rounded-2xl p-4 border border-slate-200 shadow-sm">
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-slate-900">{c.title || 'Conversation'}</span>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-blue-50 text-blue-600 font-medium">{c.type}</span>
                </div>
                <span className="text-xs text-slate-400">{new Date(c.updated_at).toLocaleDateString()}</span>
              </div>
              <div className="text-sm text-slate-500 mb-2">
                {c.members.map((m) => m.display_name || m.user_id.slice(0, 8)).join(', ')}
              </div>
              {c.last_message && (
                <div className="text-sm text-slate-600 bg-slate-50 rounded-lg p-2 truncate">
                  {c.last_message}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}