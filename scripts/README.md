# VocabWidget — Word List Generation

One script builds the entire 1 500-word master list.  It scores a
curated candidate list of ~5 000 high-quality words (GRE, SAT, AWL,
literary) using WordsAPI Zipf frequency, selects the best 500 per
level, then enriches every word with the Free Dictionary API.

---

## What it produces

`words_generated.json` — 1 500 words (500 beginner · 500 intermediate ·
500 advanced), each fully populated:

```json
{
  "id": 0,
  "word": "Candid",
  "partOfSpeech": "adjective",
  "definition": "Truthful and straightforward; frank.",
  "examples": ["She gave a candid account of what happened."],
  "synonyms": ["frank", "open", "honest", "direct"],
  "origin": "Mid 17th century: from Latin candidus 'white'.",
  "level": "intermediate",
  "isFeatured": false,
  "mastered": false
}
```

---

## How it works

The script runs in four phases:

| Phase | What happens | API used | Key |
|-------|-------------|----------|-----|
| 1 — Score | Calls `GET /words/{word}` for each candidate; gets Zipf score + definitions | WordsAPI | Required |
| 2 — Select | Buckets words by Zipf range; picks top 500 per level | — | — |
| 3 — Enrich | Calls Free Dictionary for each selected word to fill examples, synonyms, etymology | Free Dictionary | None |
| 4 — Assemble | Merges both sources, writes `words_generated.json` | — | — |

**Why candidate-list instead of random words?**  
The curated candidate list (`scripts/word_candidates.txt`) contains
GRE/SAT/literary vocabulary — words people actually want to learn.
Random WordsAPI words include obscure technical terms, archaic forms,
and brand names that aren't useful for vocabulary building.

**Zipf frequency levels:**

| Level | Zipf range | Description |
|-------|-----------|-------------|
| beginner | 4.5 – 5.5 | Common, high-value everyday words |
| intermediate | 3.1 – 4.5 | SAT-level, marks an educated vocabulary |
| advanced | 1.9 – 3.1 | GRE / literary / formal register |

Within each band, the script picks words with the **highest Zipf score**
(most recognisable, highest-quality words at that difficulty).

---

## API usage (free tier = 2 500 WordsAPI requests / day)

| Calls | Purpose |
|-------|---------|
| ~5 000 total | Score all candidates — takes **2–3 days** at 2 500/day |
| Unlimited | Free Dictionary enrichment (no quota) |

Because scoring 5 000 candidates takes more than one day, the script
caches every result and resumes automatically. After the first two
days of scoring, Phases 2–4 run instantly on each subsequent invocation.

---

## Prerequisites

**Python 3.10+** — no third-party packages, stdlib only.

**A free WordsAPI key:**
1. Sign up at https://rapidapi.com/dpventures/api/wordsapiv1
2. Subscribe to the free tier (2 500 requests / day)
3. Copy your key from the API console

---

## Setup

Set your API key as an environment variable:

```bash
export WORDSAPI_KEY=your_key_here
```

To make this permanent, add it to your shell profile:

```bash
echo 'export WORDSAPI_KEY=your_key_here' >> ~/.zshrc
source ~/.zshrc
```

---

## Running the script

From the **project root** (`VocabWidget/VocabWidget/`):

```bash
python3 scripts/build_master_list.py
```

Progress is printed in real time. Run once per day until all candidates
are scored (shown in the Phase 1 summary). After that the script
completes fully in a few minutes.

---

## Safe to interrupt

Everything is cached after every single API call:

```
scripts/cache/candidate_scores.json   ← Zipf scores + word data per candidate
scripts/cache/enrichment.json         ← Free Dictionary data per selected word
```

Stop the script any time (Ctrl-C) and re-run — it resumes exactly
where it left off. Delete `scripts/cache/` only if you want to start
from scratch.

If WordsAPI's daily quota runs out mid-run, the script stops cleanly,
prints per-level progress, and tells you how many words are still
outstanding. Re-run the next day.

---

## After the script finishes

**1. Verify counts**

```bash
python3 -c "
import json
from collections import Counter
words = json.load(open('words_generated.json'))
print(Counter(w['level'] for w in words))
"
```

**2. Spot-check a few words** in `words_generated.json` to confirm the
levels feel right.

**3. Copy into the app**

```bash
cp words_generated.json VocabWidget/words.json
rm words_generated.json
```

**4. Commit**

```bash
git add VocabWidget/words.json
git commit -m "Regenerate master word list"
```

---

## Generating a fresh batch (completely different words)

1. Delete the cache so the script starts from scratch:
   ```bash
   rm -rf scripts/cache/
   ```
2. Optionally add new words to `scripts/word_candidates.txt`.
3. Run the script again:
   ```bash
   python3 scripts/build_master_list.py
   ```

---

## Files committed to git

```
scripts/
  build_master_list.py     ← the script (no secrets)
  word_candidates.txt      ← ~5 000 curated GRE/SAT/literary candidates
  README.md                ← this file
  .gitignore               ← ignores scripts/cache/
```

`scripts/cache/` and `words_generated.json` are gitignored.
