@echo off
cd /d "D:\Teachcross APP\apps\mobile"
flutter build apk --release --dart-define=SUPABASE_URL=https://pdnrloftybrhuwefmrhp.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBkbnJsb2Z0eWJyaHV3ZWZtcmhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNTU4NjAsImV4cCI6MjEwNzczMTg2MH0.nOggil9woLHuDbiLyk_HPXH1BF-CuDR2EL1pjtgU-S8 --dart-define=FIREBASE_API_KEY=AIzaSyCtE6cWXQ9xZA0kNY1vp3-V_YwaEbV7szM --dart-define=FIREBASE_APP_ID=1:587525976197:android:a3bb2a844c3e8998d179ec --dart-define=FIREBASE_SENDER_ID=587525976197 --dart-define=FIREBASE_PROJECT_ID=teachcross-38f29
echo EXIT: %ERRORLEVEL%
