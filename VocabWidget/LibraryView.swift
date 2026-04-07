// LibraryView.swift
// Full library sheet.
//
// Tabs (normal mode): Saved · Liked · Mastered · Collections
//
// When opened from the Like button (initialTab: .liked, targetWord: set):
//   - Shows the collections picker with a hardcoded "Liked ♥" row pinned at top.
//   - User toggles Liked and/or collections, then taps Done.

import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
}

/// Three dots whose fill conveys Zipf frequency: more filled = more common/easier.
@ViewBuilder
private func frequencyBadge(_ zipf: Double) -> some View {
    let filled = zipf >= 4.0 ? 3 : zipf >= 3.0 ? 2 : 1
    HStack(spacing: 3) {
        ForEach(1...3, id: \.self) { i in
            Circle()
                .fill(i <= filled ? Color.appSecondary : Color.appSecondary.opacity(0.2))
                .frame(width: 5, height: 5)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LibraryView
// ─────────────────────────────────────────────────────────────────────────────

struct LibraryView: View {

    @ObservedObject var library: UserLibrary
    /// Non-nil when opened from the Like button — puts the sheet into picker mode.
    let targetWord: VocabularyWord?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab:      Tab
    @State private var detailWord:       VocabularyWord? = nil
    @State private var showNewAlert      = false
    @State private var newCollectionName = ""

    enum Tab: String, CaseIterable {
        case liked       = "Liked"
        case mastered    = "Mastered"
        case collections = "Collections"
    }

    init(library: UserLibrary, initialTab: Tab = .liked, targetWord: VocabularyWord? = nil) {
        self.library    = library
        self.targetWord = targetWord
        _selectedTab    = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Tab picker — hidden in picker mode (opened from Like button)
                if targetWord == nil {
                    Picker("", selection: $selectedTab) {
                        ForEach(Tab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .colorScheme(.dark)
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    Divider()
                        .overlay(Color.appSecondary.opacity(0.3))
                }

                // Tab content
                switch selectedTab {
                case .liked:
                    if targetWord != nil {
                        // Picker mode: show Liked + collections as toggles
                        likePickerContent()
                    } else {
                        wordList(
                            library.likedWords,
                            emptyIcon:    "heart",
                            emptyMessage: "No liked words yet.",
                            emptyHint:    "Tap ♡ on a card to save it here."
                        )
                    }
                case .mastered:
                    wordList(
                        library.masteredWords,
                        emptyIcon:    "checkmark.seal",
                        emptyMessage: "No mastered words yet.",
                        emptyHint:    "Tap ✓ when you know a word cold."
                    )
                case .collections:
                    collectionsTab()
                }
            }
            .background(Color.appBackground)
            .navigationTitle(targetWord != nil ? "Add to…" : "My Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appPrimary)
                }
                if selectedTab == .collections && targetWord == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            newCollectionName = ""
                            showNewAlert = true
                        } label: {
                            Image(systemName: "plus").foregroundStyle(Color.appPrimary)
                        }
                    }
                }
                if selectedTab == .liked && targetWord == nil && !library.likedWords.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: library.likedExportText,
                            subject: Text("Liked Vocab Words"),
                            message: Text("Words I liked in VocabWidget")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                }
            }
            .alert("New Collection", isPresented: $showNewAlert) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    library.createCollection(name)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give your collection a name.")
            }
        }
        .sheet(item: $detailWord) { WordInfoView(word: $0) }
    }

    // ── Like picker (opened from the Like button on a card) ───────────────────
    // Shows a hardcoded "Liked ♥" row at the top, then user-created collections.

    @ViewBuilder
    private func likePickerContent() -> some View {
        if let word = targetWord {
        List {
            Section {
                // Hardcoded Liked row — pinned at top, highlighted in red
                let isLiked = library.isLiked(word)
                Button { library.toggleLike(word) } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(isLiked
                                      ? Color(red: 0.95, green: 0.35, blue: 0.35).opacity(0.15)
                                      : Color.appPrimary.opacity(0.05))
                                .frame(width: 36, height: 36)
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(isLiked
                                                 ? Color(red: 0.95, green: 0.35, blue: 0.35)
                                                 : Color.appSecondary)
                        }
                        Text("Liked")
                            .font(.custom("Inter_18pt-Regular", size: 17))
                            .foregroundStyle(Color.appPrimary)
                        Spacer()
                        if isLiked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.35))
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    isLiked
                        ? Color(red: 0.95, green: 0.35, blue: 0.35).opacity(0.06)
                        : Color.appBackground
                )
            }
            .listRowSeparatorTint(Color.appSecondary.opacity(0.2))

            if !library.collectionNames.isEmpty {
                Section("Collections") {
                    ForEach(library.collectionNames, id: \.self) { name in
                        collectionToggleRow(name: name, word: word)
                            .listRowBackground(Color.appBackground)
                            .listRowSeparatorTint(Color.appSecondary.opacity(0.2))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        } // end if let word
    }

    // ── Word list (Saved / Liked / Mastered) ──────────────────────────────────

    @ViewBuilder
    private func wordList(
        _ words: [VocabularyWord],
        emptyIcon: String,
        emptyMessage: String,
        emptyHint: String
    ) -> some View {
        if words.isEmpty {
            emptyState(icon: emptyIcon, message: emptyMessage, hint: emptyHint)
        } else {
            List(words) { word in
                wordRow(word)
                    .listRowBackground(Color.appBackground)
                    .listRowSeparatorTint(Color.appSecondary.opacity(0.2))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // ── Collections tab ───────────────────────────────────────────────────────

    @ViewBuilder
    private func collectionsTab() -> some View {
        List {
            // ── Hardcoded Liked row (always first) ────────────────────────
            Section {
                NavigationLink {
                    LikedWordsDetailView(library: library)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.35))
                            .frame(width: 22)
                        Text("Liked")
                            .font(.custom("Inter_18pt-Regular", size: 17))
                            .foregroundStyle(Color.appPrimary)
                        Spacer()
                        Text("\(library.likedWords.count)")
                            .font(.custom("Inter_18pt-Regular", size: 13))
                            .foregroundStyle(Color.appSecondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color(red: 0.95, green: 0.35, blue: 0.35).opacity(0.06))
                .listRowSeparatorTint(Color.appSecondary.opacity(0.2))
            }

            // ── User collections ──────────────────────────────────────────
            if !library.collectionNames.isEmpty {
                Section {
                    ForEach(library.collectionNames, id: \.self) { name in
                        NavigationLink {
                            CollectionDetailView(name: name, library: library)
                        } label: {
                            HStack {
                                Text(name)
                                    .font(.custom("Inter_18pt-Regular", size: 17))
                                    .foregroundStyle(Color.appPrimary)
                                Spacer()
                                Text("\(library.words(inCollection: name).count)")
                                    .font(.custom("Inter_18pt-Regular", size: 13))
                                    .foregroundStyle(Color.appSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.appBackground)
                        .listRowSeparatorTint(Color.appSecondary.opacity(0.2))
                    }
                    .onDelete { offsets in
                        offsets.forEach { i in library.deleteCollection(library.collectionNames[i]) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func collectionToggleRow(name: String, word: VocabularyWord) -> some View {
        let inCollection = library.wordIsIn(word, collection: name)
        Button { library.toggleWord(word, inCollection: name) } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(inCollection
                              ? Color(red: 0.35, green: 0.85, blue: 0.55).opacity(0.14)
                              : Color.appPrimary.opacity(0.05))
                        .frame(width: 36, height: 36)
                    Image(systemName: inCollection ? "checkmark" : "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(inCollection
                                         ? Color(red: 0.35, green: 0.85, blue: 0.55)
                                         : Color.appSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.custom("Inter_18pt-Regular", size: 17))
                        .foregroundStyle(Color.appPrimary)
                    Text("\(library.words(inCollection: name).count) word\(library.words(inCollection: name).count == 1 ? "" : "s")")
                        .font(.custom("Inter_18pt-Regular", size: 12))
                        .foregroundStyle(Color.appSecondary.opacity(0.6))
                }
                Spacer()
                if inCollection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.55))
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ── Shared row / empty state ──────────────────────────────────────────────

    @ViewBuilder
    private func wordRow(_ word: VocabularyWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { detailWord = word } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.word)
                            .font(.custom("PlayfairDisplay-Bold", size: 17))
                            .foregroundStyle(Color.appPrimary)
                        Spacer()
                        frequencyBadge(word.frequency)
                    }
                    Text(word.definition)
                        .font(.custom("Inter_18pt-Regular", size: 13))
                        .foregroundStyle(Color.appSecondary)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 18) {
                Button { library.toggleLike(word) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: library.isLiked(word) ? "heart.fill" : "heart")
                        Text("Like")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(
                        library.isLiked(word)
                            ? Color(red: 0.95, green: 0.35, blue: 0.35)
                            : Color.appSecondary
                    )
                }
                .buttonStyle(.plain)

                Button { library.toggleMastered(word) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: library.isMastered(word) ? "checkmark.seal.fill" : "checkmark.seal")
                        Text("Mastered")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(
                        library.isMastered(word)
                            ? Color(red: 0.35, green: 0.85, blue: 0.55)
                            : Color.appSecondary
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func emptyState(icon: String, message: String, hint: String) -> some View {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.appSecondary)
            Text(message)
                .font(.custom("PlayfairDisplay-Bold", size: 18))
                .foregroundStyle(Color.appPrimary)
            Text(hint)
                .font(.custom("Inter_18pt-Regular", size: 15))
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        Spacer()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CollectionDetailView
// ─────────────────────────────────────────────────────────────────────────────
struct CollectionDetailView: View {

    let name: String
    @ObservedObject var library: UserLibrary
    @State private var detailWord: VocabularyWord? = nil

    var body: some View {
        let words = library.words(inCollection: name)
        Group {
            if words.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Color.appSecondary)
                    Text("No words yet.")
                        .font(.custom("PlayfairDisplay-Bold", size: 18))
                        .foregroundStyle(Color.appPrimary)
                    Text("Add words using the ♡ Like button\non any card.")
                        .font(.custom("Inter_18pt-Regular", size: 15))
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(words) { word in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { detailWord = word } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(word.word)
                                        .font(.custom("PlayfairDisplay-Bold", size: 17))
                                        .foregroundStyle(Color.appPrimary)
                                    Spacer()
                                    frequencyBadge(word.frequency)
                                }
                                Text(word.definition)
                                    .font(.custom("Inter_18pt-Regular", size: 13))
                                    .foregroundStyle(Color.appSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 18) {
                            Button { library.toggleLike(word) } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: library.isLiked(word) ? "heart.fill" : "heart")
                                    Text("Like")
                                }
                                .font(.system(size: 13))
                                .foregroundStyle(
                                    library.isLiked(word)
                                        ? Color(red: 0.95, green: 0.35, blue: 0.35)
                                        : Color(red: 0.55, green: 0.54, blue: 0.52)
                                )
                            }
                            .buttonStyle(.plain)

                            Button { library.toggleMastered(word) } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: library.isMastered(word) ? "checkmark.seal.fill" : "checkmark.seal")
                                    Text("Mastered")
                                }
                                .font(.system(size: 13))
                                .foregroundStyle(
                                    library.isMastered(word)
                                        ? Color(red: 0.35, green: 0.85, blue: 0.55)
                                        : Color(red: 0.55, green: 0.54, blue: 0.52)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.appBackground)
                    .listRowSeparatorTint(Color.appSecondary.opacity(0.2))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            library.toggleWord(word, inCollection: name)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $detailWord) { WordInfoView(word: $0) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LikedWordsDetailView
// ─────────────────────────────────────────────────────────────────────────────
struct LikedWordsDetailView: View {
    @ObservedObject var library: UserLibrary
    @State private var detailWord: VocabularyWord? = nil

    var body: some View {
        let words = library.likedWords
        Group {
            if words.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "heart")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.35))
                    Text("No liked words yet.")
                        .font(.custom("PlayfairDisplay-Bold", size: 18))
                        .foregroundStyle(Color(red: 0.94, green: 0.93, blue: 0.90))
                    Text("Swipe right or tap ♡ on any card.")
                        .font(.custom("Inter_18pt-Regular", size: 15))
                        .foregroundStyle(Color(red: 0.55, green: 0.54, blue: 0.52))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(words) { word in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { detailWord = word } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(word.word)
                                        .font(.custom("PlayfairDisplay-Bold", size: 17))
                                        .foregroundStyle(Color(red: 0.94, green: 0.93, blue: 0.90))
                                    Spacer()
                                    frequencyBadge(word.frequency)
                                }
                                Text(word.definition)
                                    .font(.custom("Inter_18pt-Regular", size: 13))
                                    .foregroundStyle(Color(red: 0.55, green: 0.54, blue: 0.52))
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color(red: 0.14, green: 0.14, blue: 0.15))
                    .listRowSeparatorTint(Color(red: 0.55, green: 0.54, blue: 0.52).opacity(0.2))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            library.toggleLike(word)
                        } label: {
                            Label("Unlike", systemImage: "heart.slash")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(red: 0.14, green: 0.14, blue: 0.15))
        .navigationTitle("Liked")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $detailWord) { WordInfoView(word: $0) }
    }
}

#Preview { LibraryView(library: UserLibrary()) }
