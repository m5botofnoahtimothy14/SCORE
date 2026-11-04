# ============================================================
# SCORE+ Production Deployment Script
# ============================================================
# Run from: D:\Teachcross APP
# ============================================================

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PREREQUISITES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. Install Flutter: https://docs.flutter.dev/get-started/install
# 2. Install Supabase CLI: https://supabase.com/docs/guides/cli
# 3. Install Google Cloud SDK: https://cloud.google.com/sdk/docs/install
# 4. Login to Supabase: supabase login
# 5. Link your project: supabase link --project-ref pdnrloftybrhuwefmrhp

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 1: APPLY MIGRATION 00034 (production repair — idempotent, no drops)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# supabase db push --file supabase/migrations/00034_production_repair.sql

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 2: ENABLE SUPABASE EXTENSIONS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Run these via Supabase dashboard SQL editor or psql:
#   CREATE EXTENSION IF NOT EXISTS pg_net;
#   CREATE EXTENSION IF NOT EXISTS pg_cron;
#   CREATE EXTENSION IF NOT EXISTS vector;

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 3: SET SUPABASE EDGE FUNCTION SECRETS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Run each of these (replace placeholders with actual values from .env.local):

supabase secrets set SUPABASE_URL=https://pdnrloftybrhuwefmrhp.supabase.co
supabase secrets set SUPABASE_ANON_KEY=<from-env-local>
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<from-env-local>
supabase secrets set TEXTBEE_API_KEY=<from-env-local
supabase secrets set TEXTBEE_DEVICE_ID=6ad3707710b63ade60348d0e
supabase secrets set GOOGLE_CLIENT_ID=<from-env-local>
supabase secrets set GOOGLE_CLIENT_SECRET=<from-env-local>
supabase secrets set GOOGLE_CALENDAR_ID=primary
supabase secrets set GOOGLE_REFRESH_TOKEN=<obtain-via-oauth2-below>
supabase secrets set LEARNING_AI_API_KEY=<from-env-local>
supabase secrets set LEARNING_AI_BASE_URL=https://api.openai.com/v1
supabase secrets set LEARNING_AI_CHAT_MODEL=gpt-4o-mini
supabase secrets set LEARNING_AI_EMBEDDING_MODEL=text-embedding-3-large

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 4: OBTAIN GOOGLE_REFRESH_TOKEN (OAuth2 via gcloud CLI)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# The create-google-meet Edge Function needs a refresh token to access
# Google Calendar on behalf of the school. Run these commands:

# 4a. Authenticate with Google Cloud
# gcloud auth login

# 4b. Create an OAuth2 client (use the client_secret JSON from Downloads)
# gcloud auth application-default login

# 4c. Generate refresh token for Calendar scope
# Use the client ID/secret from the JSON file:
#   Client ID:    <from-env-local>
#   Client Secret: <from-env-local
#
# Run an OAuth2 flow (e.g., via a script or the Google OAuth Playground):
#   https://developers.google.com/oauthplayground
#   1. Select "Google Calendar API v3" → scope: https://www.googleapis.com/auth/calendar
#   2. Enter your client ID and client secret
#   3. Authorize → get authorization code
#   4. Exchange code for tokens → copy the "refresh token"
#   5. Set it: supabase secrets set GOOGLE_REFRESH_TOKEN=<refresh-token>

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 5: BUILD FLUTTER APK (with production Supabase config)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cd apps/mobile

flutter build apk --release ^
  --dart-define=SUPABASE_URL=https://pdnrloftybrhuwefmrhp.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=<from-env-local>

# Output: build/app/outputs/flutter-apk/app-release.apk

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 6: CURRICULUM INGESTION (Grades 6–12)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# The curriculum_rag Edge Function reads from Supabase tables:
#   curriculum_documents (approved source material)
#   curriculum_chunks (chunked text + vector embeddings)
#
# You need to:
#   1. Collect curriculum source documents for grades 6-12
#      (Physics, Chemistry, Biology, Mathematics — CBSE or your board)
#   2. Run the ingestion pipeline (see scripts/ingest-curriculum.md)
#   3. Approve documents via approve_curriculum_document RPC
#
# Without ingested + approved documents, AI Ask returns:
#   "I can't verify this from the approved learning materials"
#
# The database tables already exist (migration 00023). You just need to
# populate curriculum_documents + curriculum_chunks with embeddings.

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 7: VERIFY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   flutter analyze          # should show 0 errors
#   supabase secrets list    # verify all secrets are set
#   supabase functions list  # verify all 12 edge functions deployed
