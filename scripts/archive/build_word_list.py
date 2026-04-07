#!/usr/bin/env python3
"""
build_word_list.py
──────────────────
Builds the single-deck VocabWidget word list from scripts/word_candidates_single.txt.

No levels.  Every word that passes WordsAPI scoring goes into one pool.
A continuous `frequency` (Zipf score, 1–7, higher = more common / easier) is
stored on each word so the app can order and adapt to the user's skill level
without discrete level buckets.

Output schema (per word)
────────────────────────
  id            sequential integer
  word          capitalised string
  partOfSpeech  "noun" / "adjective" / "verb" / etc.
  definition    string
  examples      list of up to 2 example sentences
  synonyms      list of up to 12 synonyms
  origin        etymology string, or null
  frequency     float  — Zipf score (1–7).  Higher = more common / easier.
                         Typical range for vocab words: 2.0 – 5.0.
  isFeatured    bool   — true for words in Zipf 3.2–5.0 (widget word-of-the-day pool)
  mastered      false

How it works
────────────
  Phase 1 — Score   : Reads every word from scripts/word_candidates_single.txt,
                      calls WordsAPI GET /words/{word} for each.  The full raw
                      response is cached after every call so the script can be
                      paused and resumed across days.

  Phase 2 — Select  : Keeps every word that returned a valid definition and Zipf
                      score.  Sorted by Zipf descending (most recognisable first).
                      An optional --max-words cap takes the top N.

  Phase 3 — Enrich  : Calls the Free Dictionary API (unlimited, no key) to
                      extend examples, synonyms, and etymology.

  Phase 4 — Assemble: Writes words_generated.json ready to drop into the app.

isFeatured / widget word-of-the-day
────────────────────────────────────
  Words with Zipf 3.2–5.0 are marked isFeatured.  This range covers well-known
  but genuinely interesting vocabulary — not everyday words ("the", "make") and
  not so obscure they'd confuse a casual reader seeing them on their home screen.

  At that threshold, roughly 40–60 % of the final list will be featured,
  giving the widget a pool of ~500–800 words before it repeats.

Prerequisites
─────────────
  Python 3.10+  (stdlib + nltk — already installed for deduplication step)
  export WORDSAPI_KEY=your_key

Run from the project root (VocabWidget/VocabWidget/):
  python3 scripts/build_word_list.py --quota 25000

When done, copy into the app:
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

# ── CLI arguments ─────────────────────────────────────────────────────────────

_parser = argparse.ArgumentParser(
    description="Build the VocabWidget single-deck word list.",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog="""
Examples
────────
  # Score all candidates, keep everything, all in one shot:
  python3 scripts/build_word_list.py --quota 25000

  # Cap output at 2000 words (highest Zipf = most recognisable selected first):
  python3 scripts/build_word_list.py --quota 25000 --max-words 2000

  # Slower if hitting 429 errors — increase delay:
  python3 scripts/build_word_list.py --quota 25000 --delay 1.0
""",
)
_parser.add_argument(
    "--quota", type=int, default=2500, metavar="N",
    help="Maximum WordsAPI calls for this session (default: 2500).",
)
_parser.add_argument(
    "--max-words", type=int, default=0, metavar="N", dest="max_words",
    help="Cap the final word list at N words, sorted by Zipf descending "
         "(default: 0 = keep all passing words).",
)
_parser.add_argument(
    "--delay", type=float, default=0.7, metavar="SEC",
    help="Seconds between WordsAPI calls (default: 0.7).",
)
_args = _parser.parse_args()

# ── Config ────────────────────────────────────────────────────────────────────

WORDSAPI_KEY  = os.environ.get("WORDSAPI_KEY", "")
WORDSAPI_HOST = "wordsapiv1.p.rapidapi.com"

CANDIDATES_FILE  = pathlib.Path("scripts/word_candidates_single.txt")
CACHE_DIR        = pathlib.Path("scripts/cache")
SCORES_CACHE     = CACHE_DIR / "scores_single.json"
ENRICHMENT_CACHE = CACHE_DIR / "enrichment_single.json"
OUTPUT_FILE      = pathlib.Path("words_generated.json")

MAX_EXAMPLES   = 2
MAX_SYNONYMS   = 12
DAILY_QUOTA    = _args.quota
WARN_AT_80_PCT = int(DAILY_QUOTA * 0.80)
WARN_AT_95_PCT = int(DAILY_QUOTA * 0.95)
WORDSAPI_DELAY = _args.delay
FREEDICT_DELAY = 0.30

# Words with Zipf in this range are marked isFeatured for the widget.
FEATURED_ZIPF_MIN = 3.2
FEATURED_ZIPF_MAX = 5.0

PREFERRED_POS = ["adjective", "verb", "noun", "adverb"]

print(f"\n  Quota this session : {DAILY_QUOTA:,} WordsAPI calls")
print(f"  Request delay      : {WORDSAPI_DELAY}s  (~{int(60/WORDSAPI_DELAY)} req/min)")
print(f"  Max words output   : {_args.max_words if _args.max_words else 'all passing'}")
print(f"  isFeatured range   : Zipf {FEATURED_ZIPF_MIN}–{FEATURED_ZIPF_MAX}")

# ── Validate environment ──────────────────────────────────────────────────────

if not WORDSAPI_KEY:
    print("\n❌  WORDSAPI_KEY environment variable is not set.")
    print("    export WORDSAPI_KEY=your_key_here")
    sys.exit(1)

if not CANDIDATES_FILE.exists():
    print(f"\n❌  Candidate list not found: {CANDIDATES_FILE}")
    sys.exit(1)

# ── Load candidates ───────────────────────────────────────────────────────────

def load_candidates() -> list[str]:
    seen: set = set()
    words: list[str] = []
    for line in CANDIDATES_FILE.read_text(encoding="utf-8").splitlines():
        w = line.strip().lower()
        if not w or w.startswith("#"):
            continue
        if w not in seen:
            seen.add(w)
            words.append(w)
    return words

candidates = load_candidates()
print(f"  Loaded {len(candidates)} candidate words\n")

# ── Load caches ───────────────────────────────────────────────────────────────

CACHE_DIR.mkdir(parents=True, exist_ok=True)

scores_cache: dict = (
    json.loads(SCORES_CACHE.read_text()) if SCORES_CACHE.exists() else {}
)
enrichment: dict = (
    json.loads(ENRICHMENT_CACHE.read_text()) if ENRICHMENT_CACHE.exists() else {}
)

# ── Request counter ───────────────────────────────────────────────────────────

wordsapi_calls = 0

def _quota_warning():
    if wordsapi_calls == WARN_AT_80_PCT:
        print(f"\n⚠️   80 % of quota used ({wordsapi_calls}/{DAILY_QUOTA}).")
    elif wordsapi_calls == WARN_AT_95_PCT:
        print(f"\n🚨  95 % of quota used ({wordsapi_calls}/{DAILY_QUOTA}). Stopping soon.\n")

# ── WordsAPI helpers ──────────────────────────────────────────────────────────

def fetch_word(word: str) -> dict | None | str:
    global wordsapi_calls
    encoded = urllib.parse.quote(word.lower())
    conn = http.client.HTTPSConnection(WORDSAPI_HOST)
    try:
        conn.request("GET", f"/words/{encoded}", headers={
            "X-RapidAPI-Key":  WORDSAPI_KEY,
            "X-RapidAPI-Host": WORDSAPI_HOST,
        })
        res  = conn.getresponse()
        body = json.loads(res.read().decode("utf-8"))
        wordsapi_calls += 1
        _quota_warning()
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
    """Extract a clean scored entry from a raw WordsAPI response body."""
    word = (body.get("word") or "").strip()
    if not word or " " in word:
        return None

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

# ── Stop helper ───────────────────────────────────────────────────────────────

def _stop_with_summary(reason: str):
    scored_valid = sum(1 for v in scores_cache.values() if v is not None)
    print(f"\n{'─'*60}")
    print(f"⛔  {reason}")
    print(f"{'─'*60}")
    print(f"  Candidates checked : {len(scores_cache)} / {len(candidates)}")
    print(f"  Valid scored words : {scored_valid}")
    print(f"  WordsAPI calls     : {wordsapi_calls}")
    print(f"\n  Resume tomorrow:")
    print(f"    python3 scripts/build_word_list.py --quota {DAILY_QUOTA}")
    print(f"{'─'*60}\n")
    sys.exit(0)

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1 — Score candidates via WordsAPI
# ─────────────────────────────────────────────────────────────────────────────

print("── Phase 1: Scoring candidates via WordsAPI ─────────────────────────")

unscored = [w for w in candidates if w not in scores_cache]
print(f"  {len(scores_cache)} already scored (cached) — skipping")
print(f"  {len(unscored)} candidates to score\n")

for i, candidate in enumerate(unscored):
    if wordsapi_calls >= DAILY_QUOTA:
        _stop_with_summary(f"Daily quota of {DAILY_QUOTA:,} requests reached.")

    result = fetch_word(candidate)

    if result == "RATE_LIMITED":
        _stop_with_summary("WordsAPI returned 429 — rate limited.")

    if result is None:
        scores_cache[candidate] = None
        SCORES_CACHE.write_text(json.dumps(scores_cache, indent=2, ensure_ascii=False))
        time.sleep(WORDSAPI_DELAY)
        continue

    entry = parse_word_entry(result)
    if entry is None:
        scores_cache[candidate] = None
        SCORES_CACHE.write_text(json.dumps(scores_cache, indent=2, ensure_ascii=False))
        time.sleep(WORDSAPI_DELAY)
        continue

    scores_cache[candidate] = result
    SCORES_CACHE.write_text(json.dumps(scores_cache, indent=2, ensure_ascii=False))

    featured_marker = "★" if FEATURED_ZIPF_MIN <= entry["zipf"] <= FEATURED_ZIPF_MAX else " "
    print(f"  [{len(scores_cache):>5}/{len(candidates)}]  {featured_marker} "
          f"{candidate:<22}  zipf={entry['zipf']:.2f}  {entry['partOfSpeech']}")
    time.sleep(WORDSAPI_DELAY)

print(f"\n  ✅  Phase 1 complete  ({wordsapi_calls} WordsAPI calls this session)")

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Select words
# ─────────────────────────────────────────────────────────────────────────────

print("\n── Phase 2: Selecting words ──────────────────────────────────────────")

all_scored: list[dict] = []
for w, raw in scores_cache.items():
    if raw is None:
        continue
    entry = parse_word_entry(raw)
    if entry is not None:
        all_scored.append(entry)

# Sort by Zipf descending: most recognisable / accessible words first.
all_scored.sort(key=lambda e: e["zipf"], reverse=True)

if _args.max_words and len(all_scored) > _args.max_words:
    selected = all_scored[:_args.max_words]
    print(f"  {len(all_scored)} valid words — capped to {_args.max_words} by --max-words")
else:
    selected = all_scored
    print(f"  {len(selected)} valid words selected (no cap)")

featured_count = sum(
    1 for e in selected
    if FEATURED_ZIPF_MIN <= e["zipf"] <= FEATURED_ZIPF_MAX
)
print(f"  {featured_count} marked isFeatured (widget pool)  "
      f"[Zipf {FEATURED_ZIPF_MIN}–{FEATURED_ZIPF_MAX}]")

if not selected:
    print("\n❌  No words selected — run Phase 1 to score candidates first.")
    sys.exit(1)

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Enrich with Free Dictionary
# ─────────────────────────────────────────────────────────────────────────────

print("\n── Phase 3: Enriching with Free Dictionary ──────────────────────────")

to_enrich = [e["word"].lower() for e in selected if e["word"].lower() not in enrichment]
print(f"  {len(selected) - len(to_enrich)} already enriched — skipping")
print(f"  {len(to_enrich)} words to process\n")

for i, word_key in enumerate(to_enrich):
    print(f"  [{i+1:>4}/{len(to_enrich)}]  {word_key:<22}", end=" ", flush=True)
    fd = fetch_free_dict(word_key)
    enrichment[word_key] = fd
    ENRICHMENT_CACHE.write_text(json.dumps(enrichment, indent=2, ensure_ascii=False))
    filled = [k for k in ("examples", "synonyms", "origin") if fd.get(k)]
    print("filled: " + ", ".join(filled) if filled else "no new data")
    time.sleep(FREEDICT_DELAY)

print(f"\n  ✅  Phase 3 complete")

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4 — Assemble final word list
# ─────────────────────────────────────────────────────────────────────────────

print("\n── Phase 4: Assembling output ───────────────────────────────────────")

output: list = []
stats = {"total": 0, "full_ex": 0, "full_syn": 0, "has_origin": 0, "featured": 0}

for uid, entry in enumerate(selected):
    word_key = entry["word"].lower()
    fd = enrichment.get(word_key, {"examples": [], "synonyms": [], "origin": None})

    # Merge examples
    seen_ex: set = set()
    final_examples: list[str] = []
    for ex in list(entry.get("examples") or []) + list(fd.get("examples") or []):
        ex = ex.strip()
        if ex and ex.lower() not in seen_ex:
            seen_ex.add(ex.lower())
            final_examples.append(ex)
        if len(final_examples) >= MAX_EXAMPLES:
            break

    # Merge synonyms
    seen_syn: set = set()
    final_synonyms: list[str] = []
    for s in list(entry.get("synonyms") or []) + list(fd.get("synonyms") or []):
        s = s.strip()
        if s and s.lower() not in seen_syn:
            seen_syn.add(s.lower())
            final_synonyms.append(s)
        if len(final_synonyms) >= MAX_SYNONYMS:
            break

    origin     = fd.get("origin")
    zipf       = entry["zipf"]
    is_featured = FEATURED_ZIPF_MIN <= zipf <= FEATURED_ZIPF_MAX

    stats["total"] += 1
    if len(final_examples) >= MAX_EXAMPLES: stats["full_ex"]    += 1
    if len(final_synonyms) >= 4:            stats["full_syn"]   += 1
    if origin:                              stats["has_origin"] += 1
    if is_featured:                         stats["featured"]   += 1

    output.append({
        "id":           uid,
        "word":         entry["word"].capitalize(),
        "partOfSpeech": entry["partOfSpeech"],
        "definition":   entry["definition"],
        "examples":     final_examples,
        "synonyms":     final_synonyms,
        "origin":       origin,
        "frequency":    round(zipf, 2),
        "isFeatured":   is_featured,
        "mastered":     False,
    })

OUTPUT_FILE.write_text(json.dumps(output, indent=2, ensure_ascii=False))

# ── Summary ───────────────────────────────────────────────────────────────────

n = stats["total"]
print(f"\n── Results ──────────────────────────────────────────────────────────")
print(f"\n  Total words        : {n}")
print(f"  isFeatured (widget): {stats['featured']}  ({stats['featured']/n*100:.0f}%)")
print(f"  2 examples         : {stats['full_ex']}  ({stats['full_ex']/n*100:.0f}%)")
print(f"  4+ synonyms        : {stats['full_syn']}  ({stats['full_syn']/n*100:.0f}%)")
print(f"  Etymology          : {stats['has_origin']}  ({stats['has_origin']/n*100:.0f}%)")
print(f"\n✅  Written to {OUTPUT_FILE}")
print(f"\n   Copy into the app:")
print(f"   cp words_generated.json VocabWidget/words.json")
