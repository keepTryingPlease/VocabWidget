#!/usr/bin/env python3
"""
build_master_list.py
────────────────────
Builds a clean 1 500-word master list for VocabWidget — 500 words per
difficulty level — by requesting random words from WordsAPI within each
Zipf frequency range, then filling any missing fields (examples,
synonyms, etymology) from the Free Dictionary API.

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
                       Stops once 500 unique words with definitions are
                       confirmed per level.

  Phase 2 — Enrich  : For every collected word, calls the Free Dictionary
                       API to fill any fields that WordsAPI left empty
                       (examples, synonyms, etymology).  Both sources are
                       merged so the final word always has the richest
                       possible data.

  Both phases write to disk after every single API call so the script
  can be safely interrupted and resumed at any point.  Re-running
  tomorrow after a rate-limit hit will only fetch what is still missing.

Zipf level boundaries
─────────────────────
  beginner       4.5 – 5.5
  intermediate   3.1 – 4.5
  advanced       1.9 – 3.1

WordsAPI daily quota (free tier = 2 500 requests / day)
────────────────────────────────────────────────────────
  The script tracks every request it makes this session and warns you
  at 80 % (2 000) and 95 % (2 375) of the daily limit.  If it hits
  the limit before finishing, it stops cleanly, prints a summary of
  what is still outstanding, and resumes correctly on the next run.

  Estimated usage:  ~1 650 WordsAPI calls  +  ~1 500 Free Dictionary
  calls (unlimited).  Completes in a single day on the free tier.

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
COLLECT_CACHE    = CACHE_DIR / "collected.json"
ENRICHMENT_CACHE = CACHE_DIR / "enrichment.json"
OUTPUT_FILE      = pathlib.Path("words_generated.json")

WORDS_PER_LEVEL      = 500
MAX_EXAMPLES         = 2    # try to reach this from both APIs combined
MAX_SYNONYMS         = 12   # ceiling after merging both APIs; keeps lists useful without being overwhelming
DAILY_QUOTA          = 2500
WARN_AT_80_PCT       = int(DAILY_QUOTA * 0.80)   # 2 000
WARN_AT_95_PCT       = int(DAILY_QUOTA * 0.95)   # 2 375

PREFERRED_POS = ["adjective", "verb", "noun", "adverb"]

LEVELS = {
    "beginner":     {"min": 4.5, "max": 5.5},
    "intermediate": {"min": 3.1, "max": 4.5},
    "advanced":     {"min": 1.9, "max": 3.1},
}

WORDSAPI_DELAY = 0.35
FREEDICT_DELAY = 0.30

# ── Validate environment ──────────────────────────────────────────────────────

if not WORDSAPI_KEY:
    print("❌  WORDSAPI_KEY environment variable is not set.")
    print("    Get a free key at: https://rapidapi.com/dpventures/api/wordsapiv1")
    print("    Then run:  export WORDSAPI_KEY=your_key_here")
    sys.exit(1)

# ── Load caches ───────────────────────────────────────────────────────────────

CACHE_DIR.mkdir(parents=True, exist_ok=True)

collected:  dict = json.loads(COLLECT_CACHE.read_text())    if COLLECT_CACHE.exists()    else {}
enrichment: dict = json.loads(ENRICHMENT_CACHE.read_text()) if ENRICHMENT_CACHE.exists() else {}

for lvl in LEVELS:
    if lvl not in collected:
        collected[lvl] = {}

# ── Request counter (tracks usage this session, not lifetime) ─────────────────

wordsapi_calls = 0

def _print_quota_warning():
    if wordsapi_calls == WARN_AT_80_PCT:
        print(f"\n⚠️   80 % of daily quota used ({wordsapi_calls}/{DAILY_QUOTA} calls).")
    elif wordsapi_calls == WARN_AT_95_PCT:
        print(f"\n🚨  95 % of daily quota used ({wordsapi_calls}/{DAILY_QUOTA} calls).")
        print("    The script will stop at the limit and resume tomorrow.\n")

# ── WordsAPI helper ───────────────────────────────────────────────────────────

def fetch_random_word(freq_min: float, freq_max: float) -> dict | None:
    """
    GET /words/?random=true&frequencyMin=X&frequencyMax=Y
    Returns the parsed response body, "RATE_LIMITED", or None on error.
    """
    global wordsapi_calls
    params = urllib.parse.urlencode({
        "random":       "true",
        "frequencyMin": freq_min,
        "frequencyMax": freq_max,
        "hasDetails":   "definitions",
    })
    conn = http.client.HTTPSConnection(WORDSAPI_HOST)
    try:
        conn.request(
            "GET", f"/words/?{params}",
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
        if res.status != 200 or "word" not in body:
            return None
        return body
    except Exception as e:
        print(f"  ⚠️  network error: {e}")
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
    word = (body.get("word") or "").strip()
    if not word or " " in word:   # skip phrases
        return None

    results = body.get("results") or []
    chosen  = best_result(results)
    if not chosen:
        return None

    definition = (chosen.get("definition") or "").strip()
    if not definition:
        return None

    part_of_speech = chosen.get("partOfSpeech") or "unknown"

    # Collect examples (prefer chosen sense, then others)
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

    # Collect synonyms across all results, deduplicated
    seen_syn: set = set()
    raw_synonyms: list[str] = []
    for r in results:
        for s in (r.get("synonyms") or []):
            s = s.strip()
            if s and s.lower() not in seen_syn:
                seen_syn.add(s.lower())
                raw_synonyms.append(s)

    return {
        "word":         word,
        "partOfSpeech": part_of_speech,
        "definition":   definition,
        "examples":     raw_examples[:MAX_EXAMPLES],
        "synonyms":     raw_synonyms[:MAX_SYNONYMS],
    }

# ── Free Dictionary helper ────────────────────────────────────────────────────

def fetch_free_dict(word: str) -> dict:
    """
    Calls the Free Dictionary API and returns a dict with:
      examples  : list of up to MAX_EXAMPLES sentences
      synonyms  : list of up to MAX_SYNONYMS synonyms
      origin    : etymology string or None

    Used to fill any fields that WordsAPI left empty.
    """
    encoded = urllib.parse.quote(word.lower())
    conn = http.client.HTTPSConnection("api.dictionaryapi.dev")
    try:
        conn.request("GET", f"/api/v2/entries/en/{encoded}",
                     headers={"User-Agent": "VocabWidget/1.0"})
        res  = conn.getresponse()
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

        # Deduplicate synonyms
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

def _stop_with_summary(reason: str):
    """Print a clear summary of outstanding work and exit."""
    print(f"\n{'─'*68}")
    print(f"⛔  {reason}")
    print(f"{'─'*68}")
    total_collected = sum(len(v) for v in collected.values())
    total_enriched  = len(enrichment)
    print(f"\n  Progress saved:")
    for lvl in LEVELS:
        n = len(collected.get(lvl, {}))
        bar = "█" * (n // 20) + f"  {n}/{WORDS_PER_LEVEL}"
        print(f"    {lvl:<15} {bar}")
    print(f"\n  Enriched so far : {total_enriched} / {total_collected} words")
    print(f"  WordsAPI calls  : {wordsapi_calls} this session")
    print(f"\n  Nothing was lost — re-run tomorrow to continue:")
    print(f"    python3 scripts/build_master_list.py")
    print(f"{'─'*68}\n")
    sys.exit(0)

# ── Phase 1: Collect random words per level ───────────────────────────────────

print("── Phase 1: Collecting random words ────────────────────────────────")

for level, bounds in LEVELS.items():
    already = len(collected[level])
    needed  = WORDS_PER_LEVEL - already
    if needed <= 0:
        print(f"  {level:<15} ✅  {already}/{WORDS_PER_LEVEL} — complete, skipping")
        continue

    print(f"\n  {level}  ({already} collected, need {needed} more)")

    while len(collected[level]) < WORDS_PER_LEVEL:
        if wordsapi_calls >= DAILY_QUOTA:
            _stop_with_summary(f"Daily quota of {DAILY_QUOTA} requests reached.")

        result = fetch_random_word(bounds["min"], bounds["max"])

        if result == "RATE_LIMITED":
            _stop_with_summary("WordsAPI returned 429 — daily quota exhausted.")

        if result is None:
            time.sleep(WORDSAPI_DELAY)
            continue

        entry = parse_word_entry(result)
        if entry is None:
            time.sleep(WORDSAPI_DELAY)
            continue

        key = entry["word"].lower()

        # Skip duplicates across all levels
        if any(key in collected[lvl] for lvl in LEVELS):
            time.sleep(WORDSAPI_DELAY)
            continue

        collected[level][key] = entry
        COLLECT_CACHE.write_text(json.dumps(collected, indent=2, ensure_ascii=False))

        count    = len(collected[level])
        has_ex   = "ex✓" if entry["examples"]  else "ex–"
        has_syn  = "syn✓" if entry["synonyms"] else "syn–"
        print(f"    [{count:>3}/{WORDS_PER_LEVEL}]  {entry['word']:<22} "
              f"{entry['partOfSpeech']:<12} {has_ex}  {has_syn}")
        time.sleep(WORDSAPI_DELAY)

print(f"\n  ✅  Phase 1 complete  ({wordsapi_calls} WordsAPI calls this session)")

# ── Phase 2: Enrich with Free Dictionary ──────────────────────────────────────

print("\n── Phase 2: Enriching with Free Dictionary ──────────────────────────")
print("   (fills missing examples, synonyms, and etymology)\n")

all_words_flat = [
    (word_key, level)
    for level, words in collected.items()
    for word_key in words
]

to_enrich = [(k, lvl) for k, lvl in all_words_flat if k not in enrichment]
print(f"  {len(all_words_flat) - len(to_enrich)} already enriched — skipping")
print(f"  {len(to_enrich)} words to process\n")

for i, (word_key, _) in enumerate(to_enrich):
    entry    = collected[_][word_key]
    needs_ex  = len(entry.get("examples", [])) < MAX_EXAMPLES
    needs_syn = len(entry.get("synonyms", [])) < MAX_SYNONYMS
    # Always fetch for origin; also fetch if examples or synonyms are short.
    # Free Dictionary is unlimited so there's no cost to calling it every time.

    print(f"  [{i+1:>4}/{len(to_enrich)}]  {word_key:<22}", end=" ", flush=True)
    fd = fetch_free_dict(word_key)
    enrichment[word_key] = fd
    ENRICHMENT_CACHE.write_text(json.dumps(enrichment, indent=2, ensure_ascii=False))

    filled = []
    if needs_ex  and fd["examples"]: filled.append("ex")
    if needs_syn and fd["synonyms"]: filled.append("syn")
    if fd["origin"]:                 filled.append("origin")
    print("filled: " + ", ".join(filled) if filled else "no new data")
    time.sleep(FREEDICT_DELAY)

print(f"\n  ✅  Phase 2 complete")

# ── Phase 3: Merge and assemble final word list ───────────────────────────────

print("\n── Phase 3: Assembling output ───────────────────────────────────────")

output: list = []
uid    = 0
stats  = {lvl: {"total": 0, "full_ex": 0, "full_syn": 0, "has_origin": 0}
          for lvl in LEVELS}

for level in LEVELS:
    for word_key, entry in collected[level].items():
        fd = enrichment.get(word_key, {"examples": [], "synonyms": [], "origin": None})

        # ── Merge examples ────────────────────────────────────────────────────
        # Combine both sources; keep up to MAX_EXAMPLES unique sentences.
        # WordsAPI examples come first, Free Dictionary fills any remaining slots.
        seen_ex: set = set()
        final_examples: list[str] = []
        for ex in list(entry.get("examples") or []) + list(fd.get("examples") or []):
            ex = ex.strip()
            if ex and ex.lower() not in seen_ex:
                seen_ex.add(ex.lower())
                final_examples.append(ex)
            if len(final_examples) >= MAX_EXAMPLES:
                break

        # ── Merge synonyms ────────────────────────────────────────────────────
        # Take every synonym from both APIs, deduplicate case-insensitively,
        # and keep up to MAX_SYNONYMS.  If WordsAPI has 2 and Free Dict has 7,
        # the result will have up to 9 unique synonyms (capped at MAX_SYNONYMS).
        seen_syn: set = set()
        final_synonyms: list[str] = []
        for s in list(entry.get("synonyms") or []) + list(fd.get("synonyms") or []):
            s = s.strip()
            if s and s.lower() not in seen_syn:
                seen_syn.add(s.lower())
                final_synonyms.append(s)
            if len(final_synonyms) >= MAX_SYNONYMS:
                break

        origin = fd.get("origin")   # WordsAPI rarely carries etymology

        s = stats[level]
        s["total"] += 1
        if len(final_examples) >= MAX_EXAMPLES: s["full_ex"]     += 1
        if len(final_synonyms) >= 4:            s["full_syn"]    += 1
        if origin:                              s["has_origin"]  += 1

        output.append({
            "id":           uid,
            "word":         entry["word"].capitalize(),
            "partOfSpeech": entry["partOfSpeech"],
            "definition":   entry["definition"],
            "examples":     final_examples,
            "synonyms":     final_synonyms,
            "origin":       origin,
            "level":        level,
            "isFeatured":   False,
            "mastered":     False,
        })
        uid += 1

OUTPUT_FILE.write_text(json.dumps(output, indent=2, ensure_ascii=False))

# ── Summary ───────────────────────────────────────────────────────────────────

print(f"\n── Results ──────────────────────────────────────────────────────────")
for lvl, s in stats.items():
    n = s["total"]
    print(f"\n  {lvl}  ({n} words)")
    print(f"    2 examples : {s['full_ex']:>3} / {n}  ({s['full_ex']/n*100:.0f}%)")
    print(f"    4+ synonyms: {s['full_syn']:>3} / {n}  ({s['full_syn']/n*100:.0f}%)")
    print(f"    etymology  : {s['has_origin']:>3} / {n}  ({s['has_origin']/n*100:.0f}%)")

print(f"\n  Total: {len(output)} words")
print(f"\n✅  Written to {OUTPUT_FILE}")
print(f"\n   Review, then copy into the app:")
print(f"   cp words_generated.json VocabWidget/words.json")
print(f"   rm words_generated.json")
