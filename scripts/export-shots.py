#!/usr/bin/env python3
"""Copy named XCTest screenshot attachments into the requested proof folder."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

result = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
export = result.parent / (result.stem + '-attachments')
subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(export)], check=True, capture_output=True)
output.mkdir(parents=True, exist_ok=True)
count = 0
for test in json.loads((export / 'manifest.json').read_text()):
    for attachment in test.get('attachments', []):
        name = attachment['suggestedHumanReadableName']
        if name.endswith('.png') and not name.startswith('Screenshot'):
            source = export / attachment['exportedFileName']
            target = output / name
            shutil.copyfile(source, target)
            count += 1
print(f'Exported {count} screenshots to {output}')
