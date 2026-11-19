import Foundation

// usage: dictionary-check <path-to-dictionary.json>
let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: dictionary-check <dictionary.json>")
    exit(2)
}
InkDictionaryStore.resourceURLOverride = URL(fileURLWithPath: args[1])

let store = InkDictionaryStore.shared
var finished = false
store.load { finished = true }
let deadline = Date().addingTimeInterval(20)
while !finished && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

print("loaded: cn=\(store.chinese.count) en=\(store.english.count) error=\(store.loadError ?? "none")")

func show(_ digits: String, _ mode: InkMode) {
    let hits = store.candidates(for: digits, mode: mode, limit: 5)
    let names = hits.map { $0.isChinese ? "\($0.primary)/\($0.phonetic)" : "\($0.primary)" }
    print("\(mode) \(digits) -> \(names.joined(separator: ", "))")
}

show("96", .chinese)
show("96636", .chinese)
show("64", .chinese)
show("826", .chinese)
show("43556", .english)
show("2665", .english)
show("4444", .english)

func showComposition(_ digits: String) {
    if let composition = store.composition(forDigits: digits) {
        let words = composition.words.map { $0.word }.joined(separator: "|")
        print("compose \(digits) -> \(composition.text) [\(words)] partial=\(composition.isPartial) gloss=\(composition.gloss)")
    } else {
        print("compose \(digits) -> none")
    }
}

showComposition("96636")
showComposition("5468426")
showComposition("966365465")
showComposition("966364264")

let syllableOptions = store.syllableOptions(for: "64")
print("syllables 64 -> " + syllableOptions.map { $0.text }.joined(separator: ","))
let completions = store.englishCompletions(prefix: "hel")
print("english hel -> " + completions.map { $0.primary }.joined(separator: ","))

// assertions used by the build check
let checks: [(String, InkMode, String)] = [
    ("96636", .chinese, "我们"),
    ("96", .chinese, "我"),
    ("64", .chinese, "你"),
    ("43556", .english, "hello"),
    ("96753", .english, "world")
]
var failed = 0
for (digits, mode, expected) in checks {
    let top = store.candidates(for: digits, mode: mode, limit: 1).first?.primary ?? "<none>"
    if top != expected {
        print("FAIL \(digits) expected \(expected) got \(top)")
        failed += 1
    }
}

// phrase composition
for (digits, expected) in [("96636", "我们"), ("5468426", "今天")] {
    let composed = store.composition(forDigits: digits)?.text ?? "<none>"
    if composed != expected {
        print("FAIL compose \(digits) expected \(expected) got \(composed)")
        failed += 1
    }
}
if !(store.composition(forDigits: "9694264")?.text.hasPrefix("我") ?? false) {
    print("FAIL compose 9694264 should start with 我")
    failed += 1
}
if !syllableOptions.contains(where: { $0.text == "ni" }) {
    print("FAIL syllable options for 64 should contain ni")
    failed += 1
}
if completions.first?.primary != "help" || !completions.contains(where: { $0.primary == "hello" }) {
    print("FAIL english completions for hel should lead with help and include hello")
    failed += 1
}
print(failed == 0 ? "ALL_OK" : "FAILURES=\(failed)")
exit(failed == 0 ? 0 : 1)
