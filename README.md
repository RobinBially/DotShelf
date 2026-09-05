<div align="center">

<img src="docs/images/icon.png" alt="" width="88" height="88" />

# DotShelf

### Your dotfiles, within reach.

A small, native Mac app for the config files you keep coming back to.<br />
Keep them in one sidebar. Make an edit. Get back to work.

[![macOS](https://img.shields.io/badge/macOS-14%2B-292A36?style=flat-square&logo=apple&logoColor=white)](#get-started)
[![Swift](https://img.shields.io/badge/SwiftUI_%2B_AppKit-native-7865E9?style=flat-square&logo=swift&logoColor=white)](#why-dotshelf)
[![Release](https://img.shields.io/github/v/release/RobinBially/DotShelf?style=flat-square&color=7865E9)](https://github.com/RobinBially/DotShelf/releases/latest)
[![CI](https://github.com/RobinBially/DotShelf/actions/workflows/ci.yml/badge.svg)](https://github.com/RobinBially/DotShelf/actions/workflows/ci.yml)

**[Get started](#get-started)** · **[Features](#a-little-editor-with-the-right-details)** · **[Roadmap](docs/ROADMAP.md)** · **[Feedback](https://github.com/RobinBially/DotShelf/issues)**

Built by [Robin Bially](https://github.com/RobinBially) · Part of [LocalFoundry](https://github.com/localfoundry)

</div>

<br />

[![DotShelf’s native Mac interface: a sidebar of Claude Code, OpenCode and Zsh settings beside a syntax-highlighted JSONC editor with live validation and backups enabled.](docs/images/showcase.png)](docs/images/screenshot.png)

<p align="center"><sub>The actual DotShelf interface, in English, with example configuration files. Click for the full-size screenshot.</sub></p>

## Why DotShelf?

Your shell settings live in one hidden folder. Your AI tools keep their configs
in another. You know the change you want to make; finding the file is the tedious part.

DotShelf gives those files a permanent home in a sidebar. Open your Claude Code
settings, tweak an OpenCode config or update `.zshrc` in a focused native editor.
Add any other file you return to often, and give it an icon and color of its own.

**Everything stays on your Mac.** No account, network calls or telemetry.
Built with SwiftUI and AppKit, with no third-party runtime dependencies.

## A little editor with the right details

| | What you get |
| :--- | :--- |
| **A shelf for your configs** | Built-in entries for Claude Code, OpenCode and Zsh. Add your own files, including hidden ones, and collapse the sidebar into an icon rail. |
| **Comfortable editing** | Syntax highlighting for JSON, JSONC, YAML and shell, plus line numbers, search and adjustable text size. |
| **Instant JSON feedback** | Live syntax validation for JSON and JSONC. Format JSON in a click; formatting JSONC asks before removing comments. |
| **Control over your edits** | Save explicitly with **⌘S**. Save, discard or cancel when leaving unsaved changes. Failed saves keep your buffer intact. |
| **Careful file handling** | Preserve symlinks and existing permissions. Detect external changes before saving. Create new files with owner-only permissions. |
| **Backups by default** | Each save of an existing file creates a separate backup beside its target. |

English is the default interface language. See the [usage guide](docs/USAGE.md)
for keyboard shortcuts, default file locations and current limitations.

## Get started

Requires **macOS 14 Sonoma or later**. The Universal app runs on
**Apple Silicon and Intel Macs**, is signed with Developer ID and notarized by Apple.

### Homebrew

```sh
brew install --cask localfoundry/tap/dotshelf
```

Homebrew downloads the verified release from this repository through the
[LocalFoundry tap](https://github.com/localfoundry/homebrew-tap).
To update later, run `brew update && brew upgrade --cask dotshelf`.

### Direct download

**[Download DotShelf for Mac](https://github.com/RobinBially/DotShelf/releases/download/v0.1.0/DotShelf-0.1.0.zip)**

Unzip the download, drag **DotShelf.app** into **Applications**, and open it.
See the [release notes](https://github.com/RobinBially/DotShelf/releases/latest)
for changes and the SHA-256 checksum.

> **Early preview:** DotShelf is ready to try, with more improvements planned.
> See the [current limitations](docs/USAGE.md#current-limitations) and share feedback through Issues.

### Your first edit

1. **Pick a file** from the sidebar, or use **+** to add an existing one.
2. **Make your change.** JSON validation updates as you type.
3. **Press ⌘S.** Backups are enabled by default.

<details>
<summary><strong>Build from source</strong></summary>

Requires **Xcode 26.3 or newer**. Select your full Xcode installation as the active
developer directory, then run:

```sh
git clone https://github.com/RobinBially/DotShelf.git
cd DotShelf
./build-app.sh
open ~/Applications/DotShelf.app
```

The build script installs a locally signed app in `~/Applications`.
See [build options](docs/RELEASING.md#local-builds) for a different destination or a Universal build.

</details>

## What's next?

The next useful additions are **backup history with restore**, a **diff for external
changes**, **TOML support** and **Quick Open with ⌘P**. The [roadmap](docs/ROADMAP.md)
explains the ideas and their status.

Have a config workflow DotShelf could make easier?
[Open an issue](https://github.com/RobinBially/DotShelf/issues) with your use case.
Bug reports and focused pull requests are welcome.

## Under the hood

SwiftUI provides the app and sidebar; AppKit powers the text editor. English
strings live in localization resources. Regression tests cover JSON parsing,
file safety, unsaved changes, lifecycle handling and localization.

```sh
swift test
python3 scripts/check-localization.py
```

Tests require full Xcode. GitHub Actions runs the tests and builds an app artifact.
A separate manual workflow prepares a signed, notarized **draft release** once
Apple credentials are configured.

[Contributor guide](docs/CONTRIBUTING.md) · [Build & release guide](docs/RELEASING.md) · [Release review](docs/REVIEW.md)

## License

No open-source license has been selected yet.
