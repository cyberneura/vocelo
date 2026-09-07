# Vocelo

macOS 14+ menu-bar push-to-talk dictation app. Swift 6 language mode, Swift Package Manager,
no third-party dependencies. Frameworks: AppKit, Carbon (global hotkey), Speech
(`SFSpeechRecognizer`, on-device only), AVFoundation (audio tap), ApplicationServices
(Accessibility text insertion).

## Layout

- `Sources/Vocelo/AppDelegate.swift` — status item, menu, hotkey / menu session state machine
- `Sources/Vocelo/HotKeyManager.swift` — Carbon `RegisterEventHotKey`, exclusive registration
- `Sources/Vocelo/SpeechManager.swift` — audio engine, 40 s segment rotation, live transcript
- `Sources/Vocelo/TranscriptOverlay.swift` — non-activating HUD panel shown while recording
- `Sources/Vocelo/TextInsertion.swift` — insert via Accessibility, pasteboard fallback
- `Sources/Vocelo/ConfigManager.swift` — `~/.config/vocelo/config.yaml`, restricted YAML loader
- `Tests/VoceloTests/` — swift-testing tests for the config loader
- `scripts/build-app.sh` / `test.sh` / `notarize.sh`
- `.j-menu.yaml` — j-menu entries for build, sign, run, test, notarize

## Build, test, run

```sh
./scripts/test.sh
SIGN_IDENTITY="Developer ID Application: Cyberneura K.K. (2YN5TLNQ9J)" ./scripts/build-app.sh
open dist/Vocelo.app
```

- Always run the `.app` bundle, never `swift run`: privacy permissions are tied to the bundle.
- Sign local builds with `SIGN_IDENTITY`. Ad-hoc signing (the default when unset) changes the
  code hash each build and macOS asks for Microphone / Speech / Accessibility again.
- Swift build does not work inside the Claude Code Bash sandbox (module cache under
  `/var/folders` and SwiftPM's nested `sandbox-exec` are blocked). Ask the user to disable it.
- Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist` with each change.

## Concurrency rules

All app classes are `@MainActor`. Callbacks from Speech, `AVAudioEngine` taps, and
`SFSpeechRecognizer.requestAuthorization` arrive on background queues. Mark those closures
`@Sendable` and hop to the main actor with `Task { @MainActor in … }`. A closure inferred as
MainActor-isolated traps at runtime (`dispatch_assert_queue_fail`) instead of failing to compile.

## Debugging

- Crash reports: `~/Library/Logs/DiagnosticReports/Vocelo-*.ips` (JSON after the first line).
- Permission state: `sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db
  "select service, client, auth_value from access where client like '%vocelo%'"`.
  `auth_value` 2 means allowed. A missing Microphone row makes recording refuse to start.
- Hotkey conflicts: `RegisterEventHotKey` with `kEventHotKeyExclusive` returns `-9878` when
  another process already holds the combination.

## Release

`scripts/notarize.sh` needs `DEVELOPER_ID` and `NOTARY_PROFILE`; it builds universal, signs with
hardened runtime, notarizes, staples, and writes `dist/Vocelo.zip`.
