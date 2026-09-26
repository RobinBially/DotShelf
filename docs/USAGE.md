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

## Running scripts

DotShelf can run scripts the way an IDE runs a configuration. Everything happens
in a real terminal, so colours, progress lines and line widths look the way they
do in Terminal.app.

1. Select a file and press **⌃R**, click the green play button in the toolbar, or
   right-click a script in the sidebar and choose **Run**. The command starts
   right away – no dialog in the way, like an IntelliJ run configuration.
2. Options are there when you want them: **⌥⌃R**, the menu next to the play
   button, or **Run with Options…** in the sidebar's context menu open the run
   sheet first, where command, working directory and name can be edited.

The command runs in a login shell – so `docker` and friends are found – inside the
file's folder. A temporary entry appears in the sidebar's **Terminal** section and
the editor shows the output:

| File | Suggested command |
|---|---|
| `deploy.sh` (executable) | `'/Users/you/project/deploy.sh'` |
| `deploy.sh` (not executable) | `zsh '/Users/you/project/deploy.sh'` |
| `docker-compose.yml`, `compose.yaml` | `docker compose -f '…' up` |
| anything else | empty – type the command yourself |

Scripts with a shebang line count as runnable even without a file extension.
Dotfiles such as `.zshrc` are configuration, so no command is suggested for them;
you can always type one.

The terminal is a real one: the keyboard goes there as soon as the run starts, so
typing works without a click first. Input reaches the process, **⌃C** stops it,
**⌘V** pastes, ⏎ sends a line, and the cursor marks the spot. A script that has
finished takes no more input – the terminal button in the toolbar or **⌥⌘T**
opens a free login shell in the same folder to keep working in.
A shell that just waits at the prompt reads **Ready**; the spinner only appears
while a command actually runs in it.
A terminal needs no file: the button sits in every toolbar (file, terminal and
empty state) and always works. The toolbar repeats the command (**Rerun**), stops
it (**Stop**, ⌘.), clears the output (**Clear**, ⌘K), opens another terminal
(**Open Terminal**) or removes the entry (**Close**). Closing asks only while a
process is actually working; an idle terminal closes right away.

Scripts and compose files carry their own icon in the sidebar – a terminal for
shell scripts, a box for docker-compose – so they are recognisable at a glance.

Terminal entries are temporary. They are not part of the sidebar list, are not
restored after a restart, and quitting DotShelf stops the scripts it started.
Commands run with your user account and may use the network; DotShelf itself
still makes no calls of its own.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Save | ⌘S |
| Reload from disk | ⌘R |
| Run the file (starts immediately) | ⌃R |
| Run with Options… (dialog first) | ⌥⌃R |
| Open a free terminal in the folder | ⌥⌘T |
| Rerun the selected terminal | ⌘R |
| Stop the running script | ⌘. |
| Clear terminal output | ⌘K |
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
- The terminal renders script output with colours, progress lines and simple
  cursor moves, but it is not a full emulator: full-screen programs (vim, htop),
  scroll regions and mouse reporting are not supported. Output is kept for the
  last 3000 lines.

The [roadmap](ROADMAP.md) covers planned improvements. The
[release review](REVIEW.md) records the original findings and their current status.
