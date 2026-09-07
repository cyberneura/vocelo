import Foundation
import Carbon

struct VoceloConfig: Equatable, Sendable {
    var keyCode: UInt32 = 9 // ANSI V; physical virtual key code, independent of layout.
    var modifiers: [String] = ["control", "shift"]
    var autoPunctuation = true
    var language = "ja-JP"

    var carbonModifiers: UInt32 {
        modifiers.reduce(0) { $0 | Self.modifierCodes[$1, default: 0] }
    }

    static let modifierCodes: [String: UInt32] = [
        "control": UInt32(controlKey), "shift": UInt32(shiftKey),
        "option": UInt32(optionKey), "command": UInt32(cmdKey)
    ]
}

struct VoceloError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum ConfigManager {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vocelo/config.yaml")
    }
    static let example = """
    # Vocelo configuration. Reload from the menu after editing.
    hotkey:
      key_code: 9 # Physical V key (macOS virtual key code).
      modifiers: [control, shift]
    auto_punctuation: true
    language: ja-JP
    """ + "\n"

    static func load() throws -> VoceloConfig {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try example.write(to: url, atomically: true, encoding: .utf8)
        }
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    /// A deliberately restricted YAML schema: mappings, simple scalars, and a flow
    /// sequence for modifiers. Unsupported YAML constructs fail instead of being ignored.
    static func parse(_ yaml: String) throws -> VoceloConfig {
        var config = VoceloConfig()
        var inHotkey = false
        var seen = Set<String>()
        for (index, raw) in yaml.components(separatedBy: .newlines).enumerated() {
            let line = raw.components(separatedBy: "#")[0]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            func invalid(_ detail: String) -> VoceloError {
                VoceloError("Config line \(index + 1): \(detail)")
            }
            guard !line.contains("\t"), let colon = trimmed.firstIndex(of: ":") else {
                throw invalid("use spaces and key: value syntax")
            }
            let indent = line.prefix(while: { $0 == " " }).count
            let key = String(trimmed[..<colon])
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if indent == 0 { inHotkey = false }
            if key == "hotkey", indent == 0, value.isEmpty {
                guard seen.insert(key).inserted else { throw invalid("duplicate hotkey") }
                inHotkey = true
                continue
            }
            guard indent == 0 || (indent == 2 && inHotkey) else {
                throw invalid("hotkey fields must be indented exactly two spaces")
            }
            let path = inHotkey ? "hotkey.\(key)" : key
            guard seen.insert(path).inserted else { throw invalid("duplicate \(path)") }
            func scalar(_ input: String) -> String {
                if input.count >= 2, let first = input.first,
                   (first == "\"" || first == "'"), input.last == first {
                    return String(input.dropFirst().dropLast())
                }
                return input
            }
            switch path {
            case "hotkey.key_code":
                guard let code = UInt32(value), code <= 127 else {
                    throw invalid("key_code must be an integer from 0 to 127")
                }
                // Modifier-only hotkeys do not produce RegisterEventHotKey events.
                guard ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code) else {
                    throw invalid("key_code must be a non-modifier key")
                }
                config.keyCode = code
            case "hotkey.modifiers":
                guard value.hasPrefix("["), value.hasSuffix("]") else {
                    throw invalid("modifiers must use [control, shift] syntax")
                }
                let names = value.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
                    .map { scalar($0.trimmingCharacters(in: .whitespaces)) }
                guard !names.isEmpty, names.allSatisfy({ VoceloConfig.modifierCodes[$0] != nil }),
                      Set(names).count == names.count else {
                    throw invalid("use unique control, shift, option, or command modifiers")
                }
                config.modifiers = names
            case "auto_punctuation":
                guard value == "true" || value == "false" else { throw invalid("expected true or false") }
                config.autoPunctuation = value == "true"
            case "language":
                let language = scalar(value)
                guard language.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil else {
                    throw invalid("expected a language tag such as ja-JP or en-US")
                }
                config.language = language
            default: throw invalid("unknown setting \(path)")
            }
        }
        return config
    }
}
