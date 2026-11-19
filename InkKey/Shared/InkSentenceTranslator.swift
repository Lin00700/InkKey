//
//  InkSentenceTranslator.swift
//  InkKey / InkKeyKeyboard
//
//  Chinese sentence -> English reference for the bilingual sentence row.
//
//  Order of preference:
//    1. a custom OpenAI-compatible endpoint configured in the host app
//       (App Group: endpoint / model / key),
//    2. the zero-key public Google endpoint (needs Full Access for network),
//    3. the offline word-by-word gloss the keyboard assembles itself.
//
//  Lookups are debounced by ~300 ms and cached in a small LRU so typing a
//  sentence does not fire one request per keystroke.
//

import Foundation

struct InkTranslationResult {
    let english: String
    let isOnline: Bool
}

final class InkSentenceTranslator {
    static let shared = InkSentenceTranslator()

    private let session: URLSession
    private var pending: DispatchWorkItem?
    private var inFlight: URLSessionDataTask?

    private var cache: [String: String] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 160
    private let debounce: TimeInterval = 0.3

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    // MARK: Public

    /// Asks for an English reference of `chinese`.  The completion always runs
    /// on the main thread and only reports online results (never the offline
    /// gloss, the keyboard already has that).
    func request(_ chinese: String, completion: @escaping (InkTranslationResult) -> Void) {
        let text = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }

        let deliver: (String) -> Void = { english in
            let result = InkTranslationResult(english: english, isOnline: true)
            if Thread.isMainThread {
                completion(result)
            } else {
                DispatchQueue.main.async { completion(result) }
            }
        }

        if let cached = cachedValue(for: text) {
            deliver(cached)
            return
        }

        pending?.cancel()
        inFlight?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.perform(text, deliver: deliver)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        inFlight?.cancel()
        inFlight = nil
    }

    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    var cacheCount: Int { cache.count }

    // MARK: Cache

    private func cachedValue(for text: String) -> String? {
        guard let value = cache[text] else { return nil }
        return value
    }

    private func store(_ english: String, for text: String) {
        if cache[text] == nil {
            cacheOrder.append(text)
        }
        cache[text] = english
        while cacheOrder.count > cacheLimit {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    // MARK: Network

    private func perform(_ text: String, deliver: @escaping (String) -> Void) {
        let settings = InkSettings.shared
        if !settings.translateEndpoint.isEmpty,
           let request = customRequest(text, settings: settings) {
            run(request, text: text) { body in
                if let english = Self.parseOpenAI(body) {
                    self.store(english, for: text)
                    deliver(english)
                } else {
                    self.runGoogle(text, deliver: deliver)
                }
            }
            return
        }
        runGoogle(text, deliver: deliver)
    }

    private func runGoogle(_ text: String, deliver: @escaping (String) -> Void) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "zh-CN"),
            URLQueryItem(name: "tl", value: "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("InkKey/1.0", forHTTPHeaderField: "User-Agent")
        run(request, text: text) { body in
            if let english = Self.parseGoogle(body) {
                self.store(english, for: text)
                deliver(english)
            }
        }
    }

    private func run(_ request: URLRequest,
                     text: String,
                     handler: @escaping (Data) -> Void) {
        let task = session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data, !data.isEmpty else { return }
            self.inFlight = nil
            handler(data)
        }
        inFlight = task
        task.resume()
    }

    private func customRequest(_ text: String, settings: InkSettings) -> URLRequest? {
        guard let url = Self.chatCompletionsURL(from: settings.translateEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.translateKey.isEmpty {
            request.setValue("Bearer \(settings.translateKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": settings.translateModel.isEmpty ? "gpt-4o-mini" : settings.translateModel,
            "temperature": 0,
            "messages": [
                ["role": "system",
                 "content": "You are a translation engine. Translate the user's Chinese into natural, concise English. Reply with the translation only, no quotes, no notes."],
                ["role": "user", "content": text]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = data
        return request
    }

    /// Accepts `https://host/v1`, `https://host/v1/chat/completions` or a full
    /// completions URL and returns the endpoint actually to call.
    static func chatCompletionsURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") {
            text = "https://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if !text.lowercased().contains("/chat/completions") {
            text += "/chat/completions"
        }
        return URL(string: text)
    }

    // MARK: Parsing

    static func parseGoogle(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let segments = root as? [Any],
              let first = segments.first as? [Any] else { return nil }
        var out = ""
        for item in first {
            guard let parts = item as? [Any], let piece = parts.first as? String else { continue }
            out += piece
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseOpenAI(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
