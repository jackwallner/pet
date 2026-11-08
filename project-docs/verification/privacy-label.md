# App Store privacy label

Published in App Store Connect (checked 2026-11-08): Product Interaction (analytics), Purchase History (app functionality, analytics) and User ID (app functionality), none linked to identity and none used for tracking. Pet photos and entered records stay on the device and in the user's own iCloud, so they are not collected data.

The draft it was built from:

- Purchases: purchase history, linked to the RevenueCat app user identifier, app functionality and analytics.
- Identifiers: RevenueCat app user identifier and SDK device identifiers, app functionality and analytics.
- Usage data: product interaction (counts and dates for opens, paywalls, conversion, logs and invitations), analytics.
- Diagnostics: disclose SDK diagnostics if enabled by the final RevenueCat configuration.
- Tracking: the app does not request tracking authorization or use an advertising identifier.
- Pet records, pet photos and entered text: local files and optional user-controlled CloudKit sharing. These are outside custom analytics attributes.
- Notifications: local notification permission, outside analytics attributes.

Custom measurement values contain only counts, dates and fixed product/surface identifiers.
Verify the final SDK collection and
customer-attribute delivery during Gate 1(g) after console setup.
