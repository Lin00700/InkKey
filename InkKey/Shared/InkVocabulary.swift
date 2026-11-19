//
//  InkVocabulary.swift
//  InkKey / InkKeyKeyboard
//
//  The shared 生词本.  The keyboard appends words as they are pronounced, the
//  host app lists / searches / reviews them.  Stored in the App Group
//  container with a UserDefaults fallback when the group is unavailable.
//

import Combine
import Foundation

struct VocabularyEntry: Codable, Identifiable, Hashable {
    var id: String
    var word: String
    var phonetic: String
    var meaning: String
    var addedAt: Date
    var source: String
    var timesSpoken: Int

    init(word: String, phonetic: String, meaning: String, source: String) {
        self.id = UUID().uuidString
        self.word = word
        self.phonetic = phonetic
        self.meaning = meaning
        self.addedAt = Date()
        self.source = source
        self.timesSpoken = 1
    }
}

final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()

    @Published private(set) var entries: [VocabularyEntry] = []

    private init() {
        reload()
    }

    private var fileURL: URL? {
        InkShared.containerURL?.appendingPathComponent(InkShared.vocabularyFileName)
    }

    private var fallbackKey: String { "ink.vocabulary.fallback" }

    var count: Int { entries.count }

    func contains(word: String) -> Bool {
        entries.contains { $0.word.caseInsensitiveCompare(word) == .orderedSame }
    }

    /// Adds a word if it is new, otherwise bumps how often it was heard.
    /// Returns true when a new word was inserted.
    @discardableResult
    func add(word: String, phonetic: String, meaning: String, source: String = "keyboard") -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let index = entries.firstIndex(where: {
            $0.word.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            entries[index].timesSpoken += 1
            if entries[index].phonetic.isEmpty { entries[index].phonetic = phonetic }
            save()
            return false
        }
        entries.insert(VocabularyEntry(word: trimmed, phonetic: phonetic, meaning: meaning, source: source), at: 0)
        save()
        return true
    }

    func remove(_ entry: VocabularyEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where entries.indices.contains(index) {
            entries.remove(at: index)
        }
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    func markSpoken(_ entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].timesSpoken += 1
        save()
    }

    func search(_ query: String) -> [VocabularyEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.word.localizedCaseInsensitiveContains(q)
                || $0.meaning.localizedCaseInsensitiveContains(q)
                || $0.phonetic.localizedCaseInsensitiveContains(q)
        }
    }

    func reload() {
        var loaded: [VocabularyEntry] = []
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            loaded = (try? JSONDecoder().decode([VocabularyEntry].self, from: data)) ?? []
        } else if let data = InkShared.defaults.data(forKey: fallbackKey) {
            loaded = (try? JSONDecoder().decode([VocabularyEntry].self, from: data)) ?? []
        }
        loaded.sort { $0.addedAt > $1.addedAt }
        entries = loaded
    }

    private func save() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(entries) else { return }
        if let url = fileURL {
            do {
                try data.write(to: url, options: .atomic)
                return
            } catch {
                // fall through to defaults
            }
        }
        InkShared.defaults.set(data, forKey: fallbackKey)
    }
}
