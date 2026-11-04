# ============================================================
# SCORE+ Curriculum Ingestion — Grades 6-12
# ============================================================
# Populates Supabase tables:
#   curriculum_documents (approved source material)
#   curriculum_chunks (chunked text + vector embeddings)
#
# These tables are created by migration 00023 (learning_quotas_rag.sql).
#
# Prerequisites:
#   pip install supabase openai requests beautifulsoup4 python-dotenv
#   Supabase extensions: vector
#   Edge Function env: LEARNING_AI_API_KEY, LEARNING_AI_BASE_URL,
#                       LEARNING_AI_EMBEDDING_MODEL
#
# Run: python ingest_curriculum.py
# ============================================================

import os
import json
import hashlib
import time
from typing import List, Dict, Optional
from supabase import create_client, Client
from openai import OpenAI
from bs4 import BeautifulSoup
import requests
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
OPENAI_API_KEY = os.getenv("LEARNING_AI_API_KEY")
EMBEDDING_MODEL = os.getenv("LEARNING_AI_EMBEDDING_MODEL", "text-embedding-3-large")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
openai = OpenAI(api_key=OPENAI_API_KEY)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CURRICULUM SOURCES (Grades 6-12)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Add URLs to official curriculum sources (NCERT, state boards, etc.)
# Each entry: grade, subject, chapter, topic, source_title, source_url, url
CURRICULUM_SOURCES = [
    # Example structure — populate with actual URLs:
    # {
    #   "class_grade": 10,
    #   "subject": "Physics",
    #   "chapter": "Light – Reflection and Refraction",
    #   "topic": "Reflection of Light",
    #   "source_title": "NCERT Class 10 Science",
    #   "source_url": "https://ncert.nic.in/",
    #   "url": "https://example.com/ncert/class10/physics/light-reflection",
    #   "document_identifier": "NCERT-CLASS-10-PHYSICS-CH10",
    #   "license_name": "NCERT",
    #   "license_url": "https://ncert.nic.in/",
    #   "academic_year": "2025-26",
    #   "content_version": 1,
    # },
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TEXT EXTRACTION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def fetch_page_text(url: str) -> Optional[str]:
    """Fetch and extract readable text from a webpage."""
    try:
        headers = {"User-Agent": "Mozilla/5.0 (compatible; SCORE+ Curriculum Bot/1.0)"}
        resp = requests.get(url, headers=headers, timeout=30)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")
        # Remove script/style elements
        for tag in soup(["script", "style", "nav", "footer", "header", "aside"]):
            tag.decompose()
        text = soup.get_text(separator="\n", strip=True)
        return text
    except Exception as e:
        print(f"  ⚠️  Failed to fetch {url}: {e}")
        return None


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CHUNKING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def chunk_text(text: str, max_chars: int = 1500, overlap: int = 200) -> List[str]:
    """Split text into overlapping chunks for embedding."""
    if not text:
        return []
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end >= len(text):
            break
        start = end - overlap
    return chunks


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# EMBEDDING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def get_embedding(text: str) -> Optional[List[float]]:
    """Generate embedding vector for a text chunk."""
    try:
        resp = openai.embeddings.create(
            model=EMBEDDING_MODEL,
            input=text,
        )
        return resp.data[0].embedding
    except Exception as e:
        print(f"  ⚠️  Embedding failed: {e}")
        return None


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DATABASE OPERATIONS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def insert_document(doc: Dict) -> Optional[str]:
    """Insert a curriculum document and return its UUID."""
    try:
        result = supabase.table("curriculum_documents").insert(doc).execute()
        if result.data:
            return result.data[0]["id"]
    except Exception as e:
        print(f"  ⚠️  Document insert failed: {e}")
    return None


def insert_chunk(doc_id: str, chunk_index: int, content: str,
                 embedding: List[float], page_number: Optional[int] = None,
                 section: Optional[str] = None) -> bool:
    """Insert a curriculum chunk with its embedding."""
    try:
        content_hash = hashlib.sha256(content.encode()).hexdigest()
        supabase.table("curriculum_chunks").insert({
            "document_id": doc_id,
            "chunk_index": chunk_index,
            "content": content,
            "content_hash": content_hash,
            "embedding": embedding,
            "page_number": page_number,
            "section": section,
        }).execute()
        return True
    except Exception as e:
        print(f"  ⚠️  Chunk insert failed: {e}")
    return False


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MAIN INGESTION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def ingest_source(source: Dict) -> bool:
    """Ingest a single curriculum source."""
    print(f"\n📚 Ingesting: {source['source_title']} — {source['chapter']} ({source['subject']}, Grade {source['class_grade']})")

    text = fetch_page_text(source["url"])
    if not text:
        return False

    chunks = chunk_text(text)
    print(f"  📝 Extracted {len(text)} chars → {len(chunks)} chunks")

    # Insert document
    doc = {
        "school_id": None,  # school-level (NULL = platform-wide)
        "class_grade": source["class_grade"],
        "subject": source["subject"],
        "chapter": source.get("chapter"),
        "topic": source.get("topic"),
        "source_title": source["source_title"],
        "source_url": source["source_url"],
        "document_identifier": source["document_identifier"],
        "license_name": source.get("license_name", "Unknown"),
        "license_url": source.get("license_url", ""),
        "academic_year": source.get("academic_year", "2025-26"),
        "content_version": source.get("content_version", 1),
        "approval_status": "pending",  # must be approved before RAG uses it
    }
    doc_id = insert_document(doc)
    if not doc_id:
        return False

    # Insert chunks with embeddings
    for i, chunk in enumerate(chunks):
        embedding = get_embedding(chunk)
        if not embedding:
            continue
        insert_chunk(
            doc_id=doc_id,
            chunk_index=i,
            content=chunk,
            embedding=embedding,
            page_number=None,
            section=source.get("topic"),
        )
        time.sleep(0.2)  # rate limiting

    print(f"  ✅ Inserted {len(chunks)} chunks (document ID: {doc_id})")
    return True


def main():
    if not CURRICULUM_SOURCES:
        print("⚠️  No curriculum sources configured. Edit CURRICULUM_SOURCES in this script.")
        return

    print(f"🚀 Starting curriculum ingestion: {len(CURRICULUM_SOURCES)} sources")
    success = 0
    for source in CURRICULUM_SOURCES:
        if ingest_source(source):
            success += 1
    print(f"\n✅ Ingestion complete: {success}/{len(CURRICULUM_SOURCES)} sources imported")
    print("\n📋 Next step: Approve documents via the approve_curriculum_document RPC")
    print("   Example SQL:")
    print("   SELECT public.approve_curriculum_document('<document-uuid>', true);")


if __name__ == "__main__":
    main()
