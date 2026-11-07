---
paths:
  - "Pet/**"
  - "Shared/**"
  - "PetTests/**"
  - "PetUITests/**"
  - "scripts/**"
  - "project.yml"
---

# Verification

On the Air, lease a simulator with `agent-sim checkout pet`. On the iMac there is no Xcode, so use `gh-sim all`.
On GitHub's Macs two tests skip: the StoreKit purchase test stalls and notification banners never show. The notification test passes on a local simulator, so run it there after touching `NotificationRouter`. The purchase test stalled and skipped on some local simulators too, so read its result: a skip proves nothing about purchases.

Debug flags: `-SeedDemo`, `-DemoPro`, `-Onboarding`, `-OnboardingTrial`, `-EmptyLog`,
`-UITesting`, `-SimPartner`, `-ReminderProbe`, `-NoCloudKit`, `-Appearance light|dark`, `-LargeText`, `-SmallPhone`,
`-ScreenshotRoute <route>`, `-PaywallSnapshot monthly|yearly`, `-SuggestionSamples`, `-DemoPhoto` (with `-SeedDemo`: a drawn pet photo and filled details).
Debug builds count as TestFlight, so Settings shows Suggestions: never use a debug Settings shot as an App Store screenshot.
`-UITesting` uses a new in-memory log; normal local launches persist the log.

Routes: now, history, care, settings, pets, pet, medications, medication, dose,
due, household, join, invite, sitter, correction, paywall.

The UI test scheme activates `Pet.storekit`. Paywall verification must show
actual StoreKit products, prices, trial, disclosure and footer. Simulator
RevenueCat configuration is prohibited.

`SimPartnerRelay` saves a second caregiver's immutable events on a background
context with an import author, then the normal persistent-history merge reads
them. It proves app import behavior, not Apple's transport or latency.

The Gate 1 record lives in `project-docs/verification/`. Production transport,
real accounts, long soak, invitation acceptance, revocation and reinstall,
sandbox purchase and RevenueCat customer attributes still require external setup.
