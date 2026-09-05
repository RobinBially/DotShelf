# Contributing to DotShelf

Use a full Xcode installation for the test suite; standalone Command Line Tools
may not include XCTest.

```bash
swift build
swift test
python3 scripts/check-localization.py
```

If your active developer directory points at Command Line Tools, select Xcode for
the command, for example `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
Use the path of your installed Xcode application.

The SwiftPM package is named DotShelf; the internal target and source directory
remain `KonfigEditor`. The existing bundle ID is retained so upgrading from
Konfig-Editor preserves file lists, icons and preferences.

| Area | Source |
|---|---|
| App lifecycle and windows | `KonfigEditorApp.swift`, `WindowAccessor.swift` |
| Sidebar and editor UI | `ContentView.swift`, `DetailView.swift` |
| Text editing and line numbers | `CodeEditor.swift`, `CodeTextView.swift`, `LineNumberRulerView.swift` |
| Files, state and validation | `Store.swift`, `ConfigFile.swift`, `FileDocument.swift`, `JSONDocument.swift` |
| Highlighting and colors | `SyntaxHighlighter.swift`, `Theme.swift` |
| Localization | `L10n.swift`, `Resources/en.lproj/Localizable.strings` |

Sources live in [`Sources/KonfigEditor`](../Sources/KonfigEditor), regression tests in
[`Tests/KonfigEditorTests`](../Tests/KonfigEditorTests). Add user-facing strings through
`L10n.text` or `L10n.format`, then run
`python3 scripts/check-localization.py --write` to refresh the English table.

For screenshots, `python3 scripts/prepare-screenshot.py` builds a separate demo app
using the real views, synthetic files and separate preferences. Capture its window
for `docs/images/screenshot.png`; no personal configuration is needed.

