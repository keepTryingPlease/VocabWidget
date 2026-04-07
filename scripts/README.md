# VocabWidget — Word Enrichment Scripts

## `enrich_words.py`

Adds new words to `VocabWidget/words.json` via a free-first enrichment cascade.

### Usage

Run from the **project root**:

```bash
python3 scripts/enrich_words.py
python3 scripts/enrich_words.py --no-wordsapi   # skip paid API
```

### Workflow

1. Add words (one per line) to `scripts/input/words_to_add.txt`
2. Run the script — it skips anything already in `words.json`
3. Review the preview at `words_generated.json`
4. Press Enter to merge, or Ctrl+C to abort

### Enrichment cascade

| Priority | Source | What it provides | Cost |
|----------|--------|-----------------|------|
| 1 | wordfreq | Zipf frequency score | Free, offline |
| 2 | WordNet (NLTK) | Definition, POS, synonyms, examples | Free, offline |
| 3 | Free Dictionary API | Gaps + etymology | Free, no key |
| 4 | Wiktionary | Etymology fallback | Free, no key |
| 5 | WordsAPI | Last-resort definition | Free tier (2,500/day); set `WORDSAPI_KEY` env var |

Words with Zipf > 4.2 are automatically skipped — too common to be vocabulary targets.

### Folder layout

```
scripts/
├── enrich_words.py          # main script
├── input/
│   └── words_to_add.txt     # add new words here
├── cache/
│   ├── freedict_cache.json  # Free Dictionary API cache
│   ├── wiktionary_cache.json
│   └── wordsapi_cache.json
├── output/
│   └── skipped_words.txt    # words that couldn't be enriched
├── backup/                  # timestamped backups of words.json (last 5 kept)
└── archive/                 # old scripts, kept for reference
```

### Requirements

```bash
pip install wordfreq nltk
python3 -c "import nltk; nltk.download('wordnet')"
```
