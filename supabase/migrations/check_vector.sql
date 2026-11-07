CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
SELECT extname, extnamespace::regnamespace FROM pg_extension WHERE extname = 'vector';