# Contributing to SoundbarKeys

The goal: every change should pass a human code review. Write code that an experienced developer can understand, check and safely change six months from now.

## Before you call it done

```sh
python3 tools/check_conventions.py                     # must print "All conventions hold."
cd App && swift test                                    # needs Xcode (Swift Testing); Command Line Tools alone are not enough
App/make_app.sh                                         # builds, signs, installs
```

Release: bump `CFBundleShortVersionString` in `App/Resources/Info.plist`, update `CHANGELOG.md`, run `App/make_dmg.sh`, attach `App/build/SoundbarKeys-<version>.dmg` to a GitHub release `v<version>`.

## Rules

### Language and text
- Code, comments, logs and commit messages in **English**. UI strings are English keys, translated in `App/Resources/Localization/<lang>.lproj/Localizable.strings`.
- Every new UI string needs a German translation (the check script finds missing and unused ones).
- German texts use proper umlauts (ä, ö, ü, ß), never ae/oe/ue/ss.
- No em dash (U+2014) anywhere. Use a normal hyphen or an en dash, or rephrase.
- SwiftUI only localizes string *literals*: `cond ? Text("A") : Text("B")`, not `Text(cond ? "A" : "B")`.

### Structure
- **Pure logic goes into `SoundbarKeysCore`** (no UI, no network, no Keychain) and gets tests in `App/Tests/`. Volume limits, key decoding and token parsing live there. A bug fix in pure logic comes with a test that failed before.
- One file, one responsibility; describable in one sentence.
- One function, one task. Max. **50 lines** per function (SwiftUI `body` included: split into subviews), max. **5 parameters**, max. **1,000 lines** per file.
- Don't duplicate logic. If something exists in `SoundbarKeysCore`, use it.

### Readability
- Descriptive names, no abbreviation puzzles.
- No magic numbers: timeouts, limits and sizes are named constants in `Config.swift`, with the unit in the name (`pingIntervalSeconds`).
- Comments explain **why**, not what.
- Guard clauses instead of deep nesting. No dead or commented-out code.

### Robustness
- Every external call (soundbar, Bose servers, Keychain, Bonjour) can fail. Handle it: a log entry for debugging and, where the user is affected, a message that names the operation ("Token refresh failed: …", not "Error").
- `try?` only where failure has a clear meaning (e.g. "item not found"), with a comment if it isn't obvious.
- Don't trust data from the network: parse defensively (see `VolumeState.updated(with:)`).
- Few, pinned dependencies. The app itself has none; the Python login tool pins its versions in `tools/requirements.txt`.

### Privacy
- No personal or device-specific data in the repo (names, IPs, GUIDs, email addresses, tokens). The soundbar is discovered at runtime.
- Tokens only in the Keychain, never in files or logs.

### Versioning
- The app version lives in one place: `CFBundleShortVersionString` in `App/Resources/Info.plist`.
- Notable changes go into `CHANGELOG.md`.
