#!/usr/bin/env python3
"""Add or remove the dictation widget in the Omarchy bar layout (~/.config/omarchy/shell.json)."""
import json, shutil, sys, time
from pathlib import Path

WIDGET = 'handy.dictation'
action = sys.argv[1] if len(sys.argv) > 1 else 'add'
section = sys.argv[2] if len(sys.argv) > 2 else 'center'
path = Path.home() / '.config/omarchy/shell.json'
manual = (f'Add {{"id": "{WIDGET}"}} to a bar section yourself: open the Omarchy bar settings, '
          'or edit bar.layout in ~/.config/omarchy/shell.json.')
if not path.exists():
    print('No ~/.config/omarchy/shell.json found. ' + manual); sys.exit(0)
data = json.loads(path.read_text())
layout = data.get('bar', {}).get('layout')
if not isinstance(layout, dict):
    print('Your bar uses the stock layout, which this script will not rewrite. ' + manual); sys.exit(0)
present = any(isinstance(e, dict) and e.get('id') == WIDGET for sec in layout.values() if isinstance(sec, list) for e in sec)
if action == 'add':
    if present:
        print('Dictation widget is already in the bar.'); sys.exit(0)
    layout.setdefault(section, []).append({'id': WIDGET})
elif action == 'remove':
    if not present:
        sys.exit(0)
    for name, sec in layout.items():
        if isinstance(sec, list):
            layout[name] = [e for e in sec if not (isinstance(e, dict) and e.get('id') == WIDGET)]
else:
    sys.exit('usage: bar-layout.py add|remove [left|center|right]')
shutil.copy2(path, path.with_name('shell.json.bak-handy-omarchy-' + time.strftime('%Y%m%d%H%M%S')))
tmp = path.with_name('shell.json.tmp')
tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
tmp.replace(path)
print(f'Dictation widget {"added to the " + section + " section" if action == "add" else "removed from the bar"}.')
