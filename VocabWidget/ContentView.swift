// ContentView.swift
// Main screen — vertical paging deck with horizontal swipe-to-curate gestures.
//
// Swipe RIGHT → Save word to "Saved" list (want to learn)
// Swipe LEFT  → Disregard word (hidden forever)
// Tap Like    → Open collections picker with "Liked" pinned at top
// Tap Mastered → Mark word as mastered (removed from deck)

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

// ── Frequency rarity level ────────────────────────────────────────────────────

private enum RarityLevel {
    case obscure, rare, uncommon, advanced

    init(zipf: Double) {
        switch zipf {
        case ..<2.0:  self = .obscure
        case 2.0..<3.0: self = .rare
        case 3.0..<4.0: self = .uncommon
        default:        self = .advanced
        }
    }

    var label: String {
        switch self {
        case .obscure:  return "Obscure"
        case .rare:     return "Rare"
        case .uncommon: return "Uncommon"
        case .advanced: return "Advanced"
        }
    }

    var color: Color {
        switch self {
        case .obscure:  return Color(red: 0.65, green: 0.45, blue: 0.90) // purple
        case .rare:     return Color(red: 0.40, green: 0.65, blue: 0.95) // blue
        case .uncommon: return Color(red: 0.35, green: 0.80, blue: 0.75) // teal
        case .advanced: return Color(red: 0.45, green: 0.85, blue: 0.55) // green
        }
    }
}

// ── ContentView ───────────────────────────────────────────────────────────────

struct ContentView: View {

    let allWords = VocabularyStore.words
    @StateObject private var library          = UserLibrary()
    @StateObject private var scheduler        = DeckScheduler()
    @StateObject private var milestoneManager = MilestoneManager()

    @State private var celebrationMilestone: Milestone?      = nil
    @State private var showingMilestones    = false
    @State private var selectedWord:        VocabularyWord?  = nil
    @State private var infoWord:            VocabularyWord?  = nil
    @State private var likeWord:            VocabularyWord?  = nil   // opens like/collections picker
    @State private var showingLibrary       = false
    @State private var currentCardID:       UUID?            = nil
    @State private var fetchingAudioForID:  Int?             = nil
    @State private var masteringWordID:     Int?             = nil
    /// Horizontal drag offset per card UUID — drives the swipe gesture.
    @State private var cardDragOffset:      [UUID: CGFloat]  = [:]

    private let idToWord: [Int: VocabularyWord] =
        Dictionary(uniqueKeysWithValues: VocabularyStore.words.map { ($0.id, $0) })

    private var filteredDeck: [DeckCard] {
        let excluded = library.masteredIDs.union(library.disregardedIDs)
        return scheduler.deck.filter { !excluded.contains($0.wordID) }
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
                                        let offset = cardDragOffset[card.id] ?? 0
                                        wordPage(for: word, cardID: card.id, proxy: proxy)
                                            .containerRelativeFrame([.horizontal, .vertical])
                                            .id(card.id)
                                            .offset(x: offset)
                                            .rotationEffect(
                                                .degrees(Double(offset / 22.0).clamped(to: -13...13)),
                                                anchor: UnitPoint(x: 0.5, y: 0.85)
                                            )
                                            .overlay { swipeOverlay(offset: offset) }
                                            .simultaneousGesture(
                                                swipeGesture(cardID: card.id, word: word, proxy: proxy)
                                            )
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
                    scheduler.buildInitialDeck(
                        masteredIDs:    library.masteredIDs,
                        disregardedIDs: library.disregardedIDs
                    )
                }
                if currentCardID == nil { currentCardID = filteredDeck.first?.id }
            }
            .onChange(of: currentCardID) { _, id in
                fetchingAudioForID = nil
                guard let id,
                      let idx = filteredDeck.firstIndex(where: { $0.id == id }) else { return }
                scheduler.appendPassIfNeeded(
                    currentIndex:   idx,
                    masteredIDs:    library.masteredIDs,
                    disregardedIDs: library.disregardedIDs
                )
            }
            .sheet(item: $selectedWord)   { WordDetailView(word: $0) }
            .sheet(item: $infoWord)       { WordInfoView(word: $0) }
            .sheet(item: $likeWord)       { word in
                LibraryView(library: library, initialTab: .liked, targetWord: word)
            }
            .sheet(isPresented: $showingLibrary) { LibraryView(library: library) }
            .sheet(item: $celebrationMilestone)  { MilestoneCelebrationView(milestone: $0) }
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

    @ViewBuilder
    private func wordPage(for word: VocabularyWord, cardID: UUID, proxy: ScrollViewProxy) -> some View {
        let isMastering = masteringWordID == word.id
        let mastered    = library.isMastered(word)
        let rarity      = RarityLevel(zipf: word.frequency)

        ZStack(alignment: .bottom) {

            // ── Card content ──────────────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    // Word + rarity badge
                    VStack(spacing: 8) {
                        Text(word.word)
                            .font(.custom("PlayfairDisplay-Bold", size: 36))
                            .foregroundStyle(Color.appPrimary)
                            .multilineTextAlignment(.center)

                        // Rarity indicator
                        rarityBadge(rarity)
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
                Color.clear.frame(height: 88)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(
                isMastering ? 0.05 : 1.0,
                anchor: UnitPoint(x: 0.5, y: 0.92)
            )
            .opacity(isMastering ? 0.0 : 1.0)
            .animation(.easeIn(duration: 0.30), value: isMastering)

            // ── Action bar ────────────────────────────────────────────────
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
                    likeWord = word
                }

                // Mastered button
                Button { masteredAction(for: word, cardID: cardID, proxy: proxy) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mastered ? "checkmark.seal.fill" : "checkmark.seal")
                            .font(.system(size: 19))
                            .foregroundStyle(
                                isMastering || mastered
                                    ? Color(red: 0.35, green: 0.85, blue: 0.55)
                                    : Color.appSecondary
                            )
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

    // ── Mastered action ───────────────────────────────────────────────────────

    private func masteredAction(for word: VocabularyWord, cardID: UUID, proxy: ScrollViewProxy) {
        masteringWordID = word.id

        let nextCardID: UUID? = {
            guard let idx = filteredDeck.firstIndex(where: { $0.id == cardID }),
                  filteredDeck.indices.contains(idx + 1) else { return nil }
            return filteredDeck[idx + 1].id
        }()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            if let next = nextCardID {
                proxy.scrollTo(next, anchor: .top)
                currentCardID = next
            }
            library.toggleMastered(word)
            masteringWordID = nil

            if let hit = milestoneManager.milestone(forNewCount: library.masteredIDs.count) {
                celebrationMilestone = hit
            }
        }
    }

    // ── Swipe-to-curate gestures ──────────────────────────────────────────────

    private func swipeGesture(cardID: UUID, word: VocabularyWord, proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let h = abs(value.translation.width)
                let v = abs(value.translation.height)
                if h > v || abs(cardDragOffset[cardID] ?? 0) > 5 {
                    cardDragOffset[cardID] = value.translation.width
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                if dx > 110 {
                    saveAction(for: word, cardID: cardID, proxy: proxy)
                } else if dx < -110 {
                    disregardAction(for: word, cardID: cardID, proxy: proxy)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        cardDragOffset[cardID] = 0
                    }
                }
            }
    }

    /// Swipe right — adds word to Saved list and advances.
    private func saveAction(for word: VocabularyWord, cardID: UUID, proxy: ScrollViewProxy) {
        let nextID = nextCardID(after: cardID)
        withAnimation(.easeIn(duration: 0.22)) { cardDragOffset[cardID] = 650 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            library.toggleSaved(word)
            advanceCard(to: nextID, proxy: proxy)
            cardDragOffset[cardID] = 0
        }
    }

    /// Swipe left — disregards word permanently (filtered from deck reactively).
    private func disregardAction(for word: VocabularyWord, cardID: UUID, proxy: ScrollViewProxy) {
        let nextID = nextCardID(after: cardID)
        withAnimation(.easeIn(duration: 0.22)) { cardDragOffset[cardID] = -650 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            library.disregard(word)
            advanceCard(to: nextID, proxy: proxy)
            cardDragOffset[cardID] = 0
        }
    }

    private func nextCardID(after cardID: UUID) -> UUID? {
        guard let idx = filteredDeck.firstIndex(where: { $0.id == cardID }),
              filteredDeck.indices.contains(idx + 1) else { return nil }
        return filteredDeck[idx + 1].id
    }

    private func advanceCard(to nextID: UUID?, proxy: ScrollViewProxy) {
        guard let next = nextID else { return }
        proxy.scrollTo(next, anchor: .top)
        currentCardID = next
    }

    /// SAVE / DISREGARD overlay labels — fade in as the user drags.
    @ViewBuilder
    private func swipeOverlay(offset: CGFloat) -> some View {
        let progress = min(abs(offset) / 110.0, 1.0)
        if offset > 5 {
            VStack {
                HStack {
                    Spacer()
                    Text("SAVE")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.55))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(red: 0.35, green: 0.85, blue: 0.55), lineWidth: 3))
                        .rotationEffect(.degrees(-14))
                        .padding(.top, 110).padding(.trailing, 36)
                }
                Spacer()
            }
            .opacity(Double(progress))
        } else if offset < -5 {
            VStack {
                HStack {
                    Text("NOPE")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(Color(red: 0.95, green: 0.38, blue: 0.38))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(red: 0.95, green: 0.38, blue: 0.38), lineWidth: 3))
                        .rotationEffect(.degrees(14))
                        .padding(.top, 110).padding(.leading, 36)
                    Spacer()
                }
                Spacer()
            }
            .opacity(Double(progress))
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
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(word.examples, id: \.self) { example in
                                    Text("\u{201C}\(example)\u{201D}").font(.body).italic().foregroundStyle(.secondary)
                                }
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────
#Preview { ContentView() }
