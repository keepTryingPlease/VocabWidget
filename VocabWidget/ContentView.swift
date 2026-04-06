// ContentView.swift
// The main screen of the app.
//
// Paging is driven by a native ScrollView with .scrollTargetBehavior(.paging)
// backed by UIKit's hardware-accelerated scroll layer, giving full 120 Hz
// throughput. The previous hand-rolled DragGesture approach forced a full
// SwiftUI layout pass on every finger-movement event, causing frame drops.

import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
}

struct ContentView: View {

    let allWords = VocabularyStore.words
    @StateObject private var library          = UserLibrary()
    @StateObject private var scheduler        = DeckScheduler()
    @StateObject private var milestoneManager = MilestoneManager()

    @State private var celebrationMilestone: Milestone? = nil
    @State private var showingMilestones    = false
    @State private var selectedWord:        VocabularyWord? = nil
    @State private var infoWord:            VocabularyWord? = nil
    @State private var collectionsWord:     VocabularyWord? = nil
    @State private var showingLibrary       = false
    @State private var currentCardID:       UUID?  = nil
    @State private var fetchingAudioForID:  Int?   = nil
    /// Word ID currently playing the inhale-to-mastered animation.
    @State private var masteringWordID:     Int?   = nil

    // Lookup table — built once per word bank load, reused everywhere.
    private let idToWord: [Int: VocabularyWord] =
        Dictionary(uniqueKeysWithValues: VocabularyStore.words.map { ($0.id, $0) })

    // Deck cards with mastered words filtered out.
    // Reacts to both scheduler.deck and library.masteredIDs (@Published on both).
    private var filteredDeck: [DeckCard] {
        let masteredSet = library.masteredIDs
        return scheduler.deck.filter { !masteredSet.contains($0.wordID) }
    }

    private var hasUnmasteredWords: Bool {
        VocabularyStore.words.contains { !library.masteredIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if filteredDeck.isEmpty {
                    emptyStateView()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredDeck) { card in
                                    if let word = idToWord[card.wordID] {
                                        wordPage(for: word, cardID: card.id, proxy: proxy)
                                            .containerRelativeFrame([.horizontal, .vertical])
                                            .id(card.id)
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollIndicators(.hidden)
                        .scrollPosition(id: $currentCardID)
                        .ignoresSafeArea()
                    }
                }
            }
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .onAppear {
                if scheduler.deck.isEmpty {
                    scheduler.buildInitialDeck(masteredIDs: library.masteredIDs, userSkill: library.userSkill)
                }
                if currentCardID == nil { currentCardID = filteredDeck.first?.id }
            }
            .onChange(of: currentCardID) { _, id in
                fetchingAudioForID = nil
                // When within 8 cards of the end, silently loop by appending a
                // fresh zone-sorted pass at the current skill level.
                guard let id,
                      let idx = filteredDeck.firstIndex(where: { $0.id == id }) else { return }
                scheduler.appendPassIfNeeded(
                    currentIndex: idx,
                    masteredIDs:  library.masteredIDs,
                    userSkill:    library.userSkill
                )
            }
            .sheet(item: $selectedWord)        { WordDetailView(word: $0) }
            .sheet(item: $infoWord)            { WordInfoView(word: $0) }
            .sheet(isPresented: $showingLibrary) { LibraryView(library: library) }
            .sheet(item: $collectionsWord) {
                LibraryView(library: library, initialTab: .collections, targetWord: $0)
            }
            .sheet(item: $celebrationMilestone) { MilestoneCelebrationView(milestone: $0) }
            .sheet(isPresented: $showingMilestones) {
                MilestoneProgressView(milestoneManager: milestoneManager, library: library)
            }
            .overlay(alignment: .topLeading) {
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
            .onOpenURL { url in
                guard url.scheme == "vocabwidget",
                      url.host == "word",
                      let id = Int(url.lastPathComponent),
                      let match = allWords.first(where: { $0.id == id })
                else { return }
                selectedWord = match
            }
        }
    }

    // ── Empty state ───────────────────────────────────────────────────────────
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 0) {
            Spacer()

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
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Word page ─────────────────────────────────────────────────────────────
    // The page is split into two layers in a ZStack:
    //   1. Card content  — animates (inhale) when mastered
    //   2. Action bar    — stays fixed so the mastered button is visible during the animation
    @ViewBuilder
    private func wordPage(for word: VocabularyWord, cardID: UUID, proxy: ScrollViewProxy) -> some View {
        let isMastering = masteringWordID == word.id
        let mastered    = library.isMastered(word)

        ZStack(alignment: .bottom) {

            // ── Card content (animated on master) ────────────────────────
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Text(word.word)
                        .font(.custom("PlayfairDisplay-Bold", size: 36))
                        .foregroundStyle(Color.appPrimary)
                        .multilineTextAlignment(.center)

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
                        ProgressView()
                            .tint(Color.appSecondary)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "speaker.wave.2")
                            .font(.title2)
                            .foregroundStyle(Color.appSecondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.top, 16)

                Spacer()
                // Spacer matching the action bar height so content is vertically centred.
                Color.clear.frame(height: 88)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // ── Inhale animation ──────────────────────────────────────────
            // Shrinks toward the action bar (anchor y=1) with easeIn so it
            // accelerates, feeling "pulled in" rather than just fading away.
            .scaleEffect(
                isMastering ? 0.05 : 1.0,
                anchor: UnitPoint(x: 0.5, y: 0.92)
            )
            .opacity(isMastering ? 0.0 : 1.0)
            .animation(.easeIn(duration: 0.30), value: isMastering)

            // ── Action bar (not animated, always visible) ─────────────────
            HStack(spacing: 0) {
                actionButton(icon: "info.circle", label: "Info") {
                    infoWord = word
                }
                actionButton(
                    icon:  library.isLiked(word) ? "heart.fill" : "heart",
                    label: "Like",
                    color: library.isLiked(word)
                        ? Color(red: 0.95, green: 0.35, blue: 0.35) : Color.appSecondary
                ) {
                    library.toggleLike(word)
                }

                // ── Mastered button — inline so the icon can spring-pulse ──
                Button { masteredAction(for: word, cardID: cardID, proxy: proxy) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mastered ? "checkmark.seal.fill" : "checkmark.seal")
                            .font(.system(size: 19))
                            .foregroundStyle(
                                isMastering || mastered
                                    ? Color(red: 0.35, green: 0.85, blue: 0.55)
                                    : Color.appSecondary
                            )
                            // Spring-pulse when the inhale starts
                            .scaleEffect(isMastering ? 1.45 : 1.0)
                            .animation(
                                .spring(response: 0.22, dampingFraction: 0.4).delay(0.06),
                                value: isMastering
                            )
                        Text("Mastered")
                            .font(.custom("Inter_18pt-Regular", size: 9))
                            .foregroundStyle(
                                isMastering || mastered
                                    ? Color(red: 0.35, green: 0.85, blue: 0.55)
                                    : Color.appSecondary
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .disabled(isMastering)

                actionButton(icon: "square.stack", label: "Collections") {
                    collectionsWord = word
                }
                actionButton(icon: "list.bullet", label: "Library") {
                    showingLibrary = true
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // ── Mastered action ───────────────────────────────────────────────────────
    private func masteredAction(for word: VocabularyWord, cardID: UUID, proxy: ScrollViewProxy) {
        // Kick off the inhale animation.
        masteringWordID = word.id

        // Capture the next card's UUID now, before anything changes.
        let nextCardID: UUID? = {
            guard let idx = filteredDeck.firstIndex(where: { $0.id == cardID }),
                  filteredDeck.indices.contains(idx + 1) else { return nil }
            return filteredDeck[idx + 1].id
        }()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            // Scroll to the next card.
            if let next = nextCardID {
                proxy.scrollTo(next, anchor: .top)
                currentCardID = next
            }

            // Mark mastered — filteredDeck automatically drops this word everywhere.
            library.toggleMastered(word)
            masteringWordID = nil

            // Rebuild everything ahead of the current card using the updated skill
            // level. The next card is already on screen; all cards after it get
            // fresh zone-sorted calibration.
            if let anchor = nextCardID {
                scheduler.rebuildAhead(
                    after:      anchor,
                    masteredIDs: library.masteredIDs,
                    userSkill:   library.userSkill
                )
            }

            if let hit = milestoneManager.milestone(forNewCount: library.masteredIDs.count) {
                celebrationMilestone = hit
            }
        }
    }

    // ── Action button ─────────────────────────────────────────────────────────
    @ViewBuilder
    private func actionButton(
        icon: String,
        label: String,
        color: Color = Color.appSecondary,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(color)
                Text(label)
                    .font(.custom("Inter_18pt-Regular", size: 9))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WordDetailView
// Full-screen detail sheet — used by the widget deep link (vocabwidget://word/id).
// ─────────────────────────────────────────────────────────────────────────────
struct WordDetailView: View {
    let word: VocabularyWord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text(word.word)
                            .font(.largeTitle)
                            .bold()
                        Text(word.partOfSpeech)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Definition", systemImage: "text.book.closed")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(word.definition)
                            .font(.body)
                    }

                    if !word.examples.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(word.examples.count > 1 ? "Examples" : "Example",
                                  systemImage: "quote.opening")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(word.examples, id: \.self) { example in
                                    Text("\u{201C}\(example)\u{201D}")
                                        .font(.body)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(word.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────
#Preview {
    ContentView()
}
