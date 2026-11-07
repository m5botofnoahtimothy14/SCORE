import re
with open('ingest_curriculum.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace all non-ASCII print statements
content = content.replace('??  Content generation failed', '[WARN] Content generation failed')
content = content.replace('??  Embedding failed', '[WARN] Embedding failed')
content = content.replace('??  Document insert failed', '[WARN] Document insert failed')
content = content.replace('??  Chunk insert failed', '[WARN] Chunk insert failed')
content = content.replace('?? {len(content)} chars', '[CHUNKS] {len(content)} chars')
content = content.replace('? {success_count}/{len(chunks)} chunks inserted', '[OK] {success_count}/{len(chunks)} chunks inserted')
content = content.replace('?? Starting curriculum ingestion', '[START] Starting curriculum ingestion')
content = content.replace('? Ingestion complete', '[DONE] Ingestion complete')

with open('ingest_curriculum.py', 'w', encoding='utf-8') as f:
    f.write(content)
print('Fixed!')