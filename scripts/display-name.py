import os
import plistlib
import re
from pathlib import Path

root = Path(os.environ['SRCROOT'])
name = re.search(r'static let displayName = "([^"]+)"', (root / 'Shared/Utilities/AppConfig.swift').read_text()).group(1)
path = root / 'Pet/Info.plist'
data = plistlib.loads(path.read_bytes())
data['CFBundleDisplayName'] = name
path.write_bytes(plistlib.dumps(data))
