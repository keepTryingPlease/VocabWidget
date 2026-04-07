#!/usr/bin/env python3
"""
build_master_list.py
────────────────────
Builds a clean 1 500-word master list for VocabWidget — 500 words per
difficulty level — by scoring curated candidates with WordsAPI Zipf
frequency, selecting the best per level, then enriching with the Free
Dictionary API.

Output schema (per word)
────────────────────────
  id            sequential integer
  word          capitalised string
  partOfSpeech  "noun" / "adjective" / "verb" / etc.
  definition    string
  examples      list of up to 2 example sentences
  synonyms      list of up to 12 synonyms
  origin        etymology string, or null
  level         "beginner" / "intermediate" / "advanced"
  isFeatured    false
  mastered      false

How it works
────────────
  Phase 1 — Score   : Reads every word from scripts/word_candidates.txt,
                      calls WordsAPI GET /words/{word} for each.  The FULL
                      raw API response (definitions, examples, synonyms,
                      syllables, pronunciation, frequency, typeOf, hasTypes,
                      etc.) is stored verbatim in candidate_scores.json so
                      no data is ever discarded.  Results are cached after
                      every single call so the script can be paused and
                      resumed across days.

  Phase 2 — Select  : Buckets scored words into levels by their Zipf score,
                      then takes the 500 best words per level (highest Zipf
                      within each band = most recognisable, highest-quality
                      words at that difficulty).

  Phase 3 — Enrich  : For every selected word, calls the Free Dictionary
                      API (unlimited, no key) to fill or extend examples,
                      synonyms, and etymology.  Both sources are merged so
                      the final entry always has the richest possible data.

  Phase 4 — Assemble: Writes words_generated.json ready to copy into the app.

  Both WordsAPI phases write to disk after every single API call so the
  script can be safely interrupted and resumed at any point.  Re-running
  tomorrow after a rate-limit hit will only fetch what is still missing.

Zipf level boundaries
─────────────────────
  beginner       4.5 – 5.5   (common, high-value everyday words)
  intermediate   3.1 – 4.5   (moderately frequent, SAT-level)
  advanced       1.9 – 3.1   (GRE / literary / low-frequency)

WordsAPI daily quota (free tier = 2 500 requests / day)
────────────────────────────────────────────────────────
  The script tracks every request it makes this session and warns you
  at 80 % (2 000) and 95 % (2 375).  If it hits the limit before the
  full candidate list is scored, it stops cleanly, prints progress, and
  resumes correctly on the next run.

  With ~5 000 candidates you will need 2 – 3 days of scoring to cover
  the full list.  The selection and enrichment phases then run once
  enough candidates are scored in each band.

Prerequisites
─────────────
  Python 3.10+  (stdlib only — no pip installs needed)
  export WORDSAPI_KEY=your_key

  Free key at: https://rapidapi.com/dpventures/api/wordsapiv1

Run from the project root (VocabWidget/VocabWidget/):
  python3 scripts/build_master_list.py

When done, review and copy into the app:
  cp words_generated.json VocabWidget/words.json
"""

import argparse
import json
import os
import sys
import time
import pathlib
import http.client
import urllib.parse
from wordfreq import zipf_frequency
from nltk.corpus import wordnet as wn

# ── CLI arguments ─────────────────────────────────────────────────────────────

_parser = argparse.ArgumentParser(
    description="Build the VocabWidget master word list.",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog="""
Examples
────────
  # Score all 3 000 candidates and auto-select the maximum even word count:
  python3 scripts/build_master_list.py --quota 25000

  # Same, but cap each level at 600 even if the pool is larger:
  python3 scripts/build_master_list.py --quota 25000 --words-per-level 600

  # Dry-run with a small quota to test caching / output without burning calls:
  python3 scripts/build_master_list.py --quota 50
""",
)
_parser.add_argument(
    "--quota",
    type=int,
    default=2500,
    metavar="N",
    help="Maximum WordsAPI calls for this session (default: 2500). "
         "Set to your plan's daily limit, e.g. --quota 25000.",
)
_parser.add_argument(
    "--words-per-level",
    type=int,
    default=0,
    metavar="N",
    dest="words_per_level",
    help="Words to select per level (default: 0 = auto-balance to the "
         "smallest pool so all levels stay even).",
)
_parser.add_argument(
    "--delay",
    type=float,
    default=0.7,
    metavar="SEC",
    help="Seconds to wait between WordsAPI calls (default: 0.7). "
         "Increase if you keep hitting 429 rate-limit errors.",
)
_args = _parser.parse_args()

# ── Config ────────────────────────────────────────────────────────────────────

WORDSAPI_KEY  = os.environ.get("WORDSAPI_KEY", "")
WORDSAPI_HOST = "wordsapiv1.p.rapidapi.com"

CANDIDATES_FILE  = pathlib.Path("scripts/word_candidates_clean.csv")
CACHE_DIR        = pathlib.Path("scripts/cache")
SCORES_CACHE     = CACHE_DIR / "candidate_scores.json"
ENRICHMENT_CACHE = CACHE_DIR / "enrichment.json"
OUTPUT_FILE      = pathlib.Path("words_generated.json")

MAX_EXAMPLES     = 2    # try to reach this from both APIs combined
MAX_SYNONYMS     = 12   # ceiling after merging both APIs
DAILY_QUOTA      = _args.quota
WARN_AT_80_PCT   = int(DAILY_QUOTA * 0.80)
WARN_AT_95_PCT   = int(DAILY_QUOTA * 0.95)
WORDSAPI_DELAY   = _args.delay
FREEDICT_DELAY   = 0.30

# Words above this Zipf score are too common to be vocabulary targets.
# No lower bound — the user may reach any difficulty level.
MAX_ZIPF = 4.2

print(f"\n  Quota this session : {DAILY_QUOTA:,} WordsAPI calls")
print(f"  Request delay      : {WORDSAPI_DELAY}s  (~{int(60/WORDSAPI_DELAY)} req/min)")
print(f"  Upper Zipf cap     : {MAX_ZIPF}  (words above this are too common)")

PREFERRED_POS = ["adjective", "verb", "noun", "adverb"]

WORDSAPI_DELAY = _args.delay
FREEDICT_DELAY = 0.30

# ── Validate environment ──────────────────────────────────────────────────────

if not WORDSAPI_KEY:
    print("⚠️   WORDSAPI_KEY not set — will use cache only (no new API calls).")
    print("    If unscored words remain, the script will stop at Phase 1.")

if not CANDIDATES_FILE.exists():
    print(f"❌  Candidate list not found: {CANDIDATES_FILE}")
    print("    Expected at scripts/word_candidates_clean.csv")
    sys.exit(1)

# ── Load candidates ───────────────────────────────────────────────────────────

def load_candidates() -> list[str]:
    """
    Parse word_candidates_clean.csv — single 'word' column, one word per row.
    Returns a deduplicated list of lowercase words preserving file order.
    """
    import csv as _csv
    seen: set = set()
    words: list[str] = []
    with open(CANDIDATES_FILE, encoding="utf-8") as fh:
        reader = _csv.reader(fh)
        for i, row in enumerate(reader):
            if not row:
                continue
            w = row[0].strip().lower()
            if i == 0 and w == "word":
                continue  # skip header
            if not w or " " in w:
                continue
            if w not in seen:
                seen.add(w)
                words.append(w)
    return words

candidates = load_candidates()
print(f"  Loaded {len(candidates)} unique candidate words from {CANDIDATES_FILE}")

# ── Load caches ───────────────────────────────────────────────────────────────

CACHE_DIR.mkdir(parents=True, exist_ok=True)

# scores_cache: dict of word -> entry_dict | None
#   None  = checked, WordsAPI returned no valid data (skip on future runs)
#   dict  = {zipf, word, partOfSpeech, definition, examples, synonyms}
scores_cache: dict = (
    json.loads(SCORES_CACHE.read_text())
    if SCORES_CACHE.exists() else {}
)

enrichment: dict = (
    json.loads(ENRICHMENT_CACHE.read_text())
    if ENRICHMENT_CACHE.exists() else {}
)

# ── Request counter ───────────────────────────────────────────────────────────

wordsapi_calls = 0

def _print_quota_warning():
    if wordsapi_calls == WARN_AT_80_PCT:
        print(f"\n⚠️   80 % of daily quota used ({wordsapi_calls}/{DAILY_QUOTA} calls).")
    elif wordsapi_calls == WARN_AT_95_PCT:
        print(f"\n🚨  95 % of daily quota used ({wordsapi_calls}/{DAILY_QUOTA} calls).")
        print("    The script will stop at the limit and resume tomorrow.\n")

# ── WordsAPI helper ───────────────────────────────────────────────────────────

def fetch_word(word: str) -> dict | None | str:
    """
    GET /words/{word}
    Returns:
      dict          — parsed response with at least a definition
      None          — word not found or no usable definition
      "RATE_LIMITED"— 429 response
    """
    global wordsapi_calls
    encoded = urllib.parse.quote(word.lower())
    conn = http.client.HTTPSConnection(WORDSAPI_HOST)
    try:
        conn.request(
            "GET", f"/words/{encoded}",
            headers={
                "X-RapidAPI-Key":  WORDSAPI_KEY,
                "X-RapidAPI-Host": WORDSAPI_HOST,
            },
        )
        res  = conn.getresponse()
        body = json.loads(res.read().decode("utf-8"))
        wordsapi_calls += 1
        _print_quota_warning()

        if res.status == 429:
            return "RATE_LIMITED"
        if res.status != 200:
            return None
        return body
    except Exception as e:
        print(f"  ⚠️  network error ({word}): {e}")
        return None
    finally:
        conn.close()

def best_result(results: list) -> dict | None:
    if not results:
        return None
    for pos in PREFERRED_POS:
        match = next((r for r in results if r.get("partOfSpeech") == pos), None)
        if match:
            return match
    return results[0]

def parse_word_entry(body: dict) -> dict | None:
    """Extract a clean entry dict from a full WordsAPI response body."""
    word = (body.get("word") or "").strip()
    if not word or " " in word:
        return None

    # Must have a Zipf frequency.
    # WordsAPI returns frequency as either {"zipf": 3.87, ...} or a bare float.
    freq = body.get("frequency")
    if isinstance(freq, dict):
        zipf = freq.get("zipf")
    elif isinstance(freq, (int, float)):
        zipf = float(freq)
    else:
        zipf = None
    if zipf is None:
        return None

    results = body.get("results") or []
    chosen  = best_result(results)
    if not chosen:
        return None

    definition = (chosen.get("definition") or "").strip()
    if not definition:
        return None

    part_of_speech = chosen.get("partOfSpeech") or "unknown"

    # Collect examples (prefer chosen sense, then other senses)
    raw_examples: list[str] = []
    for r in [chosen] + [r for r in results if r is not chosen]:
        for ex in (r.get("examples") or []):
            ex = ex.strip()
            if ex and ex not in raw_examples:
                raw_examples.append(ex)
            if len(raw_examples) >= MAX_EXAMPLES:
                break
        if len(raw_examples) >= MAX_EXAMPLES:
            break

    # Collect synonyms across all senses, deduplicated
    seen_syn: set = set()
    raw_synonyms: list[str] = []
    for r in results:
        for s in (r.get("synonyms") or []):
            s = s.strip()
            if s and s.lower() not in seen_syn:
                seen_syn.add(s.lower())
                raw_synonyms.append(s)

    return {
        "zipf":         float(zipf),
        "word":         word,
        "partOfSpeech": part_of_speech,
        "definition":   definition,
        "examples":     raw_examples[:MAX_EXAMPLES],
        "synonyms":     raw_synonyms[:MAX_SYNONYMS],
    }

# ── Free Dictionary helper ────────────────────────────────────────────────────

def fetch_free_dict(word: str) -> dict:
    """
    Calls the Free Dictionary API.
    Returns {examples, synonyms, origin} — empty lists / None on failure.
    """
    encoded = urllib.parse.quote(word.lower())
    conn = http.client.HTTPSConnection("api.dictionaryapi.dev")
    try:
        conn.request("GET", f"/api/v2/entries/en/{encoded}",
                     headers={"User-Agent": "VocabWidget/1.0"})
        res = conn.getresponse()
        if res.status != 200:
            return {"examples": [], "synonyms": [], "origin": None}

        entries = json.loads(res.read().decode("utf-8"))
        if not isinstance(entries, list) or not entries:
            return {"examples": [], "synonyms": [], "origin": None}

        raw_examples: list[str] = []
        raw_synonyms: list[str] = []
        origin: str | None      = None

        for entry in entries:
            if origin is None:
                o = (entry.get("origin") or "").strip()
                if o:
                    origin = o

            for meaning in (entry.get("meanings") or []):
                raw_synonyms.extend(meaning.get("synonyms") or [])
                for defn in (meaning.get("definitions") or []):
                    raw_synonyms.extend(defn.get("synonyms") or [])
                    ex = (defn.get("example") or "").strip()
                    if ex and ex not in raw_examples:
                        raw_examples.append(ex)

        seen: set = set()
        deduped: list[str] = []
        for s in raw_synonyms:
            s = s.strip()
            if s and s.lower() not in seen:
                seen.add(s.lower())
                deduped.append(s)

        return {
            "examples": raw_examples[:MAX_EXAMPLES],
            "synonyms": deduped[:MAX_SYNONYMS],
            "origin":   origin,
        }
    except Exception:
        return {"examples": [], "synonyms": [], "origin": None}
    finally:
        conn.close()

def fetch_free_dict_full(word: str) -> dict | None:
    """
    Calls the Free Dictionary API and returns a complete entry suitable for
    use as a fallback when WordsAPI has no data.
    Returns a dict with {partOfSpeech, definition, examples, synonyms, origin}
    or None if no usable definition was found.
    """
    encoded = urllib.parse.quote(word.lower())
    conn = http.client.HTTPSConnection("api.dictionaryapi.dev")
    try:
        conn.request("GET", f"/api/v2/entries/en/{encoded}",
                     headers={"User-Agent": "VocabWidget/1.0"})
        res = conn.getresponse()
        if res.status != 200:
            return None
        entries = json.loads(res.read().decode("utf-8"))
        if not isinstance(entries, list) or not entries:
            return None

        part_of_speech = "unknown"
        definition     = ""
        examples:  list[str] = []
        synonyms:  list[str] = []
        origin:    str | None = None

        for entry in entries:
            if origin is None:
                o = (entry.get("origin") or "").strip()
                if o:
                    origin = o
            for meaning in (entry.get("meanings") or []):
                pos = meaning.get("partOfSpeech", "")
                for defn in (meaning.get("definitions") or []):
                    d = (defn.get("definition") or "").strip()
                    if d and not definition:
                        definition     = d
                        part_of_speech = pos
                    ex = (defn.get("example") or "").strip()
                    if ex and ex not in examples:
                        examples.append(ex)
                    for s in (defn.get("synonyms") or []):
                        s = s.strip()
                        if s and s.lower() not in {x.lower() for x in synonyms}:
                            synonyms.append(s)
                for s in (meaning.get("synonyms") or []):
                    s = s.strip()
                    if s and s.lower() not in {x.lower() for x in synonyms}:
                        synonyms.append(s)

        if not definition:
            return None

        return {
            "partOfSpeech": part_of_speech,
            "definition":   definition,
            "examples":     examples[:MAX_EXAMPLES],
            "synonyms":     synonyms[:MAX_SYNONYMS],
            "origin":       origin,
        }
    except Exception:
        return None
    finally:
        conn.close()

def fetch_wordnet(word: str) -> dict | None:
    """
    WordNet fallback for words that neither WordsAPI nor Free Dictionary know.
    Returns {partOfSpeech, definition, examples, synonyms, origin} or None.
    Also tries stripping accents (naïve → naive) before giving up.
    """
    _pos_map = {'n': 'noun', 'v': 'verb', 'a': 'adjective', 's': 'adjective', 'r': 'adverb'}

    def _lookup(w):
        synsets = wn.synsets(w)
        if not synsets:
            return None
        ss      = synsets[0]
        pos     = _pos_map.get(ss.pos(), 'unknown')
        defn    = ss.definition()
        examples = ss.examples()[:MAX_EXAMPLES]
        synonyms = [
            lemma.name().replace('_', ' ')
            for s in synsets[:3]
            for lemma in s.lemmas()
            if lemma.name().lower() != w.lower()
        ]
        seen: set = set()
        deduped   = []
        for s in synonyms:
            if s.lower() not in seen:
                seen.add(s.lower())
                deduped.append(s)
        return {
            "partOfSpeech": pos,
            "definition":   defn,
            "examples":     examples,
            "synonyms":     deduped[:MAX_SYNONYMS],
            "origin":       None,
        }

    result = _lookup(word)
    if result:
        return result

    # Try stripping accents (naïve → naive, blasé → blase)
    import unicodedata
    normalized = unicodedata.normalize('NFD', word)
    ascii_word = ''.join(c for c in normalized if unicodedata.category(c) != 'Mn')
    if ascii_word != word:
        return _lookup(ascii_word)

    return None

# ── Stop helper ───────────────────────────────────────────────────────────────

def _stop_with_summary(reason: str):
    """Print progress summary and exit cleanly."""
    scored = {w: v for w, v in scores_cache.items() if v is not None}
    candidates_set = set(candidates)
    in_range = sum(
        1 for w, raw in scored.items()
        if w in candidates_set and raw is not None
        and (lambda e: e is not None and e["zipf"] <= MAX_ZIPF)(parse_word_entry(raw))
    )
    print(f"\n{'─'*68}")
    print(f"⛔  {reason}")
    print(f"{'─'*68}")
    print(f"\n  Candidates scored : {len(scores_cache)} / {len(candidates)}")
    print(f"  Valid scored words: {len(scored)}")
    print(f"  Within Zipf ≤ {MAX_ZIPF}: {in_range}")
    print(f"\n  WordsAPI calls this session: {wordsapi_calls}")
    print(f"\n  Re-run tomorrow to continue:")
    print(f"    python3 scripts/build_master_list.py")
    print(f"{'─'*68}\n")
    sys.exit(0)

# ── Phase 1: Score candidates via WordsAPI ────────────────────────────────────

print("\n── Phase 1: Scoring candidates via WordsAPI ─────────────────────────")

unscored = [w for w in candidates if w not in scores_cache]
already  = len(scores_cache)
print(f"  {already} already scored (cached) — skipping")
print(f"  {len(unscored)} candidates to score\n")

if unscored and not WORDSAPI_KEY:
    print("❌  Unscored words remain but WORDSAPI_KEY is not set.")
    print("    Export your key and re-run:  export WORDSAPI_KEY=your_key_here")
    sys.exit(1)

for i, candidate in enumerate(unscored):
    if wordsapi_calls >= DAILY_QUOTA:
        _stop_with_summary(f"Daily quota of {DAILY_QUOTA} requests reached.")

    result = fetch_word(candidate)

    if result == "RATE_LIMITED":
        _stop_with_summary("WordsAPI returned 429 — daily quota exhausted.")

    if result is None:
        scores_cache[candidate] = None
        SCORES_CACHE.write_text(json.dumps(scores_cache, indent=2, ensure_ascii=False))
        time.sleep(WORDSAPI_DELAY)
        continue

    entry = parse_word_entry(result)
    if entry is None:
        # Word had no usable definition/frequency — store None so we never
        # re-check it, but the raw body is lost intentionally (not useful).
        scores_cache[candidate] = None
        SCORES_CACHE.write_text(json.dumps(scores_cache, indent=2, ensure_ascii=False))
        time.sleep(WORDSAPI_DELAY)
        continue

    # Store the FULL raw API response verbatim.  parse_word_entry is called
    # again at selection time (Phase 2) so nothing is permanently discarded.
    scores_cache[candidate] = result
    SCORES_CACHE.write_text(json.dumps(scores_cache, indent=2, ensure_ascii=False))

    lvl_label = next(
        (l for l, b in LEVELS.items() if b["min"] <= entry["zipf"] <= b["max"]),
        "out-of-range"
    )
    print(f"  [{already+i+1:>5}/{len(candidates)}]  {candidate:<22} "
          f"zipf={entry['zipf']:.2f}  {lvl_label:<15} {entry['partOfSpeech']}")
    time.sleep(WORDSAPI_DELAY)

print(f"\n  ✅  Phase 1 complete  ({wordsapi_calls} WordsAPI calls this session)")

# ── Phase 2: Select best 500 per level ────────────────────────────────────────

print("\n── Phase 2: Selecting words ─────────────────────────────────────────")
print(f"  Including ALL words with Zipf ≤ {MAX_ZIPF} — no lower bound.")
print(f"  Words missing from WordsAPI cache → wordfreq Zipf + Free Dictionary definition.\n")

candidates_set = set(candidates)
selected:       list = []   # flat list of entry dicts
skipped_common  = 0
skipped_nodata  = 0
fallback_count  = 0

for w in candidates:
    raw = scores_cache.get(w)

    if raw is not None:
        # WordsAPI has data — use it directly.
        entry = parse_word_entry(raw)
        if entry is None:
            skipped_nodata += 1
            continue
        if entry["zipf"] > MAX_ZIPF:
            skipped_common += 1
            continue
        selected.append(entry)

    else:
        # No WordsAPI data — cascade through fallbacks:
        #   1. wordfreq for Zipf score
        #   2. Free Dictionary for definition
        #   3. WordNet if Free Dictionary has nothing
        zipf = zipf_frequency(w, "en")
        if zipf > MAX_ZIPF:
            skipped_common += 1
            continue
        # zipf == 0 means wordfreq has never seen this word — still try definitions.
        fd = fetch_free_dict_full(w)
        time.sleep(FREEDICT_DELAY)
        if fd is None:
            fd = fetch_wordnet(w)   # WordNet — no network call, instant
        if fd is None:
            skipped_nodata += 1
            continue
        final_zipf = zipf if zipf > 0 else 1.0   # conservative floor for truly unknown words
        selected.append({
            "zipf":         final_zipf,
            "word":         w,
            "partOfSpeech": fd["partOfSpeech"],
            "definition":   fd["definition"],
            "examples":     fd["examples"],
            "synonyms":     fd["synonyms"],
        })
        fallback_count += 1

print(f"  Selected:                    {len(selected)}")
print(f"  Skipped (too common >4.2):   {skipped_common}")
print(f"  Skipped (no definition):     {skipped_nodata}")
print(f"  Used Free Dict fallback:     {fallback_count}")

if not selected:
    print("\n❌  No words selected. Run Phase 1 to score candidates first.")
    sys.exit(1)

# ── Phase 3: Enrich with Free Dictionary ──────────────────────────────────────
# Note: words already fetched via fetch_free_dict_full in Phase 2 fallback
# already have good data — Phase 3 will skip them via the enrichment cache.

print("\n── Phase 3: Enriching with Free Dictionary ──────────────────────────")
print("   (adds examples, synonyms, and etymology from unlimited free API)\n")

all_word_keys = [entry["word"].lower() for entry in selected]
to_enrich     = [w for w in all_word_keys if w not in enrichment]

print(f"  {len(all_word_keys) - len(to_enrich)} already enriched — skipping")
print(f"  {len(to_enrich)} words to process\n")

for i, word_key in enumerate(to_enrich):
    print(f"  [{i+1:>4}/{len(to_enrich)}]  {word_key:<22}", end=" ", flush=True)
    fd = fetch_free_dict(word_key)
    enrichment[word_key] = fd
    ENRICHMENT_CACHE.write_text(json.dumps(enrichment, indent=2, ensure_ascii=False))

    filled = []
    if fd["examples"]: filled.append("ex")
    if fd["synonyms"]: filled.append("syn")
    if fd["origin"]:   filled.append("origin")
    print("filled: " + ", ".join(filled) if filled else "no new data")
    time.sleep(FREEDICT_DELAY)

print(f"\n  ✅  Phase 3 complete")

# ── Phase 4: Merge and assemble final word list ───────────────────────────────

print("\n── Phase 4: Assembling output ───────────────────────────────────────")

output: list = []
uid    = 0
stats  = {"total": 0, "full_ex": 0, "full_syn": 0, "has_origin": 0}

for entry in selected:
    word_key = entry["word"].lower()
    fd = enrichment.get(word_key, {"examples": [], "synonyms": [], "origin": None})

    # ── Merge examples ────────────────────────────────────────────────────────
    seen_ex: set = set()
    final_examples: list[str] = []
    for ex in list(entry.get("examples") or []) + list(fd.get("examples") or []):
        ex = ex.strip()
        if ex and ex.lower() not in seen_ex:
            seen_ex.add(ex.lower())
            final_examples.append(ex)
        if len(final_examples) >= MAX_EXAMPLES:
            break

    # ── Merge synonyms ────────────────────────────────────────────────────────
    seen_syn: set = set()
    final_synonyms: list[str] = []
    for s in list(entry.get("synonyms") or []) + list(fd.get("synonyms") or []):
        s = s.strip()
        if s and s.lower() not in seen_syn:
            seen_syn.add(s.lower())
            final_synonyms.append(s)
        if len(final_synonyms) >= MAX_SYNONYMS:
            break

    origin = fd.get("origin")

    stats["total"] += 1
    if len(final_examples) >= MAX_EXAMPLES: stats["full_ex"]    += 1
    if len(final_synonyms) >= 4:            stats["full_syn"]   += 1
    if origin:                              stats["has_origin"] += 1

    # isFeatured: Zipf 3.1–4.2 words make better lock-screen words —
    # challenging enough to be interesting, accessible enough to not alienate.
    is_featured = (3.1 <= entry["zipf"] <= 4.2)

    output.append({
        "id":           uid,
        "word":         entry["word"].capitalize(),
        "partOfSpeech": entry["partOfSpeech"],
        "definition":   entry["definition"],
        "examples":     final_examples,
        "synonyms":     final_synonyms,
        "origin":       origin,
        "frequency":    entry["zipf"],
        "isFeatured":   is_featured,
        "mastered":     False,
    })
    uid += 1

OUTPUT_FILE.write_text(json.dumps(output, indent=2, ensure_ascii=False))

# ── Summary ───────────────────────────────────────────────────────────────────

n = stats["total"]
print(f"\n── Results ──────────────────────────────────────────────────────────")
print(f"\n  Total words : {n}")
print(f"  2 examples  : {stats['full_ex']:>4} / {n}  ({stats['full_ex']/n*100:.0f}%)")
print(f"  4+ synonyms : {stats['full_syn']:>4} / {n}  ({stats['full_syn']/n*100:.0f}%)")
print(f"  etymology   : {stats['has_origin']:>4} / {n}  ({stats['has_origin']/n*100:.0f}%)")

print(f"\n✅  Written to {OUTPUT_FILE}")
print(f"\n   Review, then copy into the app:")
print(f"   cp words_generated.json VocabWidget/words.json")
