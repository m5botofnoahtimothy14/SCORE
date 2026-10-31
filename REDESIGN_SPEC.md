# TeachCross Complete Redesign Specification

## Overview
Complete redesign of the TeachCross platform for production testing by investors.
All stubs fixed, every API working, every function working, every detail proper.

---

## 1. DATABASE SCHEMA (Supabase Migration 00027-0029)

### Completed Files
- `supabase/migrations/00027_complete_schema_redesign.sql` — Complete schema with all tables
- `supabase/migrations/00028_rls_policies_complete.sql` — Complete RLS policies
- `supabase/migrations/00029_rpcs_complete.sql` — Complete SECURITY DEFINER RPCs

### Key Tables
| Table | Purpose |
|-------|---------|
| schools | Multi-tenant school records |
| school_settings | Per-school config incl. Google Meet settings |
| user_profiles | Extends auth.users |
| school_memberships | User ↔ school with roles |
| academic_years | School academic years |
| subjects | School subjects |
| classes | Classes/sections |
| students | Student roster |
| teachers | Teacher roster |
| class_enrollments | Student-class mappings |
| teaching_assignments | Teacher-class-subject mappings |
| student_activation_credentials | Hashed activation codes |
| staff_activation_records | Hashed OTP codes |
| rate_limit_events | Rate limiting |
| conversations | Threads (mentor_desk type added) |
| conversation_members | Thread participants |
| messages | Messages with moderation |
| attachments | File attachments |
| announcements | School announcements |
| moderation_events | AI moderation results |
| audit_events | Full audit trail |
| background_jobs | Background job queue |
| data_retention_policies | Retention config |
| mentor_desk_settings | Per-school Mentor Desk config |
| mentor_subject_approvals | Teacher subject approvals |
| mentor_availability | Teacher availability |
| doubt_requests | Student doubts with idempotency |
| doubt_status_history | Status change history |
| session_bookings | Sessions with Google Meet fields |
| session_no_shows | No-show records |
| ratings | Student ratings of mentors |
| mentor_assessments | Private mentor assessments |
| allowance_transactions | Session minute ledger |
| urgent_pass_usage | Urgent pass tracking |
| slt_access_grants | SLT access control |
| video_rooms | Video room records |
| video_participant_events | Meeting attendance |
| recording_consents | Consent decisions |
| session_recordings | Session recordings |

### Helper Functions
- `tc_user_school_ids()` — Get user's school IDs
- `tc_is_school_admin(school_id)` — Check admin role
- `tc_week_start(ts, tz)` — Week boundary calculation

### Real-time
- `supabase_realtime` publication includes: messages, doubt_requests, session_bookings, mentor_availability, ratings, announcements, background_jobs

---

## 2. EDGE FUNCTIONS

### Completed Functions
| Function | File | Status |
|----------|------|--------|
| activate-student | `supabase/functions/activate-student/index.ts` | ✅ Complete |
| send-otp | `supabase/functions/send-otp/index.ts` | ✅ Complete |
| verify-otp | `supabase/functions/verify-otp/index.ts` | ✅ Complete |
| publish-announcement | `supabase/functions/publish-announcement/index.ts` | ✅ Complete |
| moderate-message | `supabase/functions/moderate-message/index.ts` | ✅ Complete |
| moderate-image | `supabase/functions/moderate-image/index.ts` | ✅ Complete |
| dispatch-notifications | `supabase/functions/dispatch-notifications/index.ts` | ✅ Complete |
| create-google-meet | `supabase/functions/create-google-meet/index.ts` | ✅ Complete |

### Google Meet Integration
- Uses Google Calendar API v3 with OAuth2 refresh token
- Creates calendar events with `conferenceDataVersion=1` for Meet links
- Idempotent: returns existing link if already created
- Stored in `session_bookings.google_meet_link` and `google_calendar_event_id`
- Environment variables: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`, `GOOGLE_CALENDAR_ID`

### Required Supabase Secrets
```
GOOGLE_CLIENT_ID=1001686491380-baa6sg748h5b6sf5df59qbo67rf28g5g.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=<from Google Cloud Console Web OAuth>
GOOGLE_REFRESH_TOKEN=<from OAuth flow>
GOOGLE_CALENDAR_ID=primary
OPENAI_API_KEY=<from OpenAI>
SUPABASE_SERVICE_ROLE_KEY=<from Supabase>
SUPABASE_ANON_KEY=<from Supabase>
TEXTBEE_API_KEY=<from TextBee>
TEXTBEE_DEVICE_ID=<from TextBee>
FCM_PROJECT_ID=<from Firebase>
FCM_CLIENT_EMAIL=<from Firebase>
FCM_PRIVATE_KEY=<from Firebase>
INTERNAL_WEBHOOK_SECRET=<random string>
```

---

## 3. MOBILE APP (Flutter)

### Architecture
- Flutter 3.47.7, Dart 3.13.5
- Riverpod for state management
- GoRouter for navigation
- Supabase Flutter for backend
- Firebase for push notifications

### Completed Files
| File | Status |
|------|--------|
| `lib/main.dart` | ✅ Complete |
| `lib/core/config/router.dart` | ✅ Complete |
| `lib/core/theme/app_theme.dart` | ✅ Complete |
| `lib/core/providers/identity_provider.dart` | ✅ Complete |
| `lib/features/mentor_desk/screens/mentor_desk_home_screen.dart` | ✅ Complete |
| `lib/features/auth/screens/role_select_screen.dart` | ✅ Complete |
| `lib/features/auth/screens/student_signin_screen.dart` | ✅ Complete |
| `lib/features/auth/screens/teacher_enrollment_screen.dart` | ✅ Existing |

### Auth Flow
1. Splash → EULA → Role Select → Student/Teacher Sign-In → Home
2. Student: Student ID + activation code
3. Teacher: Staff ID + phone → SMS OTP → verify

### Remaining Screens to Build
- `submit_doubt_screen.dart` — Doubt submission with attachments
- `doubt_conversation_screen.dart` — Real-time conversation
- `book_session_screen.dart` — Session booking with Google Meet
- `session_detail_screen.dart` — Session detail with Meet link
- `mentor_queue_screen.dart` — Teacher queue
- `mentor_session_detail_screen.dart` — Mentor session view
- `rating_screen.dart` — Student rating
- `mentor_assessment_screen.dart` — Private mentor assessment

---

## 4. ADMIN DMS (Next.js 14)

### Architecture
- Next.js 14 App Router
- Tailwind CSS
- Supabase SSR
- Server-side auth with RLS

### Completed Files
| File | Status |
|------|--------|
| `app/layout.tsx` | ✅ Complete |
| `app/page.tsx` | ✅ Complete |

### Navigation Structure
- **Super Admin**: All Schools, Administrators, Audit Trail
- **Mentor Desk**: Overview, Doubt Requests, Session Bookings, Mentors, Ratings, Exceptions, Settings
- **Management**: Overview, Students, Teachers, Classes, Announcements, Notifications, Support, Settings

### Remaining Pages to Build
- `app/dashboard/page.tsx` — Overview dashboard
- `app/dashboard/mentor-desk/page.tsx` — Mentor Desk overview
- `app/dashboard/mentor-desk/sessions/page.tsx` — Session bookings with Google Meet
- `app/dashboard/mentor-desk/doubts/page.tsx` — Doubt requests
- `app/dashboard/mentor-desk/mentors/page.tsx` — Mentor management
- `app/dashboard/mentor-desk/ratings/page.tsx` — Feedback & ratings
- `app/dashboard/mentor-desk/exceptions/page.tsx` — Exceptions
- `app/dashboard/mentor-desk/settings/page.tsx` — Mentor Desk settings
- `app/dashboard/students/page.tsx` — Student management
- `app/dashboard/teachers/page.tsx` — Teacher management
- `app/dashboard/classes/page.tsx` — Class management
- `app/dashboard/announcements/page.tsx` — Announcement management
- `app/dashboard/audit/page.tsx` — Audit trail
- `app/dashboard/settings/page.tsx` — System settings

---

## 5. DEPLOYMENT

### Supabase
1. `supabase link --project-ref <ref>`
2. `supabase db push` (applies all migrations)
3. `supabase functions deploy` (deploy all edge functions)
4. `supabase secrets set <vars>` (set all secrets)

### Admin Website (Vercel)
1. Connect GitHub repo or use `vercel --prod`
2. Set environment variables in Vercel dashboard
3. Deploy

### Mobile App
1. `flutter pub get`
2. `flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
3. Install on device

---

## 6. TESTING CHECKLIST

- [ ] Student registration with activation code
- [ ] Teacher registration with OTP
- [ ] Student submits doubt
- [ ] Mentor claims doubt
- [ ] Mentor replies to doubt
- [ ] Mentor resolves doubt
- [ ] Student rates doubt
- [ ] Student books session
- [ ] Mentor confirms session with Google Meet
- [ ] Google Meet link generated
- [ ] Student starts session
- [ ] Student reveals verification code
- [ ] Mentor verifies code
- [ ] Session completed
- [ ] Allowance deduction/refund
- [ ] No-show reporting
- [ ] Admin views all data
- [ ] Admin configures Mentor Desk settings
- [ ] Admin approves mentor subject
- [ ] Real-time updates across devices
- [ ] RLS security (no cross-school access)
- [ ] Rate limiting
- [ ] Moderation pipeline

---

## 7. GOOGLE MEET SETUP

1. Go to Google Cloud Console
2. Enable Google Calendar API
3. Create OAuth 2.0 Client ID (Web application)
4. Get Client ID and Client Secret
5. Generate OAuth refresh token
6. Set as Supabase Edge Function secrets
7. Set `GOOGLE_CALENDAR_ID=primary` (or your calendar ID)

### SHA1 Certificate Fingerprint (for Android)
```
SHA1: E8:F4:F7:5B:09:56:C2:B7:8D:8C:FE:B1:EB:AB:B4:44:E7:59:BF:B3
SHA256: C9:FF:DA:CB:9A:29:F9:E7:17:B4:DD:B0:18:2B:A2:BD:0A:9B:73:BD:01:7A:63:C7:F9:30:5A:9A:E3:35:CF:34
```

---

## 8. ENVIRONMENT VARIABLES

### Supabase Edge Functions
```
GOOGLE_CLIENT_ID=1001686491380-baa6sg748h5b6sf5df59qbo67rf28g5g.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=<web_oauth_client_secret>
GOOGLE_REFRESH_TOKEN=<oauth_refresh_token>
GOOGLE_CALENDAR_ID=primary
OPENAI_API_KEY=<openai_key>
SUPABASE_SERVICE_ROLE_KEY=<service_role_key>
SUPABASE_ANON_KEY=<anon_key>
TEXTBEE_API_KEY=<textbee_key>
TEXTBEE_DEVICE_ID=<textbee_device_id>
FCM_PROJECT_ID=<firebase_project_id>
FCM_CLIENT_EMAIL=<firebase_service_email>
FCM_PRIVATE_KEY=<firebase_private_key>
INTERNAL_WEBHOOK_SECRET=<random_secret>
```

### Admin Website (Vercel)
```
NEXT_PUBLIC_SUPABASE_URL=https://pdnrloftybrhuwefmrhp.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon_key>
SUPABASE_SERVICE_ROLE_KEY=<service_role_key>
SUPABASE_SECRET_KEY_API=<service_role_key_alt>
```

### Mobile App (dart-define)
```
SUPABASE_URL=https://pdnrloftybrhuwefmrhp.supabase.co
SUPABASE_ANON_KEY=<anon_key>
```

---

## 9. REMAINING WORK

### Priority 1 (Critical for Production)
1. Build remaining mobile screens (submit_doubt, doubt_conversation, book_session, session_detail, rating, mentor_queue, mentor_session_detail, mentor_availability, mentor_assessment, slt_dashboard)
2. Build remaining admin pages (overview, sessions, doubts, mentors, ratings, exceptions, settings, students, teachers, classes, announcements, audit, settings)
3. Build admin API routes (/api/health, /api/activation-code)
4. Deploy Supabase migrations and edge functions
5. Configure Google Meet credentials
6. Test end-to-end flows

### Priority 2 (Polish)
1. Add loading states, error handling, empty states to all screens
2. Add real-time subscriptions for messages and bookings
3. Add push notification handling
4. Add image upload and moderation flow
5. Add announcement compose and publish
6. Add admin audit trail view

### Priority 3 (Production Hardening)
1. Add rate limiting middleware
2. Add input validation on all inputs
3. Add CORS configuration
4. Add request logging
5. Add health check endpoints
6. Add backup strategy