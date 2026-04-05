#!/usr/bin/env python3
"""
build_master_list.py
────────────────────
Builds a clean 1 500-word master list for VocabWidget with 500 words
per difficulty level. Every word includes a full data set so the app
never needs to make a network call at runtime.

Output schema (per word)
────────────────────────
  id, word, partOfSpeech, definition, examples (≤2), synonyms (≤8),
  origin (or null), level, isFeatured, mastered

How it works
────────────
  Phase 1 — Score      : Calls WordsAPI for each candidate's Zipf frequency
                          score.  Words are bucketed into levels using fixed
                          Zipf boundaries and the best 500 per level are
                          chosen.  Results are cached so the script can be
                          safely interrupted and resumed.

  Phase 2 — Enrich     : Calls the Free Dictionary API (free, no key) for
                          each confirmed word: up to 2 examples, up to 8
                          synonyms, and etymology.  Also cached.

  Phase 3 — Assemble   : Merges scored + enriched data, assigns sequential
                          IDs, writes words_generated.json for review.

Zipf level boundaries
────────────────────
  beginner     4.5 – 5.5   (heard it, don't use it confidently)
  intermediate 3.1 – 4.5   (marks an educated vocabulary)
  advanced     1.9 – 3.1   (literary / formal register)

Prerequisites
────────────────────
  pip install requests          (or use the stdlib urllib — already used here)
  export WORDSAPI_KEY=your_key  (free tier at rapidapi.com/dpventures/api/wordsapiv1)

Run from the project root (VocabWidget/VocabWidget/):
  python3 scripts/build_master_list.py

Review the output, then copy it into the app:
  cp words_generated.json VocabWidget/words.json

Safe to re-run — cached results are never re-fetched.  Delete
scripts/cache/ to start completely from scratch.
"""

import json
import os
import sys
import time
import pathlib
import http.client
import urllib.parse
import random

# ── Config ────────────────────────────────────────────────────────────────────

WORDSAPI_KEY   = os.environ.get("WORDSAPI_KEY", "")
WORDSAPI_HOST  = "wordsapiv1.p.rapidapi.com"

CANDIDATES_FILE   = pathlib.Path("scripts/word_candidates.txt")
SCORES_CACHE      = pathlib.Path("scripts/cache/scores.json")
ENRICHMENT_CACHE  = pathlib.Path("scripts/cache/enrichment.json")
OUTPUT_FILE       = pathlib.Path("words_generated.json")

# How many confirmed words to target per level before moving to enrichment.
# Set slightly above 500 as a buffer in case a few enrichment calls fail.
TARGET_PER_LEVEL  = 530
FINAL_PER_LEVEL   = 500

# Zipf boundaries
BEGINNER_MAX      = 5.5
BEGINNER_MIN      = 4.5
INTERMEDIATE_MIN  = 3.1
ADVANCED_MIN      = 1.9

# API rate limiting
WORDSAPI_DELAY    = 0.35   # seconds between WordsAPI calls
FREEDICT_DELAY    = 0.30   # seconds between Free Dictionary calls

MAX_EXAMPLES      = 2
MAX_SYNONYMS      = 8

# ── Validate environment ──────────────────────────────────────────────────────

if not WORDSAPI_KEY:
    print("❌  WORDSAPI_KEY environment variable is not set.")
    print("    Get a free key at: https://rapidapi.com/dpventures/api/wordsapiv1")
    print("    Then run:  export WORDSAPI_KEY=your_key_here")
    sys.exit(1)

# ── Load caches ───────────────────────────────────────────────────────────────

scores_cache:     dict = json.loads(SCORES_CACHE.read_text())     if SCORES_CACHE.exists()     else {}
enrichment_cache: dict = json.loads(ENRICHMENT_CACHE.read_text()) if ENRICHMENT_CACHE.exists() else {}

# ── Load candidate words ──────────────────────────────────────────────────────

if not CANDIDATES_FILE.exists():
    print(f"❌  {CANDIDATES_FILE} not found.")
    sys.exit(1)

all_candidates = [
    line.strip().lower()
    for line in CANDIDATES_FILE.read_text().splitlines()
    if line.strip() and not line.startswith("#")
]
# Deduplicate while preserving order
seen: set = set()
candidates: list = []
for w in all_candidates:
    if w not in seen:
        seen.add(w)
        candidates.append(w)

print(f"📖  {len(candidates)} unique candidates loaded from {CANDIDATES_FILE}")
print(f"📦  {len(scores_cache)} already scored (cached)")
print(f"📦  {len(enrichment_cache)} already enriched (cached)\n")

# ── Phase 1: Score candidates via WordsAPI ────────────────────────────────────

def fetch_zipf(word: str) -> float | None:
    conn = http.client.HTTPSConnection(WORDSAPI_HOST)
    try:
        conn.request(
            "GET",
            f"/words/{urllib.parse.quote(word)}/frequency",
            headers={
                "X-RapidAPI-Key":  WORDSAPI_KEY,
                "X-RapidAPI-Host": WORDSAPI_HOST,
            },
        )
        res  = conn.getresponse()
        body = json.loads(res.read().decode("utf-8"))
        if res.status == 429:
            print("\n⛔  Rate limit hit — stopping Phase 1. Re-run tomorrow to continue.")
            return "RATE_LIMITED"
        return body.get("frequency", {}).get("zipf")
    except Exception as e:
        print(f"  ⚠️  {e}")
        return None
    finally:
        conn.close()

def level_for_zipf(zipf: float) -> str | None:
    if BEGINNER_MIN <= zipf <= BEGINNER_MAX:
        return "beginner"
    if INTERMEDIATE_MIN <= zipf < BEGINNER_MIN:
        return "intermediate"
    if ADVANCED_MIN <= zipf < INTERMEDIATE_MIN:
        return "advanced"
    return None   # too_common or too_rare

# Count how many confirmed words we already have per level from the cache
def tally_confirmed() -> dict:
    t = {"beginner": 0, "intermediate": 0, "advanced": 0}
    for word, zipf in scores_cache.items():
        if zipf is None:
            continue
        lvl = level_for_zipf(float(zipf))
        if lvl:
            t[lvl] += 1
    return t

to_score = [w for w in candidates if w not in scores_cache]
print(f"── Phase 1: Scoring ─────────────────────────────────────────────────")
print(f"   {len(to_score)} candidates left to score\n")

rate_limited = False
for i, word in enumerate(to_score):
    confirmed = tally_confirmed()
    if all(confirmed[l] >= TARGET_PER_LEVEL for l in confirmed):
        print(f"\n✅  All levels have ≥{TARGET_PER_LEVEL} confirmed words — stopping early.")
        break

    print(f"  [{i+1:>4}/{len(to_score)}]  {word:<22}", end=" ", flush=True)
    result = fetch_zipf(word)

    if result == "RATE_LIMITED":
        rate_limited = True
        break

    scores_cache[word] = result
    SCORES_CACHE.parent.mkdir(parents=True, exist_ok=True)
    SCORES_CACHE.write_text(json.dumps(scores_cache, indent=2))

    if result is not None:
        lvl = level_for_zipf(float(result))
        print(f"zipf={result:.2f}  →  {lvl or 'out of range'}")
    else:
        print("not found")

    time.sleep(WORDSAPI_DELAY)

if rate_limited:
    print("\nRe-run the script tomorrow to continue scoring.")
    sys.exit(0)

# ── Select top 500 per level ──────────────────────────────────────────────────

print(f"\n── Selecting top {FINAL_PER_LEVEL} per level ──────────────────────────────────────")

by_level: dict = {"beginner": [], "intermediate": [], "advanced": []}
for word, zipf in scores_cache.items():
    if zipf is None:
        continue
    lvl = level_for_zipf(float(zipf))
    if lvl:
        by_level[lvl].append((word, float(zipf)))

# Within each level, sort highest Zipf first (most recognisable useful words)
selected: dict = {}
for lvl, pairs in by_level.items():
    pairs.sort(key=lambda x: x[1], reverse=True)
    chosen = pairs[:FINAL_PER_LEVEL]
    selected[lvl] = [w for w, _ in chosen]
    print(f"  {lvl:<15} {len(by_level[lvl]):>3} available  →  {len(chosen)} selected")

total_selected = sum(len(v) for v in selected.values())
if total_selected < FINAL_PER_LEVEL * 3:
    short = {l: FINAL_PER_LEVEL - len(v) for l, v in selected.items() if len(v) < FINAL_PER_LEVEL}
    print(f"\n⚠️  Not enough words in: {short}")
    print("   Add more candidates to word_candidates.txt and re-run.")

# ── Phase 2: Enrich via Free Dictionary API ───────────────────────────────────

print(f"\n── Phase 2: Enriching ───────────────────────────────────────────────")

all_selected = [
    (w, lvl)
    for lvl, words in selected.items()
    for w in words
    if w not in enrichment_cache
]
print(f"   {len(all_selected)} words left to enrich\n")

def fetch_enrichment(word: str) -> dict:
    encoded = urllib.parse.quote(word.lower())
    conn = http.client.HTTPSConnection("api.dictionaryapi.dev")
    try:
        conn.request("GET", f"/api/v2/entries/en/{encoded}",
                     headers={"User-Agent": "VocabWidget/1.0"})
        res  = conn.getresponse()
        if res.status != 200:
            return {}
        entries = json.loads(res.read().decode("utf-8"))
        if not isinstance(entries, list) or not entries:
            return {}

        raw_synonyms: list = []
        raw_examples: list = []
        origin: str | None = None
        definition: str | None = None
        part_of_speech: str | None = None

        for entry in entries:
            if origin is None:
                o = (entry.get("origin") or "").strip()
                if o:
                    origin = o
            for meaning in entry.get("meanings", []):
                if part_of_speech is None:
                    part_of_speech = meaning.get("partOfSpeech")
                raw_synonyms.extend(meaning.get("synonyms") or [])
                for defn in meaning.get("definitions", []):
                    if definition is None:
                        definition = (defn.get("definition") or "").strip() or None
                    raw_synonyms.extend(defn.get("synonyms") or [])
                    ex = (defn.get("example") or "").strip()
                    if ex and len(raw_examples) < MAX_EXAMPLES:
                        raw_examples.append(ex)

        # Deduplicate synonyms, preserve order, cap at MAX_SYNONYMS
        seen_syn: set = set()
        synonyms: list = []
        for s in raw_synonyms:
            s = s.strip()
            if s and s.lower() not in seen_syn:
                seen_syn.add(s.lower())
                synonyms.append(s)
                if len(synonyms) >= MAX_SYNONYMS:
                    break

        return {
            "partOfSpeech": part_of_speech,
            "definition":   definition,
            "examples":     raw_examples,
            "synonyms":     synonyms,
            "origin":       origin,
        }
    except Exception as e:
        print(f"  ⚠️  {e}")
        return {}
    finally:
        conn.close()

for i, (word, lvl) in enumerate(all_selected):
    print(f"  [{i+1:>4}/{len(all_selected)}]  {word:<22}", end=" ", flush=True)
    data = fetch_enrichment(word)
    enrichment_cache[word] = data
    ENRICHMENT_CACHE.write_text(json.dumps(enrichment_cache, indent=2, ensure_ascii=False))

    n_ex  = len(data.get("examples", []))
    n_syn = len(data.get("synonyms", []))
    has_o = "✓" if data.get("origin") else "–"
    print(f"ex={n_ex}  syn={n_syn}  origin={has_o}")
    time.sleep(FREEDICT_DELAY)

# ── Phase 3: Assemble final word list ─────────────────────────────────────────

print(f"\n── Phase 3: Assembling ──────────────────────────────────────────────")

output: list = []
uid = 0
stats = {"beginner": 0, "intermediate": 0, "advanced": 0,
         "no_def": 0, "no_example": 0}

level_order = ["beginner", "intermediate", "advanced"]

for lvl in level_order:
    for word in selected[lvl]:
        enriched = enrichment_cache.get(word, {})
        zipf     = scores_cache.get(word)

        definition   = enriched.get("definition") or ""
        part_of_speech = enriched.get("partOfSpeech") or "unknown"
        examples     = enriched.get("examples") or []
        synonyms     = enriched.get("synonyms") or []
        origin       = enriched.get("origin")

        if not definition:
            stats["no_def"] += 1

        if not examples:
            stats["no_example"] += 1

        output.append({
            "id":           uid,
            "word":         word.capitalize(),
            "partOfSpeech": part_of_speech,
            "definition":   definition,
            "examples":     examples,
            "synonyms":     synonyms,
            "origin":       origin,
            "level":        lvl,
            "isFeatured":   False,
            "mastered":     False,
        })
        stats[lvl] += 1
        uid += 1

OUTPUT_FILE.write_text(json.dumps(output, indent=2, ensure_ascii=False))

# ── Summary ───────────────────────────────────────────────────────────────────

print(f"\n── Results ──────────────────────────────────────────────────────────")
print(f"  beginner     : {stats['beginner']}")
print(f"  intermediate : {stats['intermediate']}")
print(f"  advanced     : {stats['advanced']}")
print(f"  total        : {len(output)}")
print(f"  missing def  : {stats['no_def']}")
print(f"  missing ex   : {stats['no_example']}")
print(f"\n✅  Written to {OUTPUT_FILE}")
print(f"\n   Review the file, then copy it into the app:")
print(f"   cp words_generated.json VocabWidget/words.json")
print(f"\n   Then commit words.json and delete words_generated.json.")
