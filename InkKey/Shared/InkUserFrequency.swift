//
//  InkUserFrequency.swift
//  InkKey / InkKeyKeyboard
//
//  Remembers which words and phrases the user actually picks, in the shared
//  App Group, so the same word ranks higher the next time the same syllables
//  are typed.  Deliberately tiny: a word -> count map in UserDefaults.
//

import Foundation

final class InkUserFrequency {
    static let shared = InkUserFrequency()

    private var counts: [String: Int] = [:]
    private let lock = NSLock()
    private var idleSave: DispatchWorkItem?

    private init() {
        load()
    }

    // MARK: Reading

    /// Additive score handed to the dictionary ranking (0 when never picked).
    func boost(for word: String) -> Double {
        let count = self.count(for: word)
        guard count > 0 else { return 0 }
        return min(6.0, log1p(Double(count)) * 1.8)
    }

    func count(for word: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[word] ?? 0
    }

    var totalPicks: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.values.reduce(0, +)
    }

    var topWords: [(word: String, count: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return counts.sorted { $0.value > $1.value }
            .prefix(12)
            .map { (word: $0.key, count: $0.value) }
    }

    // MARK: Writing

    func record(_ words: [String], amount: Int = 1) {
        var changed = false
        lock.lock()
        for word in words where !word.isEmpty {
            counts[word, default: 0] += amount
            changed = true
        }
        lock.unlock()
        guard changed else { return }
        scheduleSave()
    }

    func record(_ word: String, amount: Int = 1) {
        record([word], amount: amount)
    }

    func reset() {
        lock.lock()
        counts.removeAll()
        lock.unlock()
        InkShared.defaults.removeObject(forKey: InkKeyName.userFrequency)
    }

    // MARK: Persistence

    private func load() {
        guard let data = InkShared.defaults.data(forKey: InkKeyName.userFrequency),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return
        }
        counts = decoded
    }

    private func scheduleSave() {
        idleSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        idleSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        lock.lock()
        let snapshot = counts
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        InkShared.defaults.set(data, forKey: InkKeyName.userFrequency)
    }
}
