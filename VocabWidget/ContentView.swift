// ContentView.swift
//
// Vertical paging scroll deck.
// Each card shows: word + pronunciation icon | rarity badge | definition.
// Action bar: Info | Favorite | Classroom | Library

import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
    static let appAccent     = Color(red: 0.95, green: 0.78, blue: 0.35)
}

// ── Rarity level ──────────────────────────────────────────────────────────────

private enum RarityLevel {
    case obscure, uncommon, common

    init?(zipf: Double) {
        switch zipf {
        case ..<1.8:    self = .obscure
        case 1.8..<3.0: self = .uncommon
        case 3.0..<4.0: self = .common
        default:        return nil
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

    @StateObject private var library          = UserLibrary()
    @StateObject private var scheduler        = DeckScheduler()
    @StateObject private var milestoneManager = MilestoneManager()

    @State private var currentCardID:       UUID?           = nil
    @State private var infoWord:            VocabularyWord? = nil
    @State private var quizWord:            VocabularyWord? = nil
    @State private var selectedWord:        VocabularyWord? = nil
    @State private var showingLibrary       = false
    @State private var fetchingAudioForID:  Int?            = nil
    @State private var celebrationMilestone: Milestone?     = nil
    @State private var showingMilestones    = false

    private let idToWord: [Int: VocabularyWord] =
        Dictionary(uniqueKeysWithValues: VocabularyStore.words.map { ($0.id, $0) })

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if scheduler.deck.isEmpty {
                emptyStateView()
            } else {
                cardScrollView()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if scheduler.deck.isEmpty { scheduler.buildInitialDeck() }
            if currentCardID == nil   { currentCardID = scheduler.deck.first?.id }
        }
        .onChange(of: currentCardID) { _, id in
            fetchingAudioForID = nil
            guard let id,
                  let idx = scheduler.deck.firstIndex(where: { $0.id == id })
            else { return }
            scheduler.appendPassIfNeeded(currentIndex: idx)
        }
        .onChange(of: library.learnedIDs.count) { _, count in
            if let milestone = milestoneManager.milestone(forNewCount: count) {
                celebrationMilestone = milestone
            }
        }
        .sheet(item: $infoWord)               { WordInfoView(word: $0) }
        .sheet(item: $quizWord)               { QuizView(word: $0, library: library) }
        .sheet(item: $selectedWord)           { WordDetailView(word: $0) }
        .sheet(item: $celebrationMilestone)   { MilestoneCelebrationView(milestone: $0) }
        .sheet(isPresented: $showingLibrary)  { LibraryView(library: library) }
        .sheet(isPresented: $showingMilestones) { MilestoneProgressView(milestoneManager: milestoneManager, library: library) }
        .overlay(alignment: .topLeading) { milestonesButton() }
        .onOpenURL { url in
            guard url.scheme == "vocabwidget", url.host == "word",
                  let id = Int(url.lastPathComponent),
                  let match = VocabularyStore.words.first(where: { $0.id == id })
            else { return }
            selectedWord = match
        }
    }

    // ── Scroll view ───────────────────────────────────────────────────────────

    @ViewBuilder
    private func cardScrollView() -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(scheduler.deck) { card in
                    if let word = idToWord[card.wordID] {
                        cardFace(for: word)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(card.id)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentCardID)
        .ignoresSafeArea()
    }

    // ── Card face ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private func cardFace(for word: VocabularyWord) -> some View {
        let rarity = RarityLevel(zipf: word.frequency)

        ZStack(alignment: .bottom) {

            // ── Content ───────────────────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {

                    // Word + pronunciation icon inline
                    HStack(alignment: .center, spacing: 10) {
                        Text(word.word)
                            .font(.custom("PlayfairDisplay-Bold", size: 36))
                            .foregroundStyle(Color.appPrimary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)

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
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "speaker.wave.2")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.appSecondary)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }

                    // Rarity badge
                    if let rarity {
                        rarityBadge(rarity)
                    }

                    Divider()
                        .overlay(Color.appSecondary.opacity(0.4))
                        .padding(.horizontal, 40)

                    // Definition
                    Text(word.definition)
                        .font(.custom("Inter_18pt-Regular", size: 17))
                        .foregroundStyle(Color.appPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)

                    // Quiz pill — state-aware
                    if let quiz = word.quiz, !quiz.isEmpty {
                        quizPill(for: word, questionCount: quiz.count)
                    }
                }

                Spacer()
                Color.clear.frame(height: 88)
            }

            // ── Action bar ────────────────────────────────────────────────
            HStack(spacing: 0) {
                actionButton(icon: "info.circle", label: "Info") {
                    infoWord = word
                }

                actionButton(
                    icon:  library.isFavorite(word) ? "heart.fill" : "heart",
                    label: "Favorite",
                    color: library.isFavorite(word)
                        ? Color(red: 0.95, green: 0.35, blue: 0.40)
                        : Color.appSecondary
                ) {
                    library.toggleFavorite(word)
                }

                actionButton(
                    icon:  library.isInClassroom(word) ? "graduationcap.fill" : "graduationcap",
                    label: "Classroom",
                    color: library.isInClassroom(word)
                        ? Color(red: 0.40, green: 0.70, blue: 0.95)
                        : Color.appSecondary
                ) {
                    library.toggleClassroom(word)
                }

                actionButton(icon: "list.bullet", label: "Library") {
                    showingLibrary = true
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 40)
            .background(
                Color.appBackground
                    .opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(Color.appBackground)
    }

    // ── Quiz pill ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private func quizPill(for word: VocabularyWord, questionCount: Int) -> some View {
        if library.isLearned(word) {
            // Learned — show green badge, still tappable for practice
            Button { quizWord = word } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Learned · Retake Quiz")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.25, green: 0.80, blue: 0.50))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color(red: 0.25, green: 0.80, blue: 0.50).opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color(red: 0.25, green: 0.80, blue: 0.50).opacity(0.35), lineWidth: 0.5))
            }
            .padding(.top, 4)
        } else if let expiry = library.quizCooldownExpiry(for: word) {
            // Locked — show cooldown timer
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Try again \(expiry, style: .relative) from now")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.appSecondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.appSecondary.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.appSecondary.opacity(0.25), lineWidth: 0.5))
            .padding(.top, 4)
        } else {
            // Available
            Button { quizWord = word } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Take Quiz · \(questionCount) questions")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.appAccent)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.appAccent.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.appAccent.opacity(0.35), lineWidth: 0.5))
            }
            .padding(.top, 4)
        }
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

    // ── Empty state ───────────────────────────────────────────────────────────

    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.appSecondary)
            Text("No words yet")
                .font(.custom("PlayfairDisplay-Bold", size: 28))
                .foregroundStyle(Color.appPrimary)
            Text("Check back soon.")
                .font(.custom("Inter_18pt-Regular", size: 16))
                .foregroundStyle(Color.appSecondary)
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

    // ── Action button ─────────────────────────────────────────────────────────

    @ViewBuilder
    private func actionButton(
        icon: String, label: String,
        color: Color = Color.appSecondary,
        action: @escaping () -> Void
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

// ── WordDetailView (widget deep-link) ─────────────────────────────────────────

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
                            ForEach(word.examples, id: \.self) {
                                Text("\u{201C}\($0)\u{201D}").font(.body).italic().foregroundStyle(.secondary)
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
