#!/usr/bin/env python3
"""Validate the English string table; --write refreshes it from L10n calls."""
import argparse
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--write', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
keys = set()
for source in (root / 'Sources/KonfigEditor').glob('*.swift'):
    for literal in re.findall(r'L10n\.(?:text|format)\("((?:\\.|[^"\\])*)"', source.read_text()):
        keys.add(json.loads('"' + literal + '"'))
table = root / 'Sources/KonfigEditor/Resources/en.lproj/Localizable.strings'
expected = '/* English is DotShelf’s development language. */\n' + ''.join(
    f'{json.dumps(key, ensure_ascii=False)} = {json.dumps(key, ensure_ascii=False)};\n'
    for key in sorted(keys)
)
if args.write:
    table.write_text(expected)
elif table.read_text() != expected:
    raise SystemExit('English string table is stale. Run python3 scripts/check-localization.py --write.')
print(f'English localization: {len(keys)} strings OK')
