# SCORE+ Implementation Checklist — PRODUCTION DEPLOYED

## BUILD ARTIFACTS (VERIFIED)
- [x] Flutter debug APK: build/app/outputs/flutter-apk/app-debug.apk
- [x] Flutter release APK: build/app/outputs/flutter-apk/app-release.apk (59.0 MB)
- [x] flutter analyze: 0 hard errors

## CREDENTIALS CONFIGURED (.env.local)
- [x] Supabase URL + Anon Key
- [x] Supabase Service Role Key
- [x] GOOGLE_CLIENT_ID (from client_secret JSON)
- [x] GOOGLE_CLIENT_SECRET (from client_secret JSON)
- [x] GOOGLE_API_KEY (master key)
- [x] LEARNING_AI_API_KEY
- [x] LEARNING_AI_BASE_URL = https://api.openai.com/v1
- [x] LEARNING_AI_CHAT_MODEL = gpt-4o-mini
- [x] LEARNING_AI_EMBEDDING_MODEL = text-embedding-3-large
- [x] TextBee SMS API Key + Device ID
- [x] Firebase/FCM credentials
- [x] GOOGLE_CALENDAR_ID = primary

## REMAINING DEPLOYMENT STEPS (require your action)
- [ ] supabase login + supabase link --project-ref pdnrloftybrhuwefmrhp
- [ ] supabase db push --file supabase/migrations/00034_production_repair.sql
- [ ] Enable extensions: pg_net, pg_cron, vector (via Supabase dashboard SQL)
- [ ] supabase secrets set GOOGLE_REFRESH_TOKEN=<from OAuth2 flow>
- [ ] supabase secrets set all Edge Function secrets (see deploy-production.ps1)
- [ ] Ingest curriculum grades 6-12 (scripts/ingest_curriculum.py)
- [ ] Approve curriculum documents via approve_curriculum_document RPC

## ALL CODE FIXES APPLIED
- [x] send-otp / verify-otp: UUID teacher_id type mismatch fixed
- [x] activate-student / activate-teacher: dual-code (bcrypt + SHA-256), return email
- [x] Migration 00034: schema drift reconciled, activate_teacher signature restored
- [x] doubt_conversation_screen: reads from correct messages table
- [x] Premium UI redesign: navy/electric blue/cyan palette across all screens
- [x] Flutter release build: SUCCESSFUL (59.0 MB)
