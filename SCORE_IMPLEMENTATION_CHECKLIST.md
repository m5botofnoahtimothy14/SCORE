# SCORE+ Production Todo List

## ✅ COMPLETED
- [x] Fix send-otp UUID type mismatch
- [x] Fix verify-otp UUID type mismatch + RPC params
- [x] Fix activate-student dual-code + return email
- [x] Fix activate-teacher dual-code + return email
- [x] Create migration 00034 (schema repair)
- [x] Create migration 00035 (enable extensions)
- [x] Create migration 00036 (SLT read access)
- [x] Create migration 00037 (auto-enroll subjects)
- [x] Create migration 00038 (create student_subject_enrollments)
- [x] Create migration 00039 (create curriculum tables)
- [x] Create migration 00040 (create RAG RPCs)
- [x] Create migration 00041 (password system)
- [x] Fix doubt_conversation_screen (messages table)
- [x] Fix SLT dashboard (independent error handling)
- [x] Fix subject picker (default Chemistry/Physics/Biology)
- [x] Fix AI Ask (fallback to general knowledge)
- [x] Fix back arrow (canPop check)
- [x] Fix crash prevention (global error handler)
- [x] Fix home screen (tier enum vs string)
- [x] Fix book_session mentor loading (try/catch)
- [x] Fix doubt submission (attachment support)
- [x] Fix identity provider (read from user_profiles)
- [x] Apply all migrations to production DB
- [x] Set all Edge Function secrets
- [x] Enable extensions (pg_net, pg_cron, vector)
- [x] Deploy all edge functions
- [x] Build release APK
- [x] Install APK on phone
- [x] Website deployed to teachcross-admin.vercel.app
- [x] GitHub pushed
- [x] Admin app builds successfully
- [x] Premium UI redesign (navy/electric blue/cyan)
- [x] Light/dark mode support (ThemeMode.system)
- [x] Remove AI Ask from app (moved to website)
- [x] Add AI Manager to website
- [x] Add chat history section to website
- [x] Add meeting history section to website

## 🔄 IN PROGRESS
- [ ] Password system (migration applied, need mobile + admin implementation)

## ❌ NOT STARTED
- [ ] Google refresh token (needs OAuth flow - user said "figure out later")
- [ ] Curriculum ingestion (needs source URLs)
- [ ] Password creation screen after activation
- [ ] Password-based login screen
- [ ] Admin website password view/reset UI
- [ ] Push notifications end-to-end test
- [ ] Full workflow validation on device

## 📋 PRIORITY ORDER
1. Password system (mobile app) - HIGH
2. Password system (admin website) - HIGH
3. Google refresh token - MEDIUM (user said "later")
4. Curriculum ingestion - LOW (AI works without it)