# VocabWidget — Word List Generation

One script builds the entire master word list from scratch.
Run it whenever you want a fresh set of 1 500 words.

---

## What it produces

`words_generated.json` — 1 500 words (500 beginner, 500 intermediate,
500 advanced), each with:

```json
{
  "id": 0,
  "word": "Candid",
  "partOfSpeech": "adjective",
  "definition": "Truthful and straightforward; frank.",
  "examples": ["She gave a candid account of what happened.", "His candid manner won people's trust."],
  "synonyms": ["frank", "open", "honest", "direct", "forthright"],
  "origin": "Mid 17th century: from Latin candidus 'white'.",
  "level": "intermediate",
  "isFeatured": false,
  "mastered": false
}
```

---

## Prerequisites

**1. Python 3.10+** (no third-party packages needed — stdlib only)

**2. A free WordsAPI key**
   - Sign up at https://rapidapi.com/dpventures/api/wordsapiv1
   - Free tier: 2 500 requests / day
   - Used only for frequency scoring — the enrichment (definitions, examples,
     synonyms, etymology) comes from the Free Dictionary API which is free
     and requires no key.

---

## Setup

```bash
export WORDSAPI_KEY=your_key_here
```

Add that line to your `~/.zshrc` (or `~/.bashrc`) so you don't have to
re-enter it each time:

```bash
echo 'export WORDSAPI_KEY=your_key_here' >> ~/.zshrc
source ~/.zshrc
```

---

## Running the script

Run from the **project root** (`VocabWidget/VocabWidget/`):

```bash
python3 scripts/build_master_list.py
```

The script runs in three phases and prints progress as it goes:

| Phase | API used | Rate limit |
|-------|----------|------------|
| 1 — Score candidates | WordsAPI | 2 500 / day (free tier) |
| 2 — Enrich confirmed words | Free Dictionary | Unlimited |
| 3 — Assemble output | — | — |

**Phase 1 alone may take more than one day** if your free quota runs out
before all candidates are scored. The script stops cleanly when it hits
the rate limit and prints a message. Just re-run it the next day —
already-scored words are never re-fetched.

---

## Safe to interrupt

Results are cached after every single API call:

```
scripts/cache/scores.json       ← WordsAPI Zipf scores
scripts/cache/enrichment.json   ← Free Dictionary data
```

You can stop the script at any time (Ctrl-C) and re-run it — it picks
up exactly where it left off. Delete the `scripts/cache/` folder only
if you want to start completely from scratch.

---

## After the script finishes

**1. Review the output**

```bash
# Count words per level
python3 -c "
import json
words = json.load(open('words_generated.json'))
from collections import Counter
print(Counter(w['level'] for w in words))
"
```

Spot-check a few words you know to make sure the levels feel right.

**2. Copy into the app**

```bash
cp words_generated.json VocabWidget/words.json
```

**3. Clean up**

```bash
rm words_generated.json
```

---

## Customising the word pool

Edit `scripts/word_candidates.txt` to add or remove candidates.
One word per line. Lines starting with `#` are comments and are ignored.

The script targets **500 words per level**. If a level comes up short,
add more candidate words in the right frequency range and re-run.

**Zipf frequency guide:**
- `≥ 5.5` — too common (everyone already knows these)
- `4.5 – 5.5` → **beginner** (heard it, don't use it confidently)
- `3.1 – 4.5` → **intermediate** (marks an educated vocabulary)
- `1.9 – 3.1` → **advanced** (literary / formal register)
- `< 1.9` — too rare (obscure, not useful for learning)

---

## Generating a second batch (avoiding duplicates)

The script automatically skips words already in `VocabWidget/words.json`.
To generate a completely different 1 500 words:

1. Add new candidates to `word_candidates.txt`
2. Delete `scripts/cache/` (forces re-scoring)
3. Run the script

---

## Files committed to git

```
scripts/
  build_master_list.py   ← the script (no secrets)
  word_candidates.txt    ← ~2 500 candidate words
  README.md              ← this file
  .gitignore             ← ignores cache/ and output files
```

The `scripts/cache/` folder and `words_generated.json` are gitignored —
they are intermediate build artefacts, not source files.
