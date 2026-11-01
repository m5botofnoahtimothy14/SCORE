import Link from 'next/link'
import {
  ArrowRight,
  ArrowUpRight,
  BookOpenCheck,
  BrainCircuit,
  CalendarClock,
  CheckCircle2,
  GraduationCap,
  LockKeyhole,
  MessageCircleQuestion,
  MonitorSmartphone,
  School,
  ShieldCheck,
  Users,
} from 'lucide-react'

const audiences = [
  {
    icon: GraduationCap,
    title: 'Students',
    description: 'Access school notices, ask curriculum questions and request support from teachers.',
    points: ['Curriculum-grounded AI learning support', 'Mentor Desk doubt requests', 'School announcements in one place'],
  },
  {
    icon: Users,
    title: 'Teachers',
    description: 'Manage student support requests, mentor sessions and school communication.',
    points: ['Organised doubt queue', 'Session availability controls', 'Announcements and follow-up'],
  },
  {
    icon: School,
    title: 'School leadership',
    description: 'Coordinate school operations through a role-based administration workspace.',
    points: ['Student and staff administration', 'Mentor Desk oversight', 'Audit and operational visibility'],
  },
]

const features = [
  {
    icon: BrainCircuit,
    title: 'Curriculum-aware AI',
    description: 'AI Ask is designed to ground learning support in approved curriculum material and show relevant sources.',
  },
  {
    icon: MessageCircleQuestion,
    title: 'Mentor Desk',
    description: 'A structured workflow for student doubts, teacher responses, booked sessions and feedback.',
  },
  {
    icon: CalendarClock,
    title: 'Managed sessions',
    description: 'Session booking and teacher availability tools support a clear, accountable support process.',
  },
  {
    icon: ShieldCheck,
    title: 'Role-based access',
    description: 'Student, teacher and leadership experiences use account roles and school membership permissions.',
  },
  {
    icon: BookOpenCheck,
    title: 'School communication',
    description: 'Announcements and notices help keep school communities informed through one platform.',
  },
  {
    icon: LockKeyhole,
    title: 'Security-conscious design',
    description: 'Server-side checks, access policies and audit workflows form part of the platform architecture.',
  },
]

export default function PublicHomePage() {
  return (
    <main className="min-h-screen overflow-hidden bg-white text-ink-950">
      <header className="relative z-20 border-b border-ink-200/70 bg-white/90 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-5 py-4 sm:px-8">
          <Link href="/" className="flex items-center gap-3" aria-label="SCORE+ home">
            <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-gradient text-sm font-extrabold text-white shadow-glow">S+</span>
            <span>
              <span className="block text-base font-extrabold tracking-tight text-ink-950">SCORE+</span>
              <span className="block text-[10px] font-semibold uppercase tracking-[0.16em] text-ink-400">Learn · Connect · Grow</span>
            </span>
          </Link>
          <nav className="hidden items-center gap-8 text-sm font-medium text-ink-600 md:flex" aria-label="Main navigation">
            <a href="#platform" className="transition-colors hover:text-brand-600">Platform</a>
            <a href="#audiences" className="transition-colors hover:text-brand-600">Who it serves</a>
            <a href="#security" className="transition-colors hover:text-brand-600">Trust</a>
          </nav>
          <Link href="/auth/login" className="btn-primary px-4 py-2.5">
            Admin portal <ArrowUpRight className="h-4 w-4" />
          </Link>
        </div>
      </header>

      <section className="relative isolate">
        <div aria-hidden className="absolute inset-0 bg-grid opacity-70" />
        <div aria-hidden className="absolute -right-40 -top-36 h-[34rem] w-[34rem] rounded-full bg-brand-100/70 blur-3xl" />
        <div className="relative mx-auto grid max-w-7xl items-center gap-14 px-5 py-20 sm:px-8 lg:grid-cols-[1.05fr_0.95fr] lg:py-28">
          <div className="max-w-2xl">
            <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-brand-200 bg-brand-50 px-3 py-1.5 text-xs font-semibold text-brand-700">
              <span className="h-1.5 w-1.5 rounded-full bg-brand-500" />
              One connected school experience
            </div>
            <h1 className="text-balance text-4xl font-extrabold leading-[1.08] tracking-[-0.045em] text-ink-950 sm:text-5xl lg:text-6xl">
              Better school support.
              <span className="block text-brand-600">One connected platform.</span>
            </h1>
            <p className="mt-6 max-w-xl text-base leading-7 text-ink-600 sm:text-lg">
              SCORE+ brings learning support, school communication and mentor workflows into one role-based experience for students, teachers and school leaders.
            </p>
            <div className="mt-9 flex flex-col gap-3 sm:flex-row">
              <Link href="/auth/login" className="btn-primary min-h-12 px-6">
                Open administration portal <ArrowRight className="h-4 w-4" />
              </Link>
              <a href="#platform" className="btn-secondary min-h-12 px-6">Explore the platform</a>
            </div>
            <div className="mt-9 flex flex-wrap items-center gap-x-6 gap-y-3 text-xs font-medium text-ink-500">
              <span className="inline-flex items-center gap-2"><CheckCircle2 className="h-4 w-4 text-emerald-600" /> Student-first workflows</span>
              <span className="inline-flex items-center gap-2"><CheckCircle2 className="h-4 w-4 text-emerald-600" /> Role-aware experiences</span>
            </div>
          </div>

          <div className="relative mx-auto w-full max-w-xl">
            <div aria-hidden className="absolute -inset-5 rounded-[2rem] bg-brand-100/70 blur-2xl" />
            <div className="relative overflow-hidden rounded-[1.7rem] border border-ink-200 bg-white p-3 shadow-lift">
              <div className="rounded-[1.25rem] bg-ink-950 p-5 text-white sm:p-7">
                <div className="flex items-center justify-between border-b border-white/10 pb-5">
                  <div className="flex items-center gap-3">
                    <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-500 text-xs font-extrabold">S+</span>
                    <div>
                      <p className="text-sm font-bold">SCORE+ Workspace</p>
                      <p className="text-[11px] text-slate-400">A connected school experience</p>
                    </div>
                  </div>
                  <span className="rounded-full border border-emerald-400/20 bg-emerald-400/10 px-2.5 py-1 text-[10px] font-semibold text-emerald-300">Role-based</span>
                </div>
                <div className="grid grid-cols-2 gap-3 pt-5">
                  {[
                    { icon: BrainCircuit, label: 'AI Ask', detail: 'Learning support', color: 'bg-blue-400/15 text-blue-200' },
                    { icon: MessageCircleQuestion, label: 'Mentor Desk', detail: 'Student support', color: 'bg-emerald-400/15 text-emerald-200' },
                    { icon: CalendarClock, label: 'Sessions', detail: 'Managed bookings', color: 'bg-violet-400/15 text-violet-200' },
                    { icon: School, label: 'School updates', detail: 'Notices and news', color: 'bg-amber-400/15 text-amber-200' },
                  ].map((item) => (
                    <div key={item.label} className="rounded-2xl border border-white/10 bg-white/[0.045] p-4">
                      <span className={`mb-5 flex h-9 w-9 items-center justify-center rounded-xl ${item.color}`}>
                        <item.icon className="h-4 w-4" />
                      </span>
                      <p className="text-sm font-semibold">{item.label}</p>
                      <p className="mt-1 text-[11px] text-slate-400">{item.detail}</p>
                    </div>
                  ))}
                </div>
                <div className="mt-4 rounded-2xl border border-white/10 bg-white/[0.045] p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-slate-200">Built around school roles</span>
                    <MonitorSmartphone className="h-4 w-4 text-brand-300" />
                  </div>
                  <div className="mt-3 flex gap-2">
                    <span className="rounded-lg bg-white/10 px-3 py-2 text-[10px] font-semibold text-slate-200">Student</span>
                    <span className="rounded-lg bg-white/10 px-3 py-2 text-[10px] font-semibold text-slate-200">Teacher</span>
                    <span className="rounded-lg bg-white/10 px-3 py-2 text-[10px] font-semibold text-slate-200">Leadership</span>
                  </div>
                </div>
              </div>
            </div>
            <p className="relative mt-4 text-center text-[11px] text-ink-400">Illustrative platform preview. Features depend on account access and deployment configuration.</p>
          </div>
        </div>
      </section>

      <section id="platform" className="border-y border-ink-200/70 bg-surface py-20">
        <div className="mx-auto max-w-7xl px-5 sm:px-8">
          <div className="max-w-2xl">
            <p className="eyebrow">The platform</p>
            <h2 className="mt-3 text-3xl font-extrabold tracking-tight text-ink-950 sm:text-4xl">The tools schools need. In one place.</h2>
            <p className="mt-4 text-base leading-7 text-ink-600">SCORE+ connects student learning support with the people and processes that keep a school community moving.</p>
          </div>
          <div className="mt-11 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {features.map((feature) => (
              <article key={feature.title} className="surface-card bg-white p-6 transition-all duration-200 hover:-translate-y-1 hover:shadow-lift">
                <span className="mb-5 flex h-11 w-11 items-center justify-center rounded-xl bg-brand-50 text-brand-600 ring-1 ring-inset ring-brand-100">
                  <feature.icon className="h-5 w-5" />
                </span>
                <h3 className="text-base font-bold text-ink-900">{feature.title}</h3>
                <p className="mt-2 text-sm leading-6 text-ink-500">{feature.description}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section id="audiences" className="py-20">
        <div className="mx-auto max-w-7xl px-5 sm:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <p className="eyebrow">Designed for the whole school</p>
            <h2 className="mt-3 text-3xl font-extrabold tracking-tight text-ink-950 sm:text-4xl">One platform. Three connected experiences.</h2>
            <p className="mt-4 text-base leading-7 text-ink-600">Each role sees the tools and workflows that match its responsibilities.</p>
          </div>
          <div className="mt-12 grid gap-5 lg:grid-cols-3">
            {audiences.map((audience, index) => (
              <article key={audience.title} className="rounded-2xl border border-ink-200 bg-white p-7 shadow-card">
                <div className="flex items-center justify-between">
                  <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-brand-50 text-brand-600">
                    <audience.icon className="h-6 w-6" />
                  </span>
                  <span className="text-xs font-bold text-ink-300">0{index + 1}</span>
                </div>
                <h3 className="mt-6 text-xl font-bold text-ink-950">{audience.title}</h3>
                <p className="mt-2 min-h-[72px] text-sm leading-6 text-ink-500">{audience.description}</p>
                <ul className="mt-5 space-y-3 border-t border-ink-100 pt-5">
                  {audience.points.map((point) => (
                    <li key={point} className="flex items-start gap-2.5 text-sm text-ink-600">
                      <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> {point}
                    </li>
                  ))}
                </ul>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section id="security" className="bg-ink-950 py-20 text-white">
        <div className="mx-auto grid max-w-7xl items-center gap-12 px-5 sm:px-8 lg:grid-cols-[1fr_0.8fr]">
          <div>
            <p className="text-[11px] font-bold uppercase tracking-[0.16em] text-brand-300">Trust and governance</p>
            <h2 className="mt-3 max-w-xl text-3xl font-extrabold tracking-tight sm:text-4xl">Access should be clear. Accountability should be built in.</h2>
            <p className="mt-5 max-w-xl text-base leading-7 text-slate-300">SCORE+ is structured around school membership, role-aware access and operational records. Production security still depends on correct deployment, policy configuration and ongoing review.</p>
          </div>
          <div className="grid gap-3">
            {[
              ['Role-aware access', 'Separate student, teacher and leadership workflows.'],
              ['Operational audit trail', 'Keep administrative actions visible to authorised roles.'],
              ['Controlled administration', 'Keep management functions behind administrator sign-in.'],
            ].map(([title, detail]) => (
              <div key={title} className="flex gap-4 rounded-2xl border border-white/10 bg-white/[0.045] p-5">
                <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-brand-300" />
                <div>
                  <p className="text-sm font-bold">{title}</p>
                  <p className="mt-1 text-sm leading-6 text-slate-400">{detail}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="bg-brand-50 py-16">
        <div className="mx-auto flex max-w-7xl flex-col items-start justify-between gap-7 px-5 sm:px-8 md:flex-row md:items-center">
          <div>
            <p className="eyebrow text-brand-700">Get started</p>
            <h2 className="mt-2 text-3xl font-extrabold tracking-tight text-ink-950">Your school workspace starts here.</h2>
            <p className="mt-3 max-w-xl text-sm leading-6 text-ink-600">School administrators can sign in to manage their authorised SCORE+ workspace.</p>
          </div>
          <Link href="/auth/login" className="btn-primary min-h-12 shrink-0 px-6">
            Go to admin sign in <ArrowRight className="h-4 w-4" />
          </Link>
        </div>
      </section>

      <footer className="border-t border-ink-200 bg-white">
        <div className="mx-auto flex max-w-7xl flex-col gap-4 px-5 py-8 text-xs text-ink-500 sm:px-8 md:flex-row md:items-center md:justify-between">
          <div className="flex items-center gap-2">
            <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-ink-950 text-[10px] font-extrabold text-white">S+</span>
            <span className="font-semibold text-ink-700">SCORE+ · Learn · Connect · Grow</span>
          </div>
          <div className="flex flex-wrap items-center gap-5">
            <Link href="/auth/login" className="hover:text-brand-600">Admin portal</Link>
            <span>© {new Date().getFullYear()} SCORE+. All rights reserved.</span>
          </div>
        </div>
      </footer>
    </main>
  )
}
