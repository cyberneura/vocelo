import Testing
@testable import Vocelo

@Test func defaultConfiguration() throws {
    #expect(try ConfigManager.parse(ConfigManager.example) == VoceloConfig())
    #expect(try ConfigManager.parse("# defaults\n") == VoceloConfig())
}

@Test func customConfiguration() throws {
    let config = try ConfigManager.parse("""
    language: 'en-US'
    auto_punctuation: false
    hotkey:
      modifiers: [command, option]
      key_code: 49
    """)
    #expect(config.language == "en-US")
    #expect(!config.autoPunctuation)
    #expect(config.keyCode == 49)
    #expect(config.carbonModifiers == VoceloConfig.modifierCodes["command"]! | VoceloConfig.modifierCodes["option"]!)
}

@Test(arguments: [
    "auto_punctuation: yes", "language: ''", "language: ja_JP", "unknown: true",
    "language: ja-JP\nlanguage: en-US", "hotkey:\n  key_code: 128",
    "hotkey:\n  key_code: -1", "hotkey:\n  key_code: 58",
    "hotkey:\n  modifiers: [control, control]", "hotkey:\n  modifiers: []",
    "hotkey:\n  modifiers: [hyper]", "hotkey:\n key_code: 3",
    "hotkey:\n\tkey_code: 3", "key_code: 3", "hotkey: {}",
    "hotkey:\n  modifiers: [control,]", "hotkey:\n  auto_punctuation: true"
])
func rejectsInvalidConfiguration(yaml: String) {
    #expect(throws: VoceloError.self) { try ConfigManager.parse(yaml) }
}
