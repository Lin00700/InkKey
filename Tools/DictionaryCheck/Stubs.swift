// Minimal stand-ins so InkDictionary.swift can be compiled and exercised on a
// Linux/macOS toolchain without UIKit or SwiftUI.
import Foundation

enum InkShared {
    static let dictionaryFileName = "dictionary"
}

enum InkMode {
    case chinese
    case english
}
