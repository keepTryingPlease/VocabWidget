// LibraryView.swift
// Full library sheet — opened from the books icon next to the level pill.
// Three tabs: Liked words, Mastered words, and user-created Collections.

import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LibraryView
// ─────────────────────────────────────────────────────────────────────────────
struct LibraryView: View {

    @ObservedObject var library: UserLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab:  Tab          = .liked
    @State private var detailWord:   VocabularyWord? = nil
    @State private var showNewAlert  = false
    @State private var newCollectionName = ""

    enum Tab: String, CaseIterable {
        case liked       = "Liked"
        case mastered    = "Mastered"
        case collections = "Collections"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Tab picker ────────────────────────────────────────────
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

                // ── Tab content ───────────────────────────────────────────
                switch selectedTab {
                case .liked:
                    wordList(
                        library.likedWords,
                        emptyIcon:    "heart",
                        emptyMessage: "No liked words yet.",
                        emptyHint:    "Tap ♡ on any word to save it here."
                    )
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
            .navigationTitle("My Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appPrimary)
                }
                // "+" only visible on the Collections tab
                if selectedTab == .collections {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            newCollectionName = ""
                            showNewAlert = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                }
            }
            .alert("New Collection", isPresented: $showNewAlert) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { library.createCollection(name) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give your collection a name.")
            }
        }
        .sheet(item: $detailWord) { WordInfoView(word: $0) }
    }

    // ── Word list (Liked / Mastered) ──────────────────────────────────────────

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
        if library.collectionNames.isEmpty {
            emptyState(
                icon:    "square.stack",
                message: "No collections yet.",
                hint:    "Tap + to create one, then add words\nusing the Collections button on any card."
            )
        } else {
            List {
                ForEach(library.collectionNames, id: \.self) { name in
                    NavigationLink {
                        CollectionDetailView(name: name, library: library)
                    } label: {
                        HStack {
                            Text(name)
                                .font(.custom("PlayfairDisplay-Bold", size: 17))
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
                    offsets.forEach { i in
                        library.deleteCollection(library.collectionNames[i])
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // ── Shared row / empty state ──────────────────────────────────────────────

    @ViewBuilder
    private func wordRow(_ word: VocabularyWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── Word header + definition (tap to open detail) ─────────
            Button { detailWord = word } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.word)
                            .font(.custom("PlayfairDisplay-Bold", size: 17))
                            .foregroundStyle(Color.appPrimary)
                        Spacer()
                        Text(word.level.capitalized)
                            .font(.custom("Inter_18pt-Regular", size: 11))
                            .foregroundStyle(Color.appSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appPrimary.opacity(0.07))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.appSecondary.opacity(0.3), lineWidth: 0.5))
                    }
                    Text(word.definition)
                        .font(.custom("Inter_18pt-Regular", size: 13))
                        .foregroundStyle(Color.appSecondary)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)

            // ── Like / Mastered icons ─────────────────────────────────
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
// Words inside a single collection — pushed via NavigationLink.
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
                    Text("Add words using the Collections\nbutton on any card.")
                        .font(.custom("Inter_18pt-Regular", size: 15))
                        .foregroundStyle(Color.appSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(words) { word in
                    VStack(alignment: .leading, spacing: 8) {

                        // ── Word header + definition (tap to open detail) ─
                        Button { detailWord = word } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(word.word)
                                        .font(.custom("PlayfairDisplay-Bold", size: 17))
                                        .foregroundStyle(Color.appPrimary)
                                    Spacer()
                                    Text(word.level.capitalized)
                                        .font(.custom("Inter_18pt-Regular", size: 11))
                                        .foregroundStyle(Color.appSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.appPrimary.opacity(0.07))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().strokeBorder(Color.appSecondary.opacity(0.3), lineWidth: 0.5))
                                }
                                Text(word.definition)
                                    .font(.custom("Inter_18pt-Regular", size: 13))
                                    .foregroundStyle(Color.appSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)

                        // ── Like / Mastered icons ─────────────────────────
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

#Preview {
    LibraryView(library: UserLibrary())
}
