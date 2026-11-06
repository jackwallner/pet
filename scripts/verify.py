#!/usr/bin/env python3
"""Check the fixed v1 contracts without network or credentials."""
import json
import plistlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for folder in ['Pet', 'Shared', 'PetTests', 'PetUITests', 'scripts', 'fastlane', 'docs', '.claude']:
    for path in (root / folder).rglob('*'):
        if path == Path(__file__).resolve():
            continue
        if path.is_file() and path.suffix in {'.swift', '.py', '.sh', '.md', '.txt', '.html', '.yml'}:
            text = path.read_text()
            assert '\u2014' not in text and '\u2013' not in text, path
            assert 'com.jackwallner.baby' not in text, path
            assert 'iCloud.com.jackwallner.baby' not in text, path
            assert path.name == 'AppConfig.swift' or not re.search(r'appl_[A-Za-z0-9]+', text), path
config = (root / 'Shared/Utilities/AppConfig.swift').read_text()
assert 'static let productionRevenueCatKey = "appl_' in config
assert 'static let entitlement = "pro"' in config
assert 'static let offering = "default"' in config
catalog = json.loads((root / 'Pet.storekit').read_text())
assert catalog['products'] == []
assert all('description' in localization for group in catalog['subscriptionGroups'] for localization in group['localizations'])
products = catalog['subscriptionGroups'][0]['subscriptions']
assert {p['productID']: p['displayPrice'] for p in products} == {
    'com.jackwallner.pet.monthly': '2.99', 'com.jackwallner.pet.yearly': '19.99'}
assert all(p['introductoryOffer']['subscriptionPeriod'] == 'P1W' and p['introductoryOffer']['paymentMode'] == 'free' for p in products)
plist = plistlib.loads((root / 'Pet/Info.plist').read_bytes())
assert 'UILaunchScreen' in plist and plist['CKSharingSupported']
assert not (root / 'CLAUDE.md').exists()
limits = {'name': 30, 'subtitle': 30, 'keywords': 100, 'promotional_text': 170}
for field, limit in limits.items():
    value = (root / f'fastlane/metadata/en-US/{field}.txt').read_text().strip()
    assert len(value) <= limit, (field, len(value), limit)
print('PASS: identity, production key format, products, both trials, metadata lengths, plist and source copy')
