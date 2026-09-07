# Vocelo

A macOS 14+ menu-bar push-to-talk app, built with Apple Swift 6.3.1 and Swift
Package Manager. Hold **Control + Shift + F**, speak, then release to insert the
transcript into the focused application. Japanese (`ja-JP`) is the default.

## Build and run

Install the Swift 6.3.1 toolchain / compatible Apple command-line tools, then:

```sh
./scripts/test.sh
./scripts/build-app.sh
open dist/Vocelo.app
```

Use the `.app` bundle, not `swift run`: macOS privacy authorization needs its
bundle identity and usage descriptions. The local build is ad-hoc signed. To build
both Intel and Apple Silicon, use `ARCHS=universal ./scripts/build-app.sh`.
The executable targets macOS 14.0; the package uses Swift 6 language mode and has
no third-party dependencies.

`scripts/test.sh` runs `swift test` and supplies missing Testing framework/runtime
search paths on standalone Command Line Tools installations. Both build and test
scripts accept `BUILD_PATH` to redirect build output and `DEBUG_INFO_FORMAT=none`
for environments that cannot run the debug-symbol generator.

Choose **Grant Permissions…** from the microphone menu and allow Microphone,
Speech Recognition, and Accessibility access. Enable Vocelo in System Settings →
Privacy & Security → Accessibility if needed, then relaunch. Carbon hotkey
registration does not require Input Monitoring. The app stays out of the Dock.
Changing the app's location or signing identity can require granting access again.

Focus an editable field, hold the hotkey, speak, and release. A filled microphone
means recording; the menu shows status and errors. The app preserves the last
transcript in memory for **Copy Last Transcript** if insertion fails. It does not
save audio or transcripts to disk. **Cancel Recording**, sleep, or session lock
cancels active recording. Microphone changes finalize available audio.

## Configuration

On first launch Vocelo creates `~/.config/vocelo/config.yaml`:

```yaml
hotkey:
  key_code: 3
  modifiers: [control, shift]
auto_punctuation: true
language: ja-JP
```

Use **Open Configuration**, edit, then **Reload Configuration**. Invalid changes
leave the previous configuration active. On first-launch failure, fix the file
and reload to enable the hotkey.

The dependency-free loader accepts a restricted YAML schema: these mappings,
plain or simply quoted language/modifier scalars, booleans `true`/`false`, decimal
key codes, comments, and an inline modifiers list. Hotkey fields require exactly
two spaces. Anchors, multiline values, escape sequences, block sequences, and
other YAML features are unsupported. Unknown/duplicate fields are rejected;
omitted fields retain defaults.

Modifiers are `control`, `shift`, `option`, and `command`. At least one is required.
`key_code` is a macOS **physical virtual key code**, not a character: F = 3,
Space = 49. Modifier-only hotkeys are rejected. Carbon's modifiers do not select
left versus right Option; side-specific modifier gestures would require a separate
implementation using the physical key codes (left Option 58, right Option 61).
A registration conflict appears in the menu.

## Recognition and insertion behavior

Every request sets `requiresOnDeviceRecognition = true`. Vocelo refuses to start
if the selected recognizer does not support on-device recognition; there is no
cloud fallback. Language assets must already be available on the Mac. Check macOS
Keyboard → Dictation settings if a language is unavailable.

This initial version uses **SFSpeechRecognizer on macOS 14 and later, including
macOS 26**. SpeechAnalyzer / DictationTranscriber integration is deferred.
Recognition runs while the key is held; insertion happens after release. Each
request is finalized after 40 seconds and replaced while the audio engine keeps
running. A lock synchronizes audio routing and request finalization. Results are
assembled in recording order, using no added space for Japanese/Chinese. There
may be word-boundary inaccuracies between segments. After five seconds without
a final result, the latest partial result is retained and a warning is shown.

Short segments avoid long individual requests; they do **not** bypass service
quotas or guarantee unlimited availability. Service failures stop capture and
preserve available text without automatic error retries. Punctuation is controlled
by the Speech framework and depends on the language/model.

Insertion first tries the focused accessibility element's selected-text attribute.
If unsupported, it sends Command+V to the original process using a temporary
clipboard value. Vocelo checks that the frontmost application and the captured
accessible field are still focused and rejects recognized secure text fields.
Moving the caret inside the same field is not detected; insertion uses its current
selection. Apps that do not expose a focused accessibility element can only be
checked at the application level.

The paste fallback saves every advertised clipboard representation, checks
`NSPasteboard.changeCount` before writing, and restores after 500 ms only if the
clipboard has not changed and still carries Vocelo's unique ownership marker.
macOS offers no atomic clipboard transaction or
paste-consumed acknowledgment: a very slow app or clipboard manager can interfere.
Use Copy Last Transcript to recover. Some apps reject synthetic paste or AX writes.

## Developer ID distribution

Local builds are **not notarized**. A release requires a Developer ID Application
certificate with its private key and an Apple notarization Keychain profile.
Configure the profile using `xcrun notarytool store-credentials` outside the repo.
Then run:

```sh
DEVELOPER_ID='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='vocelo-notary' ./scripts/notarize.sh
```

The script builds a universal `.app`, signs with the hardened runtime and audio
input entitlement, submits it to Apple, staples and validates the ticket, runs
Gatekeeper assessment, then creates `dist/Vocelo.zip`. Distribution is outside
the App Store; the app is not sandboxed. No signing credentials belong in this
repository. Edit the bundle identifier/version in `Info.plist` before release if
needed. No Input Monitoring or Apple Events entitlement is used.

## Verification

`swift test` exercises defaults, overrides, and rejection of malformed or unsafe
hotkey configuration. Hardware/TCC integration requires a manual test:

- Launch the bundle, grant/deny permissions, and verify clear menu errors.
- Dictate Japanese and English into TextEdit; test replacement of selected text.
- Hold longer than 85 seconds to cross two segment boundaries; release and check order.
- Release quickly, press repeatedly during finalization, and cancel while recording.
- Change the focused app/field before finalization and confirm insertion is refused.
- Test an app requiring paste fallback; copy other content during the restore delay
  and confirm the new clipboard survives. Test image/multiple-format clipboard data.
- Test a conflicting hotkey, invalid config reload, no microphone, sleep/wake,
  on-device language unavailability, and offline transcription.
- Test the notarized universal bundle on clean macOS 14 Intel and macOS 26 Apple
  Silicon machines before publishing a release.

References: [on-device recognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition),
[on-device support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition),
[automatic punctuation](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/addspunctuation),
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
