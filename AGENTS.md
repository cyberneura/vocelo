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
- `VERSION` — the released version; `Info.plist` carries `__VERSION__` and is filled in at build
- `scripts/build-app.sh` / `test.sh` / `make-dmg.sh` / `notarize.sh` / `release.sh`
- `.github/workflows/release.yml` — build, sign, notarize and publish on a version change
- `.j-menu.yaml` — j-menu entries for build, sign, run, test, release

## Build, test, run

```sh
./scripts/test.sh
SIGN_IDENTITY="Developer ID Application: Cyberneura K.K. (2YN5TLNQ9J)" ./scripts/build-app.sh
open dist/Vocelo.app
```

- Always run the `.app` bundle, never `swift run`: privacy permissions are tied to the bundle.
- `/Applications/Vocelo.app` (the Homebrew cask) and `dist/Vocelo.app` share the bundle id, so
  anything addressing `com.cyberneura.vocelo` -- the j-menu quit entry, `open -b` -- may reach
  either. Name the path when it matters. TCC grants are per copy, so each asks separately.
- Sign local builds with `SIGN_IDENTITY`. Ad-hoc signing (the default when unset) changes the
  code hash each build and macOS asks for Microphone / Speech / Accessibility again.
- Swift build does not work inside the Claude Code Bash sandbox (module cache under
  `/var/folders` and SwiftPM's nested `sandbox-exec` are blocked). Ask the user to disable it.
- Bump `VERSION` in the change itself; both `Info.plist` version keys are filled in from it.
  Merging that change to main is what publishes the version, so do not also run
  `scripts/release.sh` afterwards -- that would put out a second release with no code in it.

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

- `.github/workflows/release.yml` runs on every push to main. It decides by asking GitHub whether
  `v<VERSION>` is already published, not by looking at the diff, so squash / rebase / re-push all
  reach the same answer and a failed run is retried by pushing the fix.
- `scripts/release.sh [patch|minor|major]` bumps `VERSION`, pushes it to main and watches the run.
  It is for releasing what is already on main; a change that carries its own bump needs nothing.
- The build needs six `APPLE_*` repository secrets (certificate, its password, signing identity,
  Apple ID, app-specific password, team id). They are set; a missing one fails the job early
  rather than silently shipping an unsigned build.
- The build needs an Xcode at or above the `swift-tools-version` in `Package.swift` (6.2, so Xcode
  26.0 or newer): SwiftPM refuses a manifest newer than its own toolchain. The job picks the newest
  Xcode on the image rather than its default, because a runner image's default can sit well behind
  what it carries -- `macos-15` defaults to Xcode 16.x (Swift 6.1) while also shipping 26.3.
- Homebrew is `cyberneura/homebrew-tap`'s `Casks/vocelo.rb`. The tap's own hourly job reads this
  project's latest release and rewrites version / url / sha256, so nothing here pushes to the tap
  and a new version reaches `brew upgrade` up to an hour late.
- `scripts/notarize.sh` (needs `DEVELOPER_ID` and `NOTARY_PROFILE`) is the same sequence locally.
