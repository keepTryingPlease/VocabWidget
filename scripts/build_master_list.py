#!/usr/bin/env python3
"""
build_master_list.py
────────────────────
Builds a clean 1 500-word master list for VocabWidget — 500 words per
difficulty level — by requesting random words directly from WordsAPI
within each Zipf frequency range.  No candidate word list required.

Every word ends up with a full data set so the app never needs to make
a network call at runtime.

Output schema (per word)
────────────────────────
  id            sequential integer
  word          capitalised string
  partOfSpeech  "noun" / "adjective" / "verb" / etc.
  definition    string
  examples      list of up to 2 example sentences
  synonyms      list of up to 8 synonyms
  origin        etymology string, or null
  level         "beginner" / "intermediate" / "advanced"
  isFeatured    false
  mastered      false

How it works
────────────
  Phase 1 — Collect : Calls WordsAPI GET /words/?random=true with
                       frequencyMin / frequencyMax set for each level.
                       Each successful call returns a word guaranteed to
                       be in the right Zipf band.  Runs until 500 unique
                       words with definitions are confirmed per level.

  Phase 2 — Enrich  : Calls the Free Dictionary API (free, no key) for
                       each word to get etymology (origin).  WordsAPI
                       already provides definitions, examples, synonyms.

  Both phases cache to disk after every call so the script can be
  interrupted and resumed safely.

Zipf level boundaries used
──────────────────────────
  beginner       4.5 – 5.5   heard it, don't use it confidently
  intermediate   3.1 – 4.5   marks an educated vocabulary
  advanced       1.9 – 3.1   literary / formal register

API usage estimate (free tier = 2 500 requests / day)
──────────────────────────────────────────────────────
  ~550 WordsAPI calls per level (allows for ~10% duplicates / no-data)
  ~1 650 WordsAPI calls total
  ~1 500 Free Dictionary calls (unlimited, no key)
  → Completes in a single day well within the free quota.

Prerequisites
────────────────────────────────────────────────────
  Python 3.10+  (stdlib only — no pip installs needed)
  export WORDSAPI_KEY=your_key

  Free key at: https://rapidapi.com/dpventures/api/wordsapiv1

Run from the project root (VocabWidget/VocabWidget/):
  python3 scripts/build_master_list.py

When done, review the output and copy it into the app:
  cp words_generated.json VocabWidget/words.json
"""

import json
import os
import sys
import time
import pathlib
import http.client
import urllib.parse

# ── Config ────────────────────────────────────────────────────────────────────

WORDSAPI_KEY  = os.environ.get("WORDSAPI_KEY", "")
WORDSAPI_HOST = "wordsapiv1.p.rapidapi.com"

CACHE_DIR        = pathlib.Path("scripts/cache")
COLLECT_CACHE    = CACHE_DIR / "collected.json"   # words gathered per level
ENRICHMENT_CACHE = CACHE_DIR / "enrichment.json"  # etymology from Free Dict
OUTPUT_FILE      = pathlib.Path("words_generated.json")

WORDS_PER_LEVEL = 500   # target per level
MAX_EXAMPLES    = 2
MAX_SYNONYMS    = 8

# Preferred parts of speech — we try to pick the most useful sense of a word
PREFERRED_POS = ["adjective", "verb", "noun", "adverb"]

LEVELS = {
    "beginner":     {"min": 4.5, "max": 5.5},
    "intermediate": {"min": 3.1, "max": 4.5},
    "advanced":     {"min": 1.9, "max": 3.1},
}

WORDSAPI_DELAY = 0.35   # seconds between WordsAPI calls
FREEDICT_DELAY = 0.30   # seconds between Free Dictionary calls

# ── Validate environment ──────────────────────────────────────────────────────

if not WORDSAPI_KEY:
    print("❌  WORDSAPI_KEY environment variable is not set.")
    print("    Get a free key at: https://rapidapi.com/dpventures/api/wordsapiv1")
    print("    Then run:  export WORDSAPI_KEY=your_key_here")
    sys.exit(1)

# ── Load caches ───────────────────────────────────────────────────────────────

CACHE_DIR.mkdir(parents=True, exist_ok=True)

collected: dict    = json.loads(COLLECT_CACHE.read_text())    if COLLECT_CACHE.exists()    else {"beginner": {}, "intermediate": {}, "advanced": {}}
enrichment: dict   = json.loads(ENRICHMENT_CACHE.read_text()) if ENRICHMENT_CACHE.exists() else {}

for lvl in LEVELS:
    if lvl not in collected:
        collected[lvl] = {}

# ── Phase 1: Collect random words per level from WordsAPI ─────────────────────

def fetch_random_word(freq_min: float, freq_max: float) -> dict | None:
    """
    Calls GET /words/?random=true&frequencyMin=X&frequencyMax=Y
    Returns parsed response dict, or None on any error / rate limit.
    """
    params = urllib.parse.urlencode({
        "random":       "true",
        "frequencyMin": freq_min,
        "frequencyMax": freq_max,
        "hasDetails":   "definitions",
    })
    conn = http.client.HTTPSConnection(WORDSAPI_HOST)
    try:
        conn.request(
            "GET",
            f"/words/?{params}",
            headers={
                "X-RapidAPI-Key":  WORDSAPI_KEY,
                "X-RapidAPI-Host": WORDSAPI_HOST,
            },
        )
        res  = conn.getresponse()
        body = json.loads(res.read().decode("utf-8"))

        if res.status == 429:
            print("\n⛔  Rate limit reached — stopping. Re-run tomorrow to continue.")
            return "RATE_LIMITED"

        if res.status != 200 or "word" not in body:
            return None

        return body
    except Exception as e:
        print(f"  ⚠️  {e}")
        return None
    finally:
        conn.close()

def best_result(results: list) -> dict | None:
    """Pick the most useful definition from a list of WordsAPI result objects."""
    if not results:
        return None
    for pos in PREFERRED_POS:
        match = next((r for r in results if r.get("partOfSpeech") == pos), None)
        if match:
            return match
    return results[0]

def parse_word_entry(body: dict) -> dict | None:
    """
    Extract a clean word record from a WordsAPI response body.
    Returns None if the word lacks a usable definition.
    """
    word  = (body.get("word") or "").strip()
    if not word:
        return None

    results = body.get("results") or []
    chosen  = best_result(results)
    if not chosen:
        return None

    definition = (chosen.get("definition") or "").strip()
    if not definition:
        return None

    part_of_speech = chosen.get("partOfSpeech") or "unknown"

    # Collect examples across all results (prefer chosen sense first)
    raw_examples: list[str] = []
    for r in [chosen] + [r for r in results if r is not chosen]:
        for ex in r.get("examples") or []:
            ex = ex.strip()
            if ex and ex not in raw_examples:
                raw_examples.append(ex)
            if len(raw_examples) >= MAX_EXAMPLES:
                break
        if len(raw_examples) >= MAX_EXAMPLES:
            break

    # Collect synonyms across all results
    raw_synonyms: list[str] = []
    for r in results:
        for s in r.get("synonyms") or []:
            s = s.strip()
            if s and s.lower() not in {x.lower() for x in raw_synonyms}:
                raw_synonyms.append(s)

    synonyms = raw_synonyms[:MAX_SYNONYMS]

    return {
        "word":         word,
        "partOfSpeech": part_of_speech,
        "definition":   definition,
        "examples":     raw_examples[:MAX_EXAMPLES],
        "synonyms":     synonyms,
    }

print("── Phase 1: Collecting random words per level ───────────────────────")
rate_limited = False

for level, bounds in LEVELS.items():
    already  = len(collected[level])
    needed   = WORDS_PER_LEVEL - already
    if needed <= 0:
        print(f"  {level:<15} ✅  already have {already} words — skipping")
        continue

    print(f"\n  {level}  (need {needed} more, have {already})")

    attempts = 0
    while len(collected[level]) < WORDS_PER_LEVEL:
        attempts += 1
        result = fetch_random_word(bounds["min"], bounds["max"])

        if result == "RATE_LIMITED":
            rate_limited = True
            break

        if result is None:
            print("    ↳ no result", flush=True)
            time.sleep(WORDSAPI_DELAY)
            continue

        entry = parse_word_entry(result)
        if entry is None:
            print(f"    ↳ {result.get('word', '?'):<20} no usable definition", flush=True)
            time.sleep(WORDSAPI_DELAY)
            continue

        key = entry["word"].lower()
        if key in collected[level]:
            print(f"    ↳ {entry['word']:<20} duplicate — skipping", flush=True)
            time.sleep(WORDSAPI_DELAY)
            continue

        # Also skip if the word already appears in another level
        already_in_other = any(
            key in collected[other_level]
            for other_level in LEVELS
            if other_level != level
        )
        if already_in_other:
            print(f"    ↳ {entry['word']:<20} already in another level — skipping", flush=True)
            time.sleep(WORDSAPI_DELAY)
            continue

        collected[level][key] = entry
        COLLECT_CACHE.write_text(json.dumps(collected, indent=2, ensure_ascii=False))

        count = len(collected[level])
        print(f"    [{count:>3}/{WORDS_PER_LEVEL}]  {entry['word']:<22} "
              f"pos={entry['partOfSpeech']}", flush=True)
        time.sleep(WORDSAPI_DELAY)

    if rate_limited:
        break

if rate_limited:
    total_so_far = sum(len(v) for v in collected.values())
    print(f"\n  Saved {total_so_far} words so far.  Re-run tomorrow to continue.")
    sys.exit(0)

# ── Phase 2: Enrich with etymology from Free Dictionary ───────────────────────

print("\n── Phase 2: Fetching etymology from Free Dictionary ─────────────────")

all_words = [
    (word_key, level)
    for level, words in collected.items()
    for word_key in words
    if word_key not in enrichment
]
print(f"   {len(all_words)} words need etymology lookup\n")

def fetch_origin(word: str) -> str | None:
    encoded = urllib.parse.quote(word.lower())
    conn = http.client.HTTPSConnection("api.dictionaryapi.dev")
    try:
        conn.request("GET", f"/api/v2/entries/en/{encoded}",
                     headers={"User-Agent": "VocabWidget/1.0"})
        res  = conn.getresponse()
        if res.status != 200:
            return None
        entries = json.loads(res.read().decode("utf-8"))
        if not isinstance(entries, list):
            return None
        for entry in entries:
            o = (entry.get("origin") or "").strip()
            if o:
                return o
        return None
    except Exception:
        return None
    finally:
        conn.close()

for i, (word_key, level) in enumerate(all_words):
    print(f"  [{i+1:>4}/{len(all_words)}]  {word_key:<22}", end=" ", flush=True)
    origin = fetch_origin(word_key)
    enrichment[word_key] = origin
    ENRICHMENT_CACHE.write_text(json.dumps(enrichment, indent=2, ensure_ascii=False))
    print("✓" if origin else "–")
    time.sleep(FREEDICT_DELAY)

# ── Phase 3: Assemble final word list ─────────────────────────────────────────

print("\n── Phase 3: Assembling output ───────────────────────────────────────")

output: list = []
uid  = 0
stats = {lvl: 0 for lvl in LEVELS}

for level in LEVELS:
    for word_key, entry in collected[level].items():
        output.append({
            "id":           uid,
            "word":         entry["word"].capitalize(),
            "partOfSpeech": entry["partOfSpeech"],
            "definition":   entry["definition"],
            "examples":     entry["examples"],
            "synonyms":     entry["synonyms"],
            "origin":       enrichment.get(word_key),
            "level":        level,
            "isFeatured":   False,
            "mastered":     False,
        })
        stats[level] += 1
        uid += 1

OUTPUT_FILE.write_text(json.dumps(output, indent=2, ensure_ascii=False))

# ── Summary ───────────────────────────────────────────────────────────────────

has_origin = sum(1 for w in output if w["origin"])
has_2ex    = sum(1 for w in output if len(w["examples"]) >= 2)
has_syn    = sum(1 for w in output if w["synonyms"])

print(f"\n── Results ──────────────────────────────────────────────────────────")
for lvl in LEVELS:
    print(f"  {lvl:<15} {stats[lvl]} words")
print(f"  {'total':<15} {len(output)}")
print(f"\n  has etymology  : {has_origin} / {len(output)}")
print(f"  has 2 examples : {has_2ex} / {len(output)}")
print(f"  has synonyms   : {has_syn} / {len(output)}")
print(f"\n✅  Written to {OUTPUT_FILE}")
print(f"\n   Review, then copy into the app:")
print(f"   cp words_generated.json VocabWidget/words.json")
print(f"\n   Then commit words.json and delete words_generated.json.")
