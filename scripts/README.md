# VocabWidget — Word List Generation

One script builds the entire 1 500-word master list from scratch.
No candidate word list required — words are requested directly from
WordsAPI already filtered to the right difficulty range.

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

The script runs in three phases:

| Phase | What happens | API used | Key |
|-------|-------------|----------|-----|
| 1 — Collect | Requests random words filtered to each Zipf range | WordsAPI | Required |
| 2 — Enrich | Fetches etymology for each word | Free Dictionary | None |
| 3 — Assemble | Merges data, writes `words_generated.json` | — | — |

**Zipf frequency levels used:**

| Level | Zipf range | Description |
|-------|-----------|-------------|
| beginner | 4.5 – 5.5 | Heard it, don't use it confidently |
| intermediate | 3.1 – 4.5 | Marks an educated vocabulary |
| advanced | 1.9 – 3.1 | Literary / formal register |

---

## API usage (free tier = 2 500 requests / day)

| Calls | Purpose |
|-------|---------|
| ~1 650 | WordsAPI random words (~550 per level, allows for ~10% skipped) |
| ~1 500 | Free Dictionary etymology (unlimited — no quota) |

→ Completes in **one day** well within the free quota.

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

Progress is printed in real time. The script takes roughly 20–30 minutes
to complete all three phases.

---

## Safe to interrupt

Everything is cached after every single API call:

```
scripts/cache/collected.json      ← words gathered per level
scripts/cache/enrichment.json     ← etymology data
```

Stop the script any time (Ctrl-C) and re-run — it resumes exactly where
it left off. Delete `scripts/cache/` only if you want to start from
scratch.

If WordsAPI's daily quota runs out mid-run, the script stops cleanly
and prints how many words it saved. Re-run the next day.

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
2. Run the script again:
   ```bash
   python3 scripts/build_master_list.py
   ```

Because WordsAPI returns *random* words each time, you'll get a
completely different 1 500-word set.

---

## Files committed to git

```
scripts/
  build_master_list.py   ← the script (no secrets)
  README.md              ← this file
  .gitignore             ← ignores scripts/cache/
```

`scripts/cache/` and `words_generated.json` are gitignored.
