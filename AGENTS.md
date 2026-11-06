# Biscuit project guide

The agreed product scope is [the plan](project-docs/product/plan.md). XcodeGen project and scheme `Pet`, simulator owner `pet`.

## Stack and identity
- Swift 6, SwiftUI, iOS 17+.
- Core Data private and shared stores using `NSPersistentCloudKitContainer`.
- App `com.jackwallner.pet`, App Group `group.com.jackwallner.pet`, iCloud `iCloud.com.jackwallner.pet`.
- RevenueCat entitlement `pro`, offering `default`. Monthly and yearly subscriptions, each with a 7-day trial.
- `AppConfig` is the source of the display name. `scripts/display-name.py` generates the Info.plist display name during builds.

## Architecture
- `Shared/Models/`: Codable domain values, append-only correction reducer, Core Data schema.
- `Shared/Services/EventStore.swift`: sole write boundary, household policy and imported history.
- `ScheduleEngine.swift`, `Reminders.swift`: entered schedules, reminder ownership and notification plans.
- `SharingService.swift`, `ShareInvite.swift`: one household root shared by iCloud link and QR.
- `StoreService.swift`, `Measurements.swift`, `ConversionDiagnostics.swift`: purchases and counts/date attributes.
- `Pet/Views/`: Now, History, Care, Settings and their native sheets.

## Rules
- Events are immutable. Undo, corrections and deletions append events naming their target.
- Independent taps remain separate attributed entries.
- An upload does not prove the receiver is current. Now shows stale state and the last successful import time.
- Medication notifications open Now and have no completion action. Each medication has one reminder phone.
- Use the actual entitlement expiry for `householdActiveUntil`. Preserve the previous date on fetch failure.
- Keep free history and export accessible after lapse. Joiners become read-only after 14 days.
- Simulator code returns before RevenueCat configuration, so the production key never runs on a simulator.
- Scope exclusions in the plan apply to every change.

## Target users (check every change against them)
- **Two people sharing one pet**: each needs to see at a glance whether the dog already ate or got meds, and who did it. Often older, often on larger text.
- **The one managing a daily medication**: wants the reminder on one phone and an honest last-dose record, never a guess.
- **A sitter for a week**: gets the sitter sheet and shouldn't need the app.

## Tester feedback loop
Settings has "Suggest a change" in TestFlight builds only (`Distribution.isTestFlight`). It posts to the `tester-feedback` function, which lives in `~/deepcuts/supabase` in the Sports project (its `APPS` list must include `pet`). The ops poller sees it within a minute and starts an Opus session on the iMac in this repo. That session implements it with no approval step (never `needs_jack`), tests with `gh-sim all`, commits, pushes, runs `./scripts/testflight.sh`, and reports with `python3 scripts/feedback.py status <id> shipped --build N --reply "..."`, which the tester sees under Settings, Suggestions. App Store builds keep the mail link and can never reach the endpoint.
- Debug builds never touch the network, because a real send starts a build session. `-SuggestionSamples` shows sample rows.
- `Config/Secrets.xcconfig` is gitignored and holds the URL and app key (values in `~/.tester_feedback`). It must exist in every checkout that ships, including the iMac's: without it the build still succeeds and silently can't send.
- A suggestion may not breach the plan's scope exclusions or the medication rules above. Ship the closest version that keeps them and say so in the reply.

## Deep notes
| File | Covers | Read when |
|---|---|---|
| `.claude/rules/verification.md` | Debug routes, screenshots, tests and remaining Gate 1 work | Testing or preparing release |

Shared build, simulator, signing and release conventions are in the global instructions and `ios-dev` skill.
