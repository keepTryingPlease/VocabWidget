#!/usr/bin/env python3
"""
enrich_words.py  —  VocabWidget word enrichment pipeline
─────────────────────────────────────────────────────────
Reads new words from  scripts/input/words_to_add.txt
Skips any word already in  VocabWidget/words.json
Enriches each word via a free-first cascade
Writes a preview to   words_generated.json  (review before merging)
Backs up master to    scripts/backup/
Merges into master on your approval

  Input file   : scripts/input/words_to_add.txt   ← add new words here
  Master file  : VocabWidget/words.json            ← the live app database
  Preview file : words_generated.json              ← review this before merging
  Backup dir   : scripts/backup/
  Skipped file : scripts/output/skipped_words.txt

Enrichment cascade  (free / offline first, paid last):
  1. wordfreq      – Zipf frequency              (offline, always free)
  2. WordNet/NLTK  – definition, POS,             (offline, always free)
                     synonyms, examples
  3. Free Dict API – fill any gaps + etymology    (free, no key needed)
  4. Wiktionary    – etymology fallback            (free, no key needed)
  5. WordsAPI      – last resort for definition    (free tier 2500/day;
                     only if still missing          set WORDSAPI_KEY env var)

Run from the project root:
  python3 scripts/enrich_words.py
  python3 scripts/enrich_words.py --no-wordsapi   (skip paid API entirely)
"""

import argparse
import json
import os
import pathlib
import re
import sys
import time
import unicodedata
import http.client
import urllib.parse
from collections import Counter
from datetime import datetime

from wordfreq import zipf_frequency
from nltk.corpus import wordnet as wn


# ══════════════════════════════════════════════════════════════════════════════
#  PATHS
# ══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR   = pathlib.Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent

INPUT_FILE       = SCRIPT_DIR / "input"  / "words_to_add.txt"
MASTER_FILE      = PROJECT_ROOT / "VocabWidget" / "words.json"
PREVIEW_FILE     = PROJECT_ROOT / "words_generated.json"
BACKUP_DIR       = SCRIPT_DIR / "backup"
OUTPUT_DIR       = SCRIPT_DIR / "output"
CACHE_DIR        = SCRIPT_DIR / "cache"
SKIPPED_FILE     = OUTPUT_DIR / "skipped_words.txt"

WORDSAPI_CACHE   = CACHE_DIR / "wordsapi_cache.json"
FREEDICT_CACHE   = CACHE_DIR / "freedict_cache.json"
WIKTIONARY_CACHE = CACHE_DIR / "wiktionary_cache.json"


# ══════════════════════════════════════════════════════════════════════════════
#  CONFIG
# ══════════════════════════════════════════════════════════════════════════════

MAX_EXAMPLES     = 2      # target 2 example sentences per word
TARGET_SYNONYMS  = 5      # aim for at least this many synonyms
MAX_SYNONYMS     = 8      # hard ceiling
MAX_ZIPF         = 4.2    # words above this are too common for vocab learning
MAX_BACKUPS      = 5      # how many backup copies of words.json to keep
FREEDICT_DELAY   = 0.25   # seconds between Free Dictionary API calls
WIKTIONARY_DELAY = 0.25   # seconds between Wiktionary API calls
WORDSAPI_DELAY   = 0.7    # seconds between WordsAPI calls
WORDSAPI_HOST    = "wordsapiv1.p.rapidapi.com"


# ══════════════════════════════════════════════════════════════════════════════
#  CLI ARGUMENTS
# ══════════════════════════════════════════════════════════════════════════════

_parser = argparse.ArgumentParser(
    description="Enrich new VocabWidget words and merge into words.json."
)
_parser.add_argument(
    "--no-wordsapi", action="store_true",
    help="Skip WordsAPI entirely (avoids using paid API quota)."
)
args = _parser.parse_args()
WORDSAPI_KEY = "" if args.no_wordsapi else os.environ.get("WORDSAPI_KEY", "")


# ══════════════════════════════════════════════════════════════════════════════
#  STARTUP
# ══════════════════════════════════════════════════════════════════════════════

for d in (CACHE_DIR, BACKUP_DIR, OUTPUT_DIR):
    d.mkdir(parents=True, exist_ok=True)

print("\n" + "═" * 62)
print("  VocabWidget  —  Word Enrichment Pipeline")
print("═" * 62)
print(f"  Input file   : {INPUT_FILE.relative_to(PROJECT_ROOT)}")
print(f"  Master file  : {MASTER_FILE.relative_to(PROJECT_ROOT)}")
print(f"  Preview file : {PREVIEW_FILE.relative_to(PROJECT_ROOT)}")
if args.no_wordsapi:
    print(f"  WordsAPI     : disabled  (--no-wordsapi flag)")
elif WORDSAPI_KEY:
    print(f"  WordsAPI     : enabled  (key found in WORDSAPI_KEY)")
else:
    print(f"  WordsAPI     : disabled  (WORDSAPI_KEY not set)")
print()


# ══════════════════════════════════════════════════════════════════════════════
#  CACHE HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def _load_cache(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}

def _save_cache(data: dict, path: pathlib.Path):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")

wordsapi_cache   = _load_cache(WORDSAPI_CACHE)
freedict_cache   = _load_cache(FREEDICT_CACHE)
wiktionary_cache = _load_cache(WIKTIONARY_CACHE)


# ══════════════════════════════════════════════════════════════════════════════
#  LOAD MASTER  &  INPUT
# ══════════════════════════════════════════════════════════════════════════════

if not MASTER_FILE.exists():
    print(f"❌  Master file not found: {MASTER_FILE}")
    sys.exit(1)

master_words: list = json.loads(MASTER_FILE.read_text(encoding="utf-8"))
master_set: set    = {w["word"].lower() for w in master_words}
print(f"  Master word list : {len(master_words):>5} words already present")

if not INPUT_FILE.exists():
    print(f"\n❌  Input file not found: {INPUT_FILE}")
    print(f"    Create it with one word per line (plain text, # for comments).")
    sys.exit(1)

raw_input: list[str] = []
for line in INPUT_FILE.read_text(encoding="utf-8").splitlines():
    w = line.strip().lower()
    if w and not w.startswith("#"):
        raw_input.append(w)

new_words = [w for w in raw_input if w not in master_set]
skipped_already = len(raw_input) - len(new_words)
print(f"  Input list       : {len(raw_input):>5} words")
print(f"  Already in master: {skipped_already:>5} words  (skipping)")
print(f"  To process       : {len(new_words):>5} words\n")

if not new_words:
    print("✅  Nothing to do — all input words are already in the master list.")
    sys.exit(0)


# ══════════════════════════════════════════════════════════════════════════════
#  BACKUP
# ══════════════════════════════════════════════════════════════════════════════

def backup_master():
    """Copy words.json to scripts/backup/ with a timestamp. Prunes oldest if > MAX_BACKUPS."""
    stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    dest  = BACKUP_DIR / f"words_{stamp}.json"
    dest.write_bytes(MASTER_FILE.read_bytes())
    print(f"  📦  Backup saved : {dest.name}")
    backups = sorted(BACKUP_DIR.glob("words_*.json"))
    for old in backups[:-MAX_BACKUPS]:
        old.unlink()
        print(f"  🗑   Pruned old  : {old.name}")


# ══════════════════════════════════════════════════════════════════════════════
#  SHARED UTILITY
# ══════════════════════════════════════════════════════════════════════════════

def _strip_accents(word: str) -> str:
    """naïve → naive, blasé → blase."""
    n = unicodedata.normalize("NFD", word)
    return "".join(c for c in n if unicodedata.category(c) != "Mn")

def _merge_into(target: list, source: list, cap: int):
    """Append unique items from source into target (case-insensitive dedup) up to cap."""
    seen = {x.lower() for x in target}
    for item in source:
        if len(target) >= cap:
            break
        if item and item.lower() not in seen:
            target.append(item)
            seen.add(item.lower())


# ══════════════════════════════════════════════════════════════════════════════
#  SOURCE 1 — wordfreq  (offline, free)
# ══════════════════════════════════════════════════════════════════════════════

def get_zipf(word: str) -> float:
    """Returns Zipf frequency score, or 0.0 if unknown. Tries accent-stripped form."""
    z = zipf_frequency(word, "en")
    if z == 0.0:
        z = zipf_frequency(_strip_accents(word), "en")
    return z


# ══════════════════════════════════════════════════════════════════════════════
#  SOURCE 2 — WordNet / NLTK  (offline, free)
# ══════════════════════════════════════════════════════════════════════════════

_POS_MAP       = {"n": "noun", "v": "verb", "a": "adjective", "s": "adjective", "r": "adverb"}
_POS_PREFERRED = ("a", "s", "v", "n", "r")   # adjective first, adverb last

def get_wordnet_entry(word: str) -> dict | None:
    """
    Returns {definition, pos, examples, synonyms} from WordNet, or None.
    Tries accent-stripped form if the original fails.
    """
    def _lookup(w: str) -> dict | None:
        synsets = wn.synsets(w)
        if not synsets:
            return None
        # Re-order: prefer adjective → verb → noun → adverb
        for preferred_pos in _POS_PREFERRED:
            match = next((s for s in synsets if s.pos() == preferred_pos), None)
            if match:
                synsets.insert(0, synsets.pop(synsets.index(match)))
                break
        ss       = synsets[0]
        pos      = _POS_MAP.get(ss.pos(), "unknown")
        definition = ss.definition()
        examples   = ss.examples()[:MAX_EXAMPLES]
        seen_syn: set = set()
        synonyms: list[str] = []
        for s in synsets[:4]:
            for lemma in s.lemmas():
                name = lemma.name().replace("_", " ")
                if name.lower() != w.lower() and name.lower() not in seen_syn:
                    seen_syn.add(name.lower())
                    synonyms.append(name)
        return {"definition": definition, "pos": pos,
                "examples": examples, "synonyms": synonyms[:MAX_SYNONYMS]}

    return _lookup(word) or _lookup(_strip_accents(word))


# ══════════════════════════════════════════════════════════════════════════════
#  SOURCE 3 — Free Dictionary API  (free, no key)
# ══════════════════════════════════════════════════════════════════════════════

def fetch_freedict(word: str) -> dict | None:
    """
    Calls api.dictionaryapi.dev for definition, POS, examples, synonyms, etymology.
    Results are cached in scripts/cache/freedict_cache.json.
    Returns {definition, pos, examples, synonyms, origin} or None.
    """
    key = word.lower()
    if key in freedict_cache:
        return freedict_cache[key] or None

    conn = http.client.HTTPSConnection("api.dictionaryapi.dev")
    try:
        conn.request("GET", f"/api/v2/entries/en/{urllib.parse.quote(key)}",
                     headers={"User-Agent": "VocabWidget/1.0"})
        res = conn.getresponse()
        if res.status != 200:
            freedict_cache[key] = None
            _save_cache(freedict_cache, FREEDICT_CACHE)
            return None

        entries = json.loads(res.read().decode("utf-8"))
        if not isinstance(entries, list) or not entries:
            freedict_cache[key] = None
            _save_cache(freedict_cache, FREEDICT_CACHE)
            return None

        definition = pos = ""
        examples:  list[str] = []
        synonyms:  list[str] = []
        origin:    str | None = None

        for entry in entries:
            if origin is None:
                o = (entry.get("origin") or "").strip()
                if o:
                    origin = o
            for meaning in (entry.get("meanings") or []):
                p = meaning.get("partOfSpeech", "")
                for defn_obj in (meaning.get("definitions") or []):
                    d = (defn_obj.get("definition") or "").strip()
                    if d and not definition:
                        definition, pos = d, p
                    ex = (defn_obj.get("example") or "").strip()
                    if ex and ex not in examples:
                        examples.append(ex)
                    for s in (defn_obj.get("synonyms") or []):
                        if s.strip() and s.lower() not in {x.lower() for x in synonyms}:
                            synonyms.append(s.strip())
                for s in (meaning.get("synonyms") or []):
                    if s.strip() and s.lower() not in {x.lower() for x in synonyms}:
                        synonyms.append(s.strip())

        if not definition:
            freedict_cache[key] = None
            _save_cache(freedict_cache, FREEDICT_CACHE)
            return None

        result = {"definition": definition, "pos": pos,
                  "examples": examples[:MAX_EXAMPLES],
                  "synonyms": synonyms[:MAX_SYNONYMS], "origin": origin}
        freedict_cache[key] = result
        _save_cache(freedict_cache, FREEDICT_CACHE)
        return result

    except Exception:
        freedict_cache[key] = None
        _save_cache(freedict_cache, FREEDICT_CACHE)
        return None
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════════════════════════
#  SOURCE 4 — Wiktionary  (etymology only, free, no key)
# ══════════════════════════════════════════════════════════════════════════════

def fetch_wiktionary_etymology(word: str) -> str | None:
    """
    Extracts the etymology string from Wiktionary's English section.
    Results are cached in scripts/cache/wiktionary_cache.json.
    Returns a plain-text etymology string or None.
    """
    key = word.lower()
    if key in wiktionary_cache:
        return wiktionary_cache[key] or None

    params = urllib.parse.urlencode({
        "action": "query", "titles": key,
        "prop": "revisions", "rvprop": "content",
        "rvslots": "*", "format": "json",
    })
    conn = http.client.HTTPSConnection("en.wiktionary.org")
    try:
        conn.request("GET", f"/w/api.php?{params}",
                     headers={"User-Agent": "VocabWidget/1.0"})
        res  = conn.getresponse()
        if res.status != 200:
            wiktionary_cache[key] = None
            _save_cache(wiktionary_cache, WIKTIONARY_CACHE)
            return None

        data  = json.loads(res.read().decode("utf-8"))
        pages = data.get("query", {}).get("pages", {})
        if "-1" in pages:
            wiktionary_cache[key] = None
            _save_cache(wiktionary_cache, WIKTIONARY_CACHE)
            return None

        page     = next(iter(pages.values()))
        rev      = (page.get("revisions") or [{}])[0]
        wikitext = (rev.get("slots", {}).get("main", {}).get("*")
                    or rev.get("*") or "")
        if not wikitext:
            wiktionary_cache[key] = None
            _save_cache(wiktionary_cache, WIKTIONARY_CACHE)
            return None

        # Isolate the English section, then find etymology
        en_match   = re.search(r"==English==\s*(.*?)(?:\n==[^=]|\Z)", wikitext, re.DOTALL)
        section    = en_match.group(1) if en_match else wikitext
        etym_match = re.search(
            r"===?\s*Etymology[^=]*\s*===?\s*(.*?)(?:\n===|\n==|\Z)", section, re.DOTALL
        )
        if not etym_match:
            wiktionary_cache[key] = None
            _save_cache(wiktionary_cache, WIKTIONARY_CACHE)
            return None

        raw = etym_match.group(1).strip()
        raw = re.sub(r"\{\{[^}]+\}\}", "", raw)                        # templates
        raw = re.sub(r"\[\[(?:[^|\]]+\|)?([^\]]+)\]\]", r"\1", raw)   # wikilinks
        raw = re.sub(r"'{2,}", "", raw)                                 # bold/italic
        raw = re.sub(r"<[^>]+>", "", raw)                              # HTML tags
        raw = re.sub(r"\s+", " ", raw).strip()

        result = raw if len(raw) > 10 else None
        wiktionary_cache[key] = result
        _save_cache(wiktionary_cache, WIKTIONARY_CACHE)
        return result

    except Exception:
        wiktionary_cache[key] = None
        _save_cache(wiktionary_cache, WIKTIONARY_CACHE)
        return None
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════════════════════════
#  SOURCE 5 — WordsAPI  (last resort, paid tier, cached)
# ══════════════════════════════════════════════════════════════════════════════

def _parse_wordsapi_response(body: dict) -> dict | None:
    """Extract a clean entry dict from a raw WordsAPI response body."""
    results = body.get("results") or []
    chosen  = None
    for preferred in ("adjective", "verb", "noun", "adverb"):
        chosen = next((r for r in results if r.get("partOfSpeech") == preferred), None)
        if chosen:
            break
    if not chosen and results:
        chosen = results[0]
    if not chosen:
        return None

    definition = (chosen.get("definition") or "").strip()
    if not definition:
        return None

    pos      = chosen.get("partOfSpeech") or "unknown"
    examples: list[str] = []
    synonyms: list[str] = []
    seen_syn: set = set()

    for r in [chosen] + [x for x in results if x is not chosen]:
        for ex in (r.get("examples") or []):
            if ex.strip() and ex.strip() not in examples:
                examples.append(ex.strip())
            if len(examples) >= MAX_EXAMPLES:
                break
    for r in results:
        for s in (r.get("synonyms") or []):
            if s.strip() and s.lower() not in seen_syn:
                seen_syn.add(s.lower())
                synonyms.append(s.strip())

    freq  = body.get("frequency")
    zipf  = (freq.get("zipf") if isinstance(freq, dict)
             else float(freq) if isinstance(freq, (int, float)) else None)

    return {"definition": definition, "pos": pos,
            "examples": examples[:MAX_EXAMPLES],
            "synonyms": synonyms[:MAX_SYNONYMS], "zipf": zipf}

def fetch_wordsapi(word: str) -> dict | None:
    """
    Calls WordsAPI as a last resort — only when definition is still missing.
    Requires WORDSAPI_KEY environment variable.
    Results cached in scripts/cache/wordsapi_cache.json.
    """
    if not WORDSAPI_KEY:
        return None
    key = word.lower()
    if key in wordsapi_cache:
        raw = wordsapi_cache[key]
        return _parse_wordsapi_response(raw) if raw else None

    time.sleep(WORDSAPI_DELAY)
    conn = http.client.HTTPSConnection(WORDSAPI_HOST)
    try:
        conn.request("GET", f"/words/{urllib.parse.quote(key)}", headers={
            "X-RapidAPI-Key": WORDSAPI_KEY, "X-RapidAPI-Host": WORDSAPI_HOST,
        })
        res  = conn.getresponse()
        body = json.loads(res.read().decode("utf-8"))
        if res.status == 429:
            print("\n  ⚠️  WordsAPI rate limit hit — no further WordsAPI calls this session.")
            wordsapi_cache[key] = None
            _save_cache(wordsapi_cache, WORDSAPI_CACHE)
            return None
        if res.status != 200:
            wordsapi_cache[key] = None
            _save_cache(wordsapi_cache, WORDSAPI_CACHE)
            return None
        wordsapi_cache[key] = body
        _save_cache(wordsapi_cache, WORDSAPI_CACHE)
        return _parse_wordsapi_response(body)
    except Exception:
        wordsapi_cache[key] = None
        _save_cache(wordsapi_cache, WORDSAPI_CACHE)
        return None
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════════════════════════
#  ENRICHMENT CASCADE
# ══════════════════════════════════════════════════════════════════════════════

def enrich_word(word: str) -> tuple[dict | None, dict]:
    """
    Runs the full enrichment cascade for a single word.
    Returns (entry_dict | None, sources_dict).
      entry_dict : complete word entry ready for words.json, or None if no
                   definition was found anywhere.
      sources_dict: maps each field to the source that provided it, e.g.
                   {"definition": "wordnet", "origin": "wiktionary", ...}
    """
    sources: dict = {}
    definition = pos = ""
    examples:  list[str] = []
    synonyms:  list[str] = []
    origin:    str | None = None

    # ── 1. wordfreq — Zipf frequency ──────────────────────────────────────────
    frequency = get_zipf(word)
    if frequency > 0:
        sources["frequency"] = "wordfreq"

    # ── 2. WordNet — definition, POS, synonyms, examples ─────────────────────
    wn_entry = get_wordnet_entry(word)
    if wn_entry:
        definition = wn_entry["definition"]
        pos        = wn_entry["pos"]
        examples   = list(wn_entry["examples"])
        synonyms   = list(wn_entry["synonyms"])
        sources["definition"] = "wordnet"
        sources["pos"]        = "wordnet"
        if examples: sources["examples"] = "wordnet"
        if synonyms: sources["synonyms"] = "wordnet"

    # ── 3. Free Dictionary — fill any gaps + etymology ────────────────────────
    needs_fd = (not definition or not origin
                or len(examples) < MAX_EXAMPLES
                or len(synonyms) < TARGET_SYNONYMS)
    if needs_fd:
        fd = fetch_freedict(word)
        time.sleep(FREEDICT_DELAY)
        if fd:
            if not definition and fd.get("definition"):
                definition = fd["definition"]
                pos        = fd.get("pos") or pos
                sources["definition"] = "freedict"
                sources.setdefault("pos", "freedict")
            _merge_into(examples, fd.get("examples") or [], MAX_EXAMPLES)
            if fd.get("examples"): sources.setdefault("examples", "freedict")
            _merge_into(synonyms, fd.get("synonyms") or [], MAX_SYNONYMS)
            if fd.get("synonyms"): sources.setdefault("synonyms", "freedict")
            if fd.get("origin"):
                origin = fd["origin"]
                sources["origin"] = "freedict"

    # ── 4. Wiktionary — etymology (if still missing) ──────────────────────────
    if not origin:
        etym = fetch_wiktionary_etymology(word)
        time.sleep(WIKTIONARY_DELAY)
        if etym:
            origin = etym
            sources["origin"] = "wiktionary"

    # ── 5. WordsAPI — last resort, only if still no definition ────────────────
    if not definition:
        wa = fetch_wordsapi(word)
        if wa:
            if wa.get("definition"):
                definition = wa["definition"]
                sources["definition"] = "wordsapi"
            pos = pos or wa.get("pos") or ""
            sources.setdefault("pos", "wordsapi")
            _merge_into(examples, wa.get("examples") or [], MAX_EXAMPLES)
            _merge_into(synonyms, wa.get("synonyms") or [], MAX_SYNONYMS)
            if wa.get("zipf") and frequency == 0:
                frequency = wa["zipf"]
                sources["frequency"] = "wordsapi"

    # ── No definition found anywhere → skip ───────────────────────────────────
    if not definition:
        return None, sources

    final_freq = round(frequency if frequency > 0 else 1.0, 2)
    if "frequency" not in sources:
        sources["frequency"] = "default(1.0)"

    return {
        "word":         word.capitalize(),
        "partOfSpeech": pos or "unknown",
        "definition":   definition,
        "examples":     examples[:MAX_EXAMPLES],
        "synonyms":     synonyms[:MAX_SYNONYMS],
        "origin":       origin,
        "frequency":    final_freq,
        "isFeatured":   3.1 <= final_freq <= 4.2,
        "mastered":     False,
    }, sources


# ══════════════════════════════════════════════════════════════════════════════
#  PROCESSING LOOP
# ══════════════════════════════════════════════════════════════════════════════

cascade_label = (
    "wordfreq → WordNet → Free Dict → Wiktionary"
    + (" → WordsAPI" if WORDSAPI_KEY else "  [WordsAPI disabled]")
)
print(f"── Processing {len(new_words)} words ──────────────────────────────────────────")
print(f"   Cascade: {cascade_label}\n")

enriched:     list[dict] = []
skipped:      list[tuple[str, str]] = []   # (word, reason)
all_sources:  list[dict] = []

for i, word in enumerate(new_words, 1):
    print(f"  [{i:>4}/{len(new_words)}]  {word:<28}", end="", flush=True)

    z = get_zipf(word)
    if z > MAX_ZIPF:
        print(f"  skipped  (too common — Zipf {z:.2f} > {MAX_ZIPF})")
        skipped.append((word, f"too common (Zipf {z:.2f})"))
        continue

    entry, sources = enrich_word(word)

    if entry is None:
        print(f"  skipped  (no definition found in any source)")
        skipped.append((word, "no definition found"))
        continue

    src_tag = "+".join(sorted(set(sources.values())))
    print(f"  ✅  [{src_tag}]")
    enriched.append(entry)
    all_sources.append(sources)


# ══════════════════════════════════════════════════════════════════════════════
#  WRITE PREVIEW  &  SKIPPED
# ══════════════════════════════════════════════════════════════════════════════

PREVIEW_FILE.write_text(
    json.dumps(enriched, indent=2, ensure_ascii=False), encoding="utf-8"
)

if skipped:
    SKIPPED_FILE.write_text(
        "\n".join(f"{w:<30}  # {reason}" for w, reason in skipped),
        encoding="utf-8"
    )


# ══════════════════════════════════════════════════════════════════════════════
#  REPORT
# ══════════════════════════════════════════════════════════════════════════════

n = len(enriched)
print("\n" + "═" * 62)
print("  Enrichment Report")
print("═" * 62)
print(f"  Input words      : {len(new_words)}")
print(f"  Added to preview : {n}")
print(f"  Skipped          : {len(skipped)}")
if skipped:
    print(f"  Skipped list     : {SKIPPED_FILE.relative_to(PROJECT_ROOT)}")

if n > 0:
    def _pct(count: int) -> str:
        return f"{count:>4} / {n}  ({count / n * 100:.0f}%)"

    has_def   = sum(1 for e in enriched if e.get("definition"))
    has_pos   = sum(1 for e in enriched if e.get("partOfSpeech") not in ("", "unknown", None))
    has_freq  = sum(1 for e in enriched if e.get("frequency", 1.0) > 1.0)
    has_ex    = sum(1 for e in enriched if e.get("examples"))
    has_2ex   = sum(1 for e in enriched if len(e.get("examples") or []) >= 2)
    has_syn   = sum(1 for e in enriched if e.get("synonyms"))
    has_5syn  = sum(1 for e in enriched if len(e.get("synonyms") or []) >= TARGET_SYNONYMS)
    has_ori   = sum(1 for e in enriched if e.get("origin"))

    print(f"\n  Field coverage:")
    print(f"    definition        : {_pct(has_def)}")
    print(f"    part of speech    : {_pct(has_pos)}")
    print(f"    frequency (Zipf)  : {_pct(has_freq)}")
    print(f"    any example       : {_pct(has_ex)}")
    print(f"    2 examples        : {_pct(has_2ex)}")
    print(f"    any synonyms      : {_pct(has_syn)}")
    print(f"    5+ synonyms       : {_pct(has_5syn)}")
    print(f"    etymology/origin  : {_pct(has_ori)}")

    def_sources  = Counter(s.get("definition", "—") for s in all_sources)
    etym_sources = Counter(s.get("origin", "none") for s in all_sources)

    print(f"\n  Definition came from:")
    for src, count in def_sources.most_common():
        print(f"    {src:<18} {count:>4} words")

    print(f"\n  Etymology came from:")
    for src, count in etym_sources.most_common():
        print(f"    {src:<18} {count:>4} words")

    freq_vals = [e["frequency"] for e in enriched]
    print(f"\n  Frequency (Zipf) range : {min(freq_vals):.2f} – {max(freq_vals):.2f}")
    print(f"  isFeatured (3.1–4.2)   : {sum(1 for e in enriched if e['isFeatured'])} words")


# ══════════════════════════════════════════════════════════════════════════════
#  CONFIRM  &  MERGE
# ══════════════════════════════════════════════════════════════════════════════

if not enriched:
    print("\n  Nothing to merge.")
    sys.exit(0)

print(f"\n{'─' * 62}")
print(f"  Review the preview file before merging:")
print(f"  → {PREVIEW_FILE}")
print()
print(f"  When ready, press Enter to merge {n} word(s) into:")
print(f"  → {MASTER_FILE}")
print(f"  (Ctrl+C to abort without making any changes)")
print(f"{'─' * 62}")

try:
    input("\n  Press Enter to merge → ")
except KeyboardInterrupt:
    print("\n\n  Aborted. No changes made to words.json.")
    sys.exit(0)

print()
backup_master()

# Assign IDs starting after the current maximum
next_id = max((w.get("id", -1) for w in master_words), default=-1) + 1
for entry in enriched:
    entry["id"] = next_id
    next_id += 1

merged = master_words + enriched
MASTER_FILE.write_text(
    json.dumps(merged, indent=2, ensure_ascii=False), encoding="utf-8"
)

print(f"\n✅  Merged {n} new word(s) into {MASTER_FILE.relative_to(PROJECT_ROOT)}")
print(f"   Master list now contains {len(merged)} words.")
print(f"\n   Rebuild the app in Xcode to pick up the updated words.json.")
print()
