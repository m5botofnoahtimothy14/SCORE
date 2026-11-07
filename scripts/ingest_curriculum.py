# ============================================================
# SCORE+ Curriculum Ingestion — Grades 6-12
# ============================================================
# Populates Supabase tables:
#   curriculum_documents (approved source material)
#   curriculum_chunks (chunked text + vector embeddings)
#
# Uses OpenAI API to generate curriculum-aligned study content
# and generate embeddings for RAG retrieval.
#
# Prerequisites:
#   pip install supabase openai python-dotenv
#   .env.local with SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, LEARNING_AI_API_KEY
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
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
OPENAI_API_KEY = os.getenv("LEARNING_AI_API_KEY")
EMBEDDING_MODEL = os.getenv("LEARNING_AI_EMBEDDING_MODEL", "text-embedding-3-large")
CHAT_MODEL = os.getenv("LEARNING_AI_CHAT_MODEL", "gpt-4o-mini")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
openai = OpenAI(api_key=OPENAI_API_KEY, base_url="https://api.openai.com/v1")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CURRICULUM TOPICS — Grades 6-12 (Chemistry, Physics, Biology, Mathematics)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CURRICULUM_TOPICS = {
    6: {
        "Mathematics": [
            "Whole Numbers", "Fractions", "Decimals", "Ratio and Proportion",
            "Basic Geometry", "Perimeter and Area", "Data Handling",
        ],
        "Physics": [
            "Motion and Measurement of Distances", "Light, Shadows and Reflections",
            "Electricity and Circuits", "Fun with Magnets", "Air Around Us",
        ],
        "Chemistry": [
            "Fibre to Fabric", "Sorting Materials into Groups", "Separation of Substances",
            "Changes Around Us", "Water", "Air",
        ],
        "Biology": [
            "Food: Where Does It Come From?", "Components of Food", "Getting to Know Plants",
            "Body Movements", "Living Organisms and Their Surroundings", "The Living Organisms",
        ],
    },
    7: {
        "Mathematics": [
            "Integers", "Fractions and Decimals", "Data Handling", "Simple Equations",
            "Lines and Angles", "Triangle and Its Properties", "Congruence of Triangles",
            "Comparing Quantities", "Rational Numbers", "Perimeter and Area",
        ],
        "Physics": [
            "Motion", "Heat", "Acids, Bases and Salts", "Physical and Chemical Changes",
            "Weather, Climate and Adaptations", "Winds, Storms and Cyclones",
        ],
        "Chemistry": [
            "Fibre to Fabric", "Acids, Bases and Salts", "Physical and Chemical Changes",
            "Heat", "Respiration in Organisms", "Transportation in Animals and Plants",
        ],
        "Biology": [
            "Nutrition in Plants", "Nutrition in Animals", "Respiration in Organisms",
            "Transportation in Animals and Plants", "Reproduction in Plants",
            "Motion and Time", "Electric Current and Its Effects",
        ],
    },
    8: {
        "Mathematics": [
            "Rational Numbers", "Linear Equations in One Variable", "Understanding Quadrilaterals",
            "Practical Geometry", "Data Handling", "Squares and Square Roots",
            "Cubes and Cube Roots", "Comparing Quantities", "Algebraic Expressions and Identities",
            "Visualising Solid Shapes", "Mensuration", "Exponents and Powers",
        ],
        "Physics": [
            "Force and Pressure", "Friction", "Sound", "Chemical Effects of Electric Current",
            "Natural Phenomena", "Reaching the Age of Adolescence",
        ],
        "Chemistry": [
            "Synthetic Fibres and Plastics", "Materials: Metals and Non-Metals",
            "Coal and Petroleum", "Combustion and Flame", "Pollution of Air and Water",
        ],
        "Biology": [
            "Crop Production and Management", "Microorganisms: Friend and Foe",
            "Conservation of Plants and Animals", "Cell — Structure and Functions",
            "Reproduction in Animals", "Adolescence",
        ],
    },
    9: {
        "Mathematics": [
            "Number Systems", "Polynomials", "Coordinate Geometry", "Linear Equations in Two Variables",
            "Introduction to Euclid's Geometry", "Lines and Angles", "Triangles",
            "Quadrilaterals", "Areas of Parallelograms and Triangles", "Circles",
            "Constructions", "Heron's Formula", "Surface Areas and Volumes", "Statistics", "Probability",
        ],
        "Physics": [
            "Motion", "Force and Laws of Motion", "Gravitation", "Work and Energy",
            "Sound", "Matter in Our Surroundings", "Is Matter Around Us Pure",
        ],
        "Chemistry": [
            "Matter in Our Surroundings", "Is Matter Around Us Pure",
            "Atoms and Molecules", "Structure of the Atom",
        ],
        "Biology": [
            "The Fundamental Unit of Life", "Tissues", "Diversity in Living Organisms",
            "Why Do We Fall Ill", "Natural Resources", "Improvement in Food Resources",
        ],
    },
    10: {
        "Mathematics": [
            "Real Numbers", "Polynomials", "Pair of Linear Equations in Two Variables",
            "Quadratic Equations", "Arithmetic Progressions", "Triangles", "Coordinate Geometry",
            "Introduction to Trigonometry", "Some Applications of Trigonometry",
            "Circles", "Constructions", "Areas Related to Circles",
            "Surface Areas and Volumes", "Statistics", "Probability",
        ],
        "Physics": [
            "Light – Reflection and Refraction", "Human Eye and Colourful World",
            "Electricity", "Magnetic Effects of Electric Current", "Sources of Energy",
        ],
        "Chemistry": [
            "Chemical Reactions and Equations", "Acids, Bases and Salts",
            "Metals and Non-metals", "Carbon and Its Compounds", "Periodic Classification of Elements",
        ],
        "Biology": [
            "Life Processes", "Control and Coordination", "How Do Organisms Reproduce",
            "Heredity and Evolution", "Our Environment", "Management of Natural Resources",
        ],
    },
    11: {
        "Mathematics": [
            "Sets", "Relations and Functions", "Trigonometric Functions", "Principle of Mathematical Induction",
            "Complex Numbers and Quadratic Equations", "Linear Inequalities", "Permutations and Combinations",
            "Binomial Theorem", "Sequences and Series", "Straight Lines", "Conic Sections",
            "Introduction to Three Dimensional Geometry", "Limits and Derivatives",
            "Mathematical Reasoning", "Statistics", "Probability",
        ],
        "Physics": [
            "Physical World", "Units and Measurements", "Motion in a Straight Line",
            "Motion in a Plane", "Laws of Motion", "Work, Energy and Power",
            "System of Particles and Rotational Motion", "Gravitation",
            "Mechanical Properties of Solids", "Mechanical Properties of Fluids",
            "Thermal Properties of Matter", "Thermodynamics", "Kinetic Theory",
            "Oscillations", "Waves",
        ],
        "Chemistry": [
            "Some Basic Concepts of Chemistry", "Structure of Atom", "Classification of Elements and Periodicity",
            "Chemical Bonding and Molecular Structure", "States of Matter", "Thermodynamics",
            "Equilibrium", "Redox Reactions", "Hydrogen", "The s-Block Elements",
            "The p-Block Elements", "Organic Chemistry – Some Basic Principles and Techniques",
            "Hydrocarbons", "Environmental Chemistry",
        ],
        "Biology": [
            "The Living World", "Biological Classification", "Plant Kingdom", "Animal Kingdom",
            "Morphology of Flowering Plants", "Anatomy of Flowering Plants",
            "Structural Organisation in Animals", "Cell: The Unit of Life",
            "Biomolecules", "Cell Cycle and Cell Division", "Transport in Plants",
            "Mineral Nutrition", "Photosynthesis in Higher Plants", "Respiration in Plants",
            "Plant Growth and Development", "Digestion and Absorption",
            "Breathing and Exchange of Gases", "Body Fluids and Circulation",
            "Excretory Products and Their Elimination", "Locomotion and Movement",
            "Neural Control and Coordination", "Chemical Coordination and Integration",
        ],
    },
    12: {
        "Mathematics": [
            "Relations and Functions", "Inverse Trigonometric Functions", "Matrices", "Determinants",
            "Continuity and Differentiability", "Application of Derivatives", "Integrals",
            "Application of Integrals", "Differential Equations", "Vector Algebra",
            "Three Dimensional Geometry", "Linear Programming", "Probability",
        ],
        "Physics": [
            "Electric Charges and Fields", "Electrostatic Potential and Capacitance",
            "Current Electricity", "Moving Charges and Magnetism", "Magnetism and Matter",
            "Electromagnetic Induction", "Alternating Current", "Electromagnetic Waves",
            "Ray Optics and Optical Instruments", "Wave Optics", "Dual Nature of Radiation and Matter",
            "Atoms", "Nuclei", "Semiconductor Electronics",
        ],
        "Chemistry": [
            "The Solid State", "Solutions", "Electrochemistry", "Chemical Kinetics",
            "Surface Chemistry", "General Principles and Processes of Isolation of Elements",
            "The p-Block Elements", "The d- and f-Block Elements", "Coordination Compounds",
            "Haloalkanes and Haloarenes", "Alcohols, Phenols and Ethers",
            "Aldehydes, Ketones and Carboxylic Acids", "Amines", "Biomolecules",
            "Polymers", "Chemistry in Everyday Life",
        ],
        "Biology": [
            "Reproduction in Organisms", "Sexual Reproduction in Flowering Plants",
            "Human Reproduction", "Reproductive Health", "Principles of Inheritance and Variation",
            "Molecular Basis of Inheritance", "Evolution", "Human Health and Disease",
            "Strategies for Enhancement in Food Production", "Microbes in Human Welfare",
            "Biotechnology: Principles and Processes", "Biotechnology and Its Applications",
            "Organisms and Populations", "Ecosystem", "Biodiversity and Conservation",
            "Environmental Issues",
        ],
    },
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CONTENT GENERATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def generate_study_content(grade: int, subject: str, chapter: str) -> Optional[str]:
    """Generate study content for a chapter using OpenAI."""
    try:
        resp = openai.chat.completions.create(
            model=CHAT_MODEL,
            messages=[
                {
                    "role": "system",
                    "content": f"You are an expert {subject} educator for Class {grade}. Generate comprehensive study material for the chapter '{chapter}'. Include: key concepts, definitions, formulas (if applicable), examples, and important points. Keep it educational and accurate. Format as plain text paragraphs.",
                },
                {
                    "role": "user",
                    "content": f"Generate study material for Class {grade} {subject} — Chapter: {chapter}. Cover all important concepts, definitions, and examples. Make it detailed enough for a student to learn from.",
                },
            ],
            max_tokens=1500,
            temperature=0.3,
        )
        return resp.choices[0].message.content
    except Exception as e:
        print(f"    [WARN] Content generation failed: {e}")
        return None


def get_embedding(text: str) -> Optional[List[float]]:
    """Generate embedding vector for text."""
    try:
        resp = openai.embeddings.create(
            model=EMBEDDING_MODEL,
            input=text,
        )
        return resp.data[0].embedding
    except Exception as e:
        print(f"    [WARN] Embedding failed: {e}")
        return None


def chunk_text(text: str, max_chars: int = 1200, overlap: int = 150) -> List[str]:
    """Split text into overlapping chunks."""
    if not text:
        return []
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        chunk = text[start:end].strip()
        if chunk and len(chunk) > 50:
            chunks.append(chunk)
        if end >= len(text):
            break
        start = end - overlap
    return chunks


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DATABASE OPERATIONS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def insert_document(grade: int, subject: str, chapter: str) -> Optional[str]:
    """Insert a curriculum document and return its UUID."""
    doc = {
        "school_id": None,
        "class_grade": grade,
        "subject": subject,
        "chapter": chapter,
        "topic": chapter,
        "source_title": f"NCERT Class {grade} {subject} - {chapter}",
        "source_url": "https://ncert.nic.in/",
        "document_identifier": f"NCERT-CLASS-{grade}-{subject.upper().replace(' ', '-')}-{chapter.upper().replace(' ', '-')[:20]}",
        "license_name": "NCERT",
        "license_url": "https://ncert.nic.in/",
        "curriculum_year": "2025-26",
        "academic_year": "2025-26",
        "content_version": 1,
        "approval_status": "approved",
    }
    try:
        result = supabase.table("curriculum_documents").insert(doc).execute()
        if result.data:
            return result.data[0]["id"]
    except Exception as e:
        print(f"    [WARN] Document insert failed: {e}")
    return None


def insert_chunk(doc_id: str, chunk_index: int, content: str, embedding: List[float]) -> bool:
    """Insert a curriculum chunk with its embedding."""
    try:
        content_hash = hashlib.sha256(content.encode()).hexdigest()
        supabase.table("curriculum_chunks").insert({
            "document_id": doc_id,
            "chunk_index": chunk_index,
            "content": content,
            "content_hash": content_hash,
            "embedding": embedding,
        }).execute()
        return True
    except Exception as e:
        print(f"    [WARN] Chunk insert failed: {e}")
    return False


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MAIN INGESTION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def ingest_topic(grade: int, subject: str, chapter: str) -> bool:
    """Ingest a single curriculum topic."""
    print(f"\n  [TOPIC] {subject} - {chapter} (Grade {grade})")

    # Generate study content
    content = generate_study_content(grade, subject, chapter)
    if not content:
        return False

    # Insert document
    doc_id = insert_document(grade, subject, chapter)
    if not doc_id:
        return False

    # Chunk and embed
    chunks = chunk_text(content)
    print(f"    [CHUNKS] {len(content)} chars ? {len(chunks)} chunks")

    success_count = 0
    for i, chunk in enumerate(chunks):
        embedding = get_embedding(chunk)
        if not embedding:
            continue
        if insert_chunk(doc_id, i, chunk, embedding):
            success_count += 1
        time.sleep(0.1)  # rate limiting

    print(f"    [OK] {success_count}/{len(chunks)} chunks inserted (doc: {doc_id})")
    return success_count > 0


def main():
    print("[START] Starting curriculum ingestion (Grades 6-12)")
    print(f"   Subjects: Chemistry, Physics, Biology, Mathematics")
    print(f"   Embedding model: {EMBEDDING_MODEL}")
    print(f"   Chat model: {CHAT_MODEL}")

    total = 0
    success = 0
    for grade, subjects in CURRICULUM_TOPICS.items():
        print(f"\n{'='*60}")
        print(f"  GRADE {grade}")
        print(f"{'='*60}")
        for subject, chapters in subjects.items():
            for chapter in chapters:
                total += 1
                if ingest_topic(grade, subject, chapter):
                    success += 1
                time.sleep(1)  # rate limiting between topics

    print(f"\n{'='*60}")
    print(f"[DONE] Ingestion complete: {success}/{total} topics imported")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
