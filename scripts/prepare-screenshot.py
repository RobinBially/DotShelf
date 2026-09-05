#!/usr/bin/env python3
"""Build the real DotShelf UI with synthetic files and separate preferences.

Open the printed demo app and capture its window for docs/images/screenshot.png.
Only the demo copy's initial data, window size and displayed example paths differ.
"""
from pathlib import Path
import json
import plistlib
import shutil
import subprocess


def replace_exact(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError('Screenshot override no longer matches; aborting before build.')
    return source.replace(old, new)


root = Path(__file__).resolve().parents[1]
work = root / '.build' / 'screenshot'
sources = work / 'Sources' / 'KonfigEditor'
sources.mkdir(parents=True, exist_ok=True)
for source in (root / 'Sources' / 'KonfigEditor').glob('*.swift'):
    shutil.copy2(source, sources / source.name)
shutil.copytree(root / 'Sources/KonfigEditor/Resources', sources / 'Resources', dirs_exist_ok=True)
(work / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DotShelf", defaultLocalization: "en", platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "KonfigEditor", path: "Sources/KonfigEditor",
        resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)])])
''')
fixtures = work / 'fixtures'
fixtures.mkdir(exist_ok=True)
sample = '''{
  // Example configuration — no credentials
  "$schema": "https://opencode.ai/config.json",
  "theme": "system",
  "autoupdate": false,
  "permission": {
    "edit": "ask",
    "bash": "ask",
    "webfetch": "allow"
  },
  "instructions": [
    "AGENTS.md",
    "docs/conventions.md"
  ]
}'''
for name, data in {
    'claude-settings.json': '{"permissions": {"defaultMode": "default"}}',
    'claude-local-settings.json': '{}',
    'opencode.jsonc': sample,
    'opencode-tui.jsonc': '{"theme": "system"}',
    'zshrc.sh': '# Example shell configuration\nexport EDITOR=vim\n',
}.items():
    (fixtures / name).write_text(data)
app_source = sources / 'KonfigEditorApp.swift'
app_source.write_text(replace_exact(app_source.read_text(),
    '@StateObject private var store = Store()',
    '''@StateObject private var store: Store = {
        let directory = URL(fileURLWithPath: ''' + json.dumps(str(fixtures)) + ''')
        let names = ["claude-settings.json", "claude-local-settings.json", "opencode.jsonc", "opencode-tui.jsonc", "zshrc.sh"]
        let files = zip(ConfigFile.known, names).map { file, name in
            var copy = file
            copy.rawPath = directory.appendingPathComponent(name).path
            return copy
        }
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: "ai.robin.konfigeditor.screenshot")
        let store = Store(initialFiles: files, defaults: defaults, newFileDirectory: directory)
        store.selectFromSidebar("opencode")
        store.fontSize = 16
        store.statusMessage = "Example configuration"
        return store
    }()'''))
config = sources / 'ConfigFile.swift'
config_text = config.read_text()
pretty_start = config_text.index('    var prettyPath: String {')
pretty_end = config_text.index('    // Hinweis:', pretty_start)
config.write_text(config_text[:pretty_start] +
    '    var prettyPath: String { "~/Examples/" + url.lastPathComponent }\n\n' + config_text[pretty_end:])
window = sources / 'WindowAccessor.swift'
window.write_text(replace_exact(replace_exact(window.read_text(),
    'let width = visible.width * 0.8', 'let width: CGFloat = 1200'),
    'let height = visible.height * 0.8', 'let height: CGFloat = 760'))
subprocess.run(['swift', 'build', '--package-path', str(work), '-c', 'release'], check=True)
bin_dir = Path(subprocess.check_output([
    'swift', 'build', '--package-path', str(work), '-c', 'release', '--show-bin-path'
], text=True).strip())
app = work / 'DotShelf-Demo.app'
(app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
(app / 'Contents/Resources').mkdir(parents=True, exist_ok=True)
shutil.copy2(bin_dir / 'KonfigEditor', app / 'Contents/MacOS/KonfigEditor')
shutil.copytree(bin_dir / 'DotShelf_KonfigEditor.bundle',
                app / 'Contents/Resources/DotShelf_KonfigEditor.bundle', dirs_exist_ok=True)
with (app / 'Contents/Info.plist').open('wb') as target:
    plistlib.dump({
        'CFBundleName': 'DotShelf',
        'CFBundleDisplayName': 'DotShelf',
        'CFBundleIdentifier': 'ai.robin.konfigeditor.screenshot',
        'CFBundleExecutable': 'KonfigEditor',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'CFBundleShortVersionString': '0.1.0',
        'CFBundleDevelopmentRegion': 'en',
        'CFBundleLocalizations': ['en'],
        'LSMinimumSystemVersion': '14.0',
        'NSPrincipalClass': 'NSApplication',
        'NSHighResolutionCapable': True,
    }, target)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
print(app)
