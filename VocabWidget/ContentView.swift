// ContentView.swift
//
// Card deck built as a ZStack — current card on top, next card behind.
// A single DragGesture on the top card drives all interactions:
//
//   Swipe RIGHT  (≥ 110 pt)  → Save to "Saved" list
//   Swipe LEFT   (≥ 110 pt)  → Disregard word (hidden forever)
//   Swipe UP     (≥ 110 pt)  → Skip to next card (no action)
//   Tap Mastered             → Inhale animation, mark as mastered
//   Tap Like                 → Open Liked / Collections picker
//
// No ScrollView means no gesture conflict, no jitter.
// As the top card moves, the card beneath scales up into view — Tinder style.

import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// ── Rarity level ──────────────────────────────────────────────────────────────

private enum RarityLevel {
    case obscure, uncommon, common

    /// Returns nil for advanced words (Zipf ≥ 4.0) — badge not shown.
    init?(zipf: Double) {
        switch zipf {
        case ..<1.8:     self = .obscure
        case 1.8..<3.0:  self = .uncommon
        case 3.0..<4.0:  self = .common
        default:         return nil   // advanced — no badge
        }
    }

    var label: String {
        switch self {
        case .obscure:  return "Obscure"
        case .uncommon: return "Uncommon"
        case .common:   return "Common"
        }
    }

    var color: Color {
        switch self {
        case .obscure:  return Color(red: 0.65, green: 0.45, blue: 0.90)
        case .uncommon: return Color(red: 0.40, green: 0.65, blue: 0.95)
        case .common:   return Color(red: 0.35, green: 0.80, blue: 0.75)
        }
    }
}

// ── ContentView ───────────────────────────────────────────────────────────────

struct ContentView: View {

    let allWords = VocabularyStore.words
    @StateObject private var library          = UserLibrary()
    @StateObject private var scheduler        = DeckScheduler()
    @StateObject private var milestoneManager = MilestoneManager()

    @State private var celebrationMilestone: Milestone?     = nil
    @State private var showingMilestones    = false
    @State private var infoWord:            VocabularyWord? = nil
    @State private var collectionsWord:     VocabularyWord? = nil
    @State private var selectedWord:        VocabularyWord? = nil   // widget deep-link
    @State private var showingLibrary       = false
    @State private var currentCardID:       UUID?           = nil
    @State private var fetchingAudioForID:  Int?            = nil
    @State private var masteringWordID:     Int?            = nil
    /// Live drag translation — drives offset, rotation, and background scale.
    @State private var dragOffset:          CGSize          = .zero
    /// Locked true while a fly-off animation is running so the gesture is ignored.
    @State private var isDismissing:        Bool            = false

    private let idToWord: [Int: VocabularyWord] =
        Dictionary(uniqueKeysWithValues: VocabularyStore.words.map { ($0.id, $0) })

    // ── Derived deck ──────────────────────────────────────────────────────────

    private var filteredDeck: [DeckCard] {
        let excluded = library.masteredIDs.union(library.disregardedIDs)
        return scheduler.deck.filter { !excluded.contains($0.wordID) }
    }

    private var currentEntry: (card: DeckCard, word: VocabularyWord)? {
        guard let id = currentCardID,
              let card = filteredDeck.first(where: { $0.id == id }),
              let word = idToWord[card.wordID] else { return nil }
        return (card, word)
    }

    private var nextEntry: (card: DeckCard, word: VocabularyWord)? {
        guard let id = currentCardID,
              let idx = filteredDeck.firstIndex(where: { $0.id == id }),
              filteredDeck.indices.contains(idx + 1),
              let word = idToWord[filteredDeck[idx + 1].wordID]
        else { return nil }
        return (filteredDeck[idx + 1], word)
    }

    /// 0 → 1 as horizontal drag crosses the dismiss threshold.
    private var dragProgress: Double {
        min(abs(dragOffset.width) / 110.0, 1.0)
    }

    private var cardRotation: Double {
        Double(dragOffset.width / 22.0).clamped(to: -13...13)
    }

    // ── Body ──────────────────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if filteredDeck.isEmpty {
                    emptyStateView()
                } else {
                    cardStack()
                }
            }
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .onAppear {
                if scheduler.deck.isEmpty {
                    scheduler.buildInitialDeck(
                        masteredIDs:    library.masteredIDs,
                        disregardedIDs: library.disregardedIDs
                    )
                }
                if currentCardID == nil { currentCardID = filteredDeck.first?.id }
            }
            // Append a new pass when the deck is running low.
            .onChange(of: currentCardID) { _, id in
                fetchingAudioForID = nil
                guard let id,
                      let deckIdx = scheduler.deck.firstIndex(where: { $0.id == id })
                else { return }
                scheduler.appendPassIfNeeded(
                    currentIndex:   deckIdx,
                    masteredIDs:    library.masteredIDs,
                    disregardedIDs: library.disregardedIDs
                )
            }
            .sheet(item: $infoWord)          { WordInfoView(word: $0) }
            .sheet(item: $collectionsWord)   { LibraryView(library: library, initialTab: .collections, targetWord: $0) }
            .sheet(item: $selectedWord)      { WordDetailView(word: $0) }
            .sheet(isPresented: $showingLibrary)    { LibraryView(library: library) }
            .sheet(item: $celebrationMilestone)     { MilestoneCelebrationView(milestone: $0) }
            .sheet(isPresented: $showingMilestones) { MilestoneProgressView(milestoneManager: milestoneManager, library: library) }
            .overlay(alignment: .topLeading) { milestonesButton() }
            .onOpenURL { url in
                guard url.scheme == "vocabwidget", url.host == "word",
                      let id = Int(url.lastPathComponent),
                      let match = allWords.first(where: { $0.id == id }) else { return }
                selectedWord = match
            }
        }
    }

    // ── Card stack ────────────────────────────────────────────────────────────

    @ViewBuilder
    private func cardStack() -> some View {
        GeometryReader { geo in
            ZStack {
                // ── Card behind (next in deck) ────────────────────────────
                // Scales up from 92 % → 100 % as the top card is dragged away.
                if let (nextCard, nextWord) = nextEntry {
                    let behindScale = 0.92 + 0.08 * dragProgress
                    let behindY     = 14.0 * (1.0 - dragProgress)

                    cardFace(for: nextWord, cardID: nextCard.id, size: geo.size)
                        .scaleEffect(behindScale)
                        .offset(y: behindY)
                        .allowsHitTesting(false)   // only the top card is interactive
                }

                // ── Top card (current) ────────────────────────────────────
                if let (card, word) = currentEntry {
                    cardFace(for: word, cardID: card.id, size: geo.size)
                        .offset(x: dragOffset.width, y: dragOffset.height * 0.25)
                        .rotationEffect(.degrees(cardRotation),
                                        anchor: UnitPoint(x: 0.5, y: 0.85))
                        .overlay { swipeOverlay() }
                        .gesture(deckGesture(word: word, cardID: card.id))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // ── Card face (content + action bar) ──────────────────────────────────────

    @ViewBuilder
    private func cardFace(for word: VocabularyWord, cardID: UUID, size: CGSize) -> some View {
        let isMastering = masteringWordID == word.id
        let mastered    = library.isMastered(word)
        let rarity      = RarityLevel(zipf: word.frequency)   // nil = advanced, badge hidden

        ZStack(alignment: .bottom) {

            // ── Card content ──────────────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text(word.word)
                            .font(.custom("PlayfairDisplay-Bold", size: 36))
                            .foregroundStyle(Color.appPrimary)
                            .multilineTextAlignment(.center)

                        if let rarity { rarityBadge(rarity) }
                    }

                    Divider()
                        .overlay(Color.appSecondary.opacity(0.4))
                        .padding(.horizontal, 40)

                    Text(word.definition)
                        .font(.custom("Inter_18pt-Regular", size: 17))
                        .foregroundStyle(Color.appPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let example = word.examples.first {
                        Text("\u{201C}\(example)\u{201D}")
                            .font(.custom("Inter_18pt-Regular", size: 15))
                            .italic()
                            .foregroundStyle(Color.appSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                Button {
                    Task {
                        fetchingAudioForID = word.id
                        await PronunciationService.shared.speak(word.word)
                        fetchingAudioForID = nil
                    }
                } label: {
                    if fetchingAudioForID == word.id {
                        ProgressView().tint(Color.appSecondary).frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "speaker.wave.2")
                            .font(.title2)
                            .foregroundStyle(Color.appSecondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.top, 16)

                Spacer()
                Color.clear.frame(height: 88)
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(isMastering ? 0.05 : 1.0,
                         anchor: UnitPoint(x: 0.5, y: 0.92))
            .opacity(isMastering ? 0.0 : 1.0)
            .animation(.easeIn(duration: 0.30), value: isMastering)

            // ── Action bar ────────────────────────────────────────────────
            HStack(spacing: 0) {
                actionButton(icon: "info.circle", label: "Info") { infoWord = word }

                actionButton(icon: "square.stack", label: "Collections") { collectionsWord = word }

                Button { masteredAction(for: word, cardID: cardID) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mastered ? "checkmark.seal.fill" : "checkmark.seal")
                            .font(.system(size: 19))
                            .foregroundStyle(isMastering || mastered
                                ? Color(red: 0.35, green: 0.85, blue: 0.55) : Color.appSecondary)
                            .scaleEffect(isMastering ? 1.45 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.4).delay(0.06),
                                       value: isMastering)
                        Text("Mastered")
                            .font(.custom("Inter_18pt-Regular", size: 9))
                            .foregroundStyle(isMastering || mastered
                                ? Color(red: 0.35, green: 0.85, blue: 0.55) : Color.appSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .disabled(isMastering || isDismissing)

                actionButton(icon: "list.bullet", label: "Library") { showingLibrary = true }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 40)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    // ── Rarity badge ──────────────────────────────────────────────────────────

    @ViewBuilder
    private func rarityBadge(_ rarity: RarityLevel) -> some View {
        Text(rarity.label.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(rarity.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(rarity.color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(rarity.color.opacity(0.30), lineWidth: 0.5))
    }

    // ── Swipe overlay ─────────────────────────────────────────────────────────

    @ViewBuilder
    private func swipeOverlay() -> some View {
        let progress = min(abs(dragOffset.width) / 110.0, 1.0)

        ZStack(alignment: .topLeading) {
            if dragOffset.width > 5 {
                // LIKE — right
                VStack {
                    HStack {
                        Spacer()
                        swipeLabel("LIKE", color: Color(red: 0.95, green: 0.35, blue: 0.35),
                                   rotation: -14)
                            .padding(.top, 100).padding(.trailing, 36)
                    }
                    Spacer()
                }
                .opacity(progress)

            } else if dragOffset.width < -5 {
                // NOPE — left
                VStack {
                    HStack {
                        swipeLabel("NOPE", color: Color(red: 0.95, green: 0.38, blue: 0.38),
                                   rotation: 14)
                            .padding(.top, 100).padding(.leading, 36)
                        Spacer()
                    }
                    Spacer()
                }
                .opacity(progress)
            }
        }
    }

    @ViewBuilder
    private func swipeLabel(_ text: String, color: Color, rotation: Double) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(rotation))
    }

    // ── Deck gesture ──────────────────────────────────────────────────────────

    private func deckGesture(word: VocabularyWord, cardID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isDismissing, masteringWordID == nil else { return }
                // Only track horizontal movement; ignore vertical drag.
                dragOffset = CGSize(width: value.translation.width, height: 0)
            }
            .onEnded { value in
                guard !isDismissing, masteringWordID == nil else { return }
                let dx = value.translation.width
                if dx > 110 {
                    flyOff(to: .right, word: word, cardID: cardID)
                } else if dx < -110 {
                    flyOff(to: .left, word: word, cardID: cardID)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private enum SwipeDirection { case left, right }

    private func flyOff(to direction: SwipeDirection, word: VocabularyWord, cardID: UUID) {
        isDismissing = true

        // Capture next card ID NOW — before any state mutation changes filteredDeck.
        let nextID: UUID? = {
            guard let idx = filteredDeck.firstIndex(where: { $0.id == cardID }),
                  filteredDeck.indices.contains(idx + 1)
            else { return nil }
            return filteredDeck[idx + 1].id
        }()

        let target = CGSize(width: direction == .right ? 700 : -700, height: 0)
        withAnimation(.easeIn(duration: 0.22)) { dragOffset = target }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            switch direction {
            case .right: library.toggleLike(word)
            case .left:  library.disregard(word)
            }
            // Use the pre-captured ID — filteredDeck may have changed by now.
            currentCardID = nextID ?? filteredDeck.first?.id
            dragOffset    = .zero
            isDismissing  = false
        }
    }

    // ── Mastered action ───────────────────────────────────────────────────────

    private func masteredAction(for word: VocabularyWord, cardID: UUID) {
        masteringWordID = word.id

        let nextID: UUID? = {
            guard let idx = filteredDeck.firstIndex(where: { $0.id == cardID }),
                  filteredDeck.indices.contains(idx + 1) else { return nil }
            return filteredDeck[idx + 1].id
        }()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            library.toggleMastered(word)
            masteringWordID = nil
            currentCardID = nextID ?? filteredDeck.first?.id

            if let hit = milestoneManager.milestone(forNewCount: library.masteredIDs.count) {
                celebrationMilestone = hit
            }
        }
    }

    // ── Empty state ───────────────────────────────────────────────────────────

    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.55))
            Text("All Words Mastered!")
                .font(.custom("PlayfairDisplay-Bold", size: 32))
                .foregroundStyle(Color.appPrimary)
            Text("You've mastered every word in the deck.\nCheck your Library to revisit them.")
                .font(.custom("Inter_18pt-Regular", size: 16))
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // ── Milestones button ─────────────────────────────────────────────────────

    @ViewBuilder
    private func milestonesButton() -> some View {
        Button { showingMilestones = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10, weight: .medium))
                Text("\(milestoneManager.shownCounts.count)/\(Milestone.all.count)")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.35))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(red: 0.95, green: 0.78, blue: 0.35).opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(
                Color(red: 0.95, green: 0.78, blue: 0.35).opacity(0.25), lineWidth: 0.5))
        }
        .padding(.top, 56)
        .padding(.leading, 24)
    }

    // ── Action button helper ──────────────────────────────────────────────────

    @ViewBuilder
    private func actionButton(
        icon: String, label: String,
        color: Color = Color.appSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(color)
                Text(label).font(.custom("Inter_18pt-Regular", size: 9)).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WordDetailView  (widget deep-link target)
// ─────────────────────────────────────────────────────────────────────────────
struct WordDetailView: View {
    let word: VocabularyWord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(word.word).font(.largeTitle).bold()
                        Text(word.partOfSpeech).font(.subheadline).italic().foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Definition", systemImage: "text.book.closed").font(.headline).foregroundStyle(.blue)
                        Text(word.definition).font(.body)
                    }
                    if !word.examples.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(word.examples.count > 1 ? "Examples" : "Example",
                                  systemImage: "quote.opening").font(.headline).foregroundStyle(.blue)
                            ForEach(word.examples, id: \.self) { example in
                                Text("\u{201C}\(example)\u{201D}").font(.body).italic().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(word.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

#Preview { ContentView() }
