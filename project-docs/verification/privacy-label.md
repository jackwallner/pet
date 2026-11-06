# Draft App Store privacy label

Verify this against the configured RevenueCat SDK and Apple's current form before submission.

- Purchases: purchase history, linked to the RevenueCat app user identifier, app functionality and analytics.
- Identifiers: RevenueCat app user identifier and SDK device identifiers, app functionality and analytics.
- Usage data: product interaction (counts and dates for opens, paywalls, conversion, logs and invitations), analytics.
- Diagnostics: disclose SDK diagnostics if enabled by the final RevenueCat configuration.
- Tracking: the app does not request tracking authorization or use an advertising identifier.
- Pet records and entered text: local files and optional user-controlled CloudKit sharing. These are outside custom analytics attributes.
- Notifications: local notification permission, outside analytics attributes.

Custom measurement values contain only counts, dates and fixed product/surface identifiers.
The production RevenueCat key is empty. Verify the final SDK collection and
customer-attribute delivery during Gate 1(g) after console setup.
