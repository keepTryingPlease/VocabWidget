# VocabWidget — Lock Screen Word of the Day

A minimal iOS app + lock screen widget that shows a new vocabulary word every day.
Built with SwiftUI + WidgetKit. No API calls. Local word list only.

---

## File Map

```
Shared/
  VocabularyWord.swift      ← data model (add to BOTH targets)
  VocabularyStore.swift     ← word list + word-of-day logic (add to BOTH targets)

MainApp/
  VocabApp.swift            ← app entry point (main app target only)
  ContentView.swift         ← main screen UI (main app target only)

WidgetExtension/
  VocabLockScreenWidget.swift  ← full widget (widget extension target only)
```

---

## Xcode Setup (Step by Step)

### 1. Create the main app project

1. Open Xcode → **Create New Project**
2. Choose **iOS → App**
3. Name it `VocabWidget`, set interface to **SwiftUI**, language to **Swift**
4. Save it somewhere on your Mac

### 2. Delete the generated boilerplate

Xcode creates `ContentView.swift` and `VocabWidgetApp.swift` for you.
Delete them (Move to Trash) — you'll replace them with the files from this folder.

### 3. Add your source files to the main app target

Drag these files into your project navigator in Xcode:
- `Shared/VocabularyWord.swift`
- `Shared/VocabularyStore.swift`
- `MainApp/VocabApp.swift`
- `MainApp/ContentView.swift`

When the dialog asks **"Add to targets"**, make sure **only your main app** is checked.

### 4. Add the Widget Extension target

1. In Xcode menu: **File → New → Target**
2. Search for **Widget Extension** → select it → Next
3. Name it something like `VocabWidgetExtension`
4. **Uncheck** "Include Configuration App Intent" (keep it simple)
5. Click **Finish** → when asked to activate the scheme, click **Activate**

Xcode will create a new group in the navigator with some generated files.
You can delete the generated `.swift` file inside it — you'll replace it.

### 5. Add the widget source file

Drag `WidgetExtension/VocabLockScreenWidget.swift` into the widget extension group.
When the dialog asks **"Add to targets"**, check **only the widget extension**.

### 6. Add the shared files to the widget extension target too

The widget needs `VocabularyWord.swift` and `VocabularyStore.swift`.
For each of those files:
1. Click the file in the navigator
2. Open the **File Inspector** panel (right sidebar, first tab — looks like a document icon)
3. Under **Target Membership**, check the box next to your **widget extension** as well

Both shared files should now have checkmarks for BOTH targets.

### 7. Build and run

- Select your **main app** scheme in the toolbar → run on Simulator or device
- You should see the main app with today's word and a scrollable word bank

### 8. Test the widget

- In Xcode, change the active scheme to your **widget extension** scheme
- Run it — Xcode will install it and show the widget in the lock screen simulator
- Or on a real device: long-press the lock screen → tap **Customize** → **Add Widget** → find "Word of the Day"

> **Note:** Lock screen widgets require iOS 16 or later.

---

## How the Word-of-Day Logic Works

```swift
let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
let index = (dayOfYear - 1) % words.count
return words[index]
```

Both the app and the widget run this same code independently — they always agree on
the current word without needing to communicate. No App Groups, no UserDefaults
sharing, no network calls required.

---

## Adding More Words

Open `VocabularyStore.swift` and add entries to the `words` array following the same
pattern. Keep `id` values unique and incrementing. The widget will automatically cycle
through them day by day.

---

## What to Explore Next (Beyond the MVP)

| Feature | What you'd learn |
|---|---|
| Tap widget → opens app to that word | URL schemes / widgetURL |
| Swipe through past words in the app | @State, gesture recognizers |
| Mark words as "mastered" | UserDefaults / @AppStorage |
| Share word of the day | ShareLink (iOS 16+) |
| Load words from a JSON file in the bundle | Bundle.main.url, JSONDecoder |
| Fetch new word packs from an API | async/await, URLSession |
| App Group to pass "bookmarked" words to widget | App Groups, shared UserDefaults |
