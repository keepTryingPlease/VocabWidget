// CollectionsPickerView.swift
// Sheet shown when the user taps the Collections button on a word card.
// Lists all existing collections with a checkmark when the word is already
// in them, and lets the user create a new collection inline.

import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
}

struct CollectionsPickerView: View {

    let word: VocabularyWord
    @ObservedObject var library: UserLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var showingNewField = false
    @State private var newName = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {

                // ── Create new collection ─────────────────────────────────
                Section {
                    if showingNewField {
                        HStack(spacing: 12) {
                            TextField("Collection name", text: $newName)
                                .foregroundStyle(Color.appPrimary)
                                .focused($fieldFocused)
                                .onSubmit { commitNew() }
                            Button("Create", action: commitNew)
                                .bold()
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            showingNewField = true
                            fieldFocused    = true
                        } label: {
                            Label("New Collection", systemImage: "plus")
                        }
                    }
                }

                // ── Existing collections ──────────────────────────────────
                if !library.collectionNames.isEmpty {
                    Section("My Collections") {
                        ForEach(library.collectionNames, id: \.self) { name in
                            Button {
                                library.toggleWord(word, inCollection: name)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .foregroundStyle(Color.appPrimary)
                                        Text("\(library.words(inCollection: name).count) words")
                                            .font(.caption)
                                            .foregroundStyle(Color.appSecondary)
                                    }
                                    Spacer()
                                    if library.wordIsIn(word, collection: name) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                            .bold()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appPrimary)
                }
            }
        }
    }

    private func commitNew() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        library.createCollection(name)
        library.toggleWord(word, inCollection: name)
        newName         = ""
        showingNewField = false
        fieldFocused    = false
    }
}

#Preview {
    CollectionsPickerView(
        word: VocabularyStore.words[0],
        library: UserLibrary()
    )
}
