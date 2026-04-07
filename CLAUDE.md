# VocabWidget — Project Context for Claude Code

## What this app is
An iOS vocabulary-learning app. A single adaptive card deck of GRE/academic words. The user swipes vertically through words; mastering a word removes it from the deck. A lock screen widget shows the daily word.

## Architecture

### Core data flow
- `VocabularyStore` — static list of `VocabularyWord` objects loaded from `words.json`
- `UserLibrary` — persists user state: `masteredIDs`, `likedIDs`, collections, `userSkill`
- `DeckScheduler` — builds and manages the in-memory deck of `DeckCard`s
- `ContentView` — drives the scroll UI; consumes `filteredDeck` (deck minus mastered words)

### `userSkill`
Mean Zipf frequency of all mastered words. Starts at a default (around 4.5). Used to zone-sort each deck pass.

### `DeckCard`
Wraps a `wordID: Int` with a stable `UUID`. The UUID gives SwiftUI's `ForEach` a unique identity even when the same word appears in multiple passes (how looping works).

### Deck zones (relative to `userSkill`)
| Zone    | Zipf range              | Share | Purpose              |
|---------|-------------------------|-------|----------------------|
| easy    | > skill + 0.3           | ~15%  | confidence / quick wins |
| target  | skill−1.0 … skill+0.3  | ~65%  | active learning edge |
| stretch | < skill − 1.0           | ~20%  | challenging exposure |

Zones are interleaved in 3:13:4 blocks by `DeckScheduler.interleave()`.

### Infinite looping
`appendPassIfNeeded()` triggers when the user is within 8 cards of the end. It silently appends a full fresh zone-sorted pass. The user can scroll indefinitely — every unmastered word cycles back.

### Real-time difficulty adaptation
After each mastery, `masteredAction()` calls `rebuildAhead(after:)` which replaces all cards ahead of the current position with a freshly calibrated zone-sorted pass at the updated `userSkill`. The card immediately after a mastery is already at the right difficulty.

### Scroll tracking
`currentCardID: UUID?` (not a word Int ID) is the scroll anchor. This means deck rebuilds never break the scroll position.

## Key files
| File | Role |
|------|------|
| `VocabWidget/ContentView.swift` | Main UI, scroll logic, mastery animation |
| `VocabWidget/DeckScheduler.swift` | Deck building, looping, zone sorting |
| `VocabWidget/UserLibrary.swift` | Persistence: mastered, liked, collections, userSkill |
| `VocabWidget/VocabularyStore.swift` | Loads `words.json` |
| `VocabWidget/VocabularyWord.swift` | Word model |
| `VocabWidget/MilestoneManager.swift` | Achievement milestones |
| `VocabWidget/MilestoneViews.swift` | Fireworks celebration UI |
| `VocabWidget/PronunciationService.swift` | TTS audio via AVSpeechSynthesizer |
| `VocabWidget/LibraryView.swift` | Mastered/Liked/Collections browser |
| `VocabWidget/WordInfoView.swift` | Info sheet (etymology, synonyms, etc.) |
| `VocabWidgetExtension/VocabLockScreenWidget.swift` | Lock screen widget |
| `scripts/` | Python word-mining scripts |

## Design decisions & rejected approaches

### Why UUID-per-slot (not word ID) for ForEach identity
Using word ID as identity caused SwiftUI to confuse cards when the same word appeared in multiple passes of the deck. UUIDs are created fresh per slot, so looping works correctly.

### Why ScrollView + `.scrollTargetBehavior(.paging)` (not DragGesture)
The previous hand-rolled DragGesture approach forced a full SwiftUI layout pass on every finger-movement event, causing frame drops. Native ScrollView uses UIKit's hardware-accelerated scroll layer — full 120Hz throughput.

### Why `filteredDeck` filters mastered words on the fly
Rather than mutating the deck on mastery, `filteredDeck` is a computed property that filters out mastered words reactively. This keeps the deck scheduler simple and avoids index-shifting bugs.

### Single deck (no levels)
Previous versions had level-based decks. Removed in favour of a single adaptive deck sorted by frequency zones relative to `userSkill`. Simpler UX, better adaptability.

## Current branch
`swipe-curation` — branched from `single-deck`.

## In-progress / open questions
<!-- Update this section at the end of each session -->
_Last updated: 2026-04-06_

### Ratchet difficulty system — SHIPPED

Ratchet model is fully coded and working:
- `userSkill` starts at **2.0** (current tuning — was 3.5, then 2.9, still feeling out the right value)
- Only decreases (by 0.05) when a target- or stretch-zone word is mastered
- Easy masteries (Zipf > skill + 0.3) have no effect
- Green skill pill appears in top-right for 2 seconds after each qualifying mastery
- `#if DEBUG` block in `UserLibrary.init()` wipes all state on every launch (testing convenience — remove before shipping)

**Still to tune:** Starting skill value. 2.0 is the current test point. May need to go back up slightly depending on word coverage at that Zipf range.

**Future feature (not now):** Onboarding placement test to set starting skill precisely. Flagged for later.

### Word enrichment pipeline — SHIPPED

New `scripts/enrich_words.py` is the single script going forward:
- Reads from `scripts/input/words_to_add.txt`
- Free-first cascade: wordfreq → WordNet → Free Dict API → Wiktionary → WordsAPI
- Max Zipf cap: 4.2 (script) and 4.0 (DeckScheduler — belt-and-suspenders)
- Auto-backup of `words.json` before each merge (last 5 kept in `scripts/backup/`)
- Pauses for review before merging
- `scripts/README.md` documents the workflow

Master list is at **2,731 words** (after last merge session). 17 more words are ready to merge
(preview is in `words_generated.json`) — just needs an interactive terminal run to confirm.

### SourceKit diagnostics
Persistent "Cannot find X in scope" errors in SourceKit are **stale index warnings**, not real
build errors. They clear on a clean build in Xcode.
