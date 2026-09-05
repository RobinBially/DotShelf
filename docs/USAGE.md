# Using DotShelf

## Getting started

1. Select a file in the sidebar or click **+** to add an existing file.
2. Edit and press **⌘S** to save. An orange indicator marks unsaved changes.
3. Click a file's icon to customize it, or use its context menu for more actions.

The document-with-plus button creates an empty `untitled.txt` in your home folder.
Rename it through the context menu. Removing an entry only removes it from the
sidebar; renaming changes the filename on disk.

Built-in entries:

| File | Location |
|---|---|
| Claude Code – Settings | `~/.claude/settings.json` |
| Claude Code – Local mode | `~/.claude-local/settings.json` |
| OpenCode | `~/.config/opencode/opencode.json` |
| OpenCode – TUI | `~/.config/opencode/tui.json` |
| Zsh | `~/.zshrc` |

“Local mode” refers to a separate `claude-local` configuration directory.
Project-local Claude settings are not discovered automatically; add them with **+**.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Save | ⌘S |
| Reload from disk | ⌘R |
| Find | ⌘F |
| Next / previous match | ⌘G / ⌘⇧G |
| Toggle line comments | ⌘/ |
| Indent / unindent | Tab / ⇧Tab |
| Duplicate line or selection | ⌘D |
| Delete line(s) | ⌘⌫ |
| Move line(s) | ⌥⇧↑ / ⌥⇧↓ |
| Increase / decrease font size | ⌘+ / ⌘− |
| Reset font size to 13 pt | ⌘0 |

## Current limitations

- JSONC formatting removes comments after confirmation; it does not preserve them.
- Validation checks syntax, not a tool's JSON schema. Invalid content may still be
  saved intentionally.
- YAML and shell have highlighting but no semantic validation. TOML, full JSON5
  and manual language selection are not yet supported; unknown extensions use shell
  highlighting.
- Conflict detection stops a save and asks you to reload. Copy your edits before
  reloading if you need to merge them; there is no visual merge editor yet.
- Backups have no in-app browser, automatic cleanup or restore button yet.

The [roadmap](ROADMAP.md) covers planned improvements. The
[release review](REVIEW.md) records the original findings and their current status.

