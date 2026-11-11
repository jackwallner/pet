# Biscuit: agreed plan (2026-11-06)

Evidence and competitor research: `project-docs/research/2026-11-06-fact-pack.md`.
Agreed through a six-seat council (Claude Opus, Sonnet, Haiku; GPT Sol, Terra, Luna; two providers) over three rounds.

## Call
Build a thin v1 now, keep it cheap, and gate every further hour and dollar on measured results. This is a low-cost option. The gap in the original pitch is real, and its commercial value is unproven: 90 of 199 pet apps seen in search shipped in the past 12 months with a median of 0 ratings, and the best indie owner log has 1,389 ratings after nine years.

## Who and what
Two people raising one dog, starting with a new puppy, because puppy is the only part of this demand that is findable. All five top indie logs lean on puppy in the title or subtitle. Medication and records terms sit at the Astro popularity floor. Medications are the retention hypothesis past the puppy stage, unproven. Cats are supported from day one and not marketed in v1.

One sentence: everyone caring for the dog sees what happened and what is next.

## Name and store
- Title `Biscuit: Critter Log` (tester feedback #12, was `Biscuit: Puppy & Dog Log`), home screen `Biscuit`. Rename if taken when the App Store Connect record is created.
- Xcode project/scheme `Pet`, slug and sim lease owner `pet`, bundle `com.jackwallner.pet`, App Group `group.com.jackwallner.pet`, iCloud `iCloud.com.jackwallner.pet`.
- Subtitle around pet diary and med tracking. Keyword field: pet log, puppy tracker, puppy schedule, dog medication tracker, pet health. Do not lead on pet tracker, dog tracker or cat tracker (GPS intent). Dog log and puppy tracker are bonus traffic, because DogLog holds them.

## V1 scope
In:
- Pet profile, including one photo and plain vet, microchip, insurance and notes fields (tester feedback #13). The photo syncs as a JPEG capped at 180 KB in a `petPhoto` record's existing `payload`, so it needs no CloudKit schema change. Each pet also keeps a list of potential sitters (name, phone with tap-to-call, note) inside the pet record (tester feedback #16).
- Four large buttons; one tap logs what, who and when. Dog: Potty, Meal, Walk, Meds. Cat, Rabbit: Meal, Litter, Meds, Play. Small pet, Bird, Other: Meal, Cleaning, Meds, Play. Fish, Reptile: Meal, Water, Cleaning, Meds. Those are defaults: Settings, Log buttons shows, hides and reorders them per pet from the eight activities, synced with the household (tester feedback #14).
- Now view: the last of each, who did it, and the last successful sync time.
- User-entered medications with given or skipped, actual time, and who.
- User-entered recurring due items with local reminders.
- Correction history, CloudKit household sharing by link and QR, basic export.
- One-page sitter sheet as a share-sheet PDF: a snapshot, stated plainly, for helpers on Android or without iCloud.

Out: weight, a dedicated emergency card, record photos, OCR, costs, breed data, preset vaccine or medical schedules, dosing, AI, widget, Watch, Android, lifetime plan.

Chassis: `~/baby` for log, share and sync; `~/elderhub` for medication schedule logic.

Copy promise: no account, honest limits shown before the first log, your data never locked. Reliable sync gets claimed only after Gate 1. Android households cannot share a live log in v1, and listing copy says so.

## Data rules
- The log is append-only, new to this app: remove the chassis edit and delete paths, so undo, edit and delete each write a new event, pointing at the old one where relevant.
- Two people logging the same thing show as two entries with both names. Nothing silently merges or overwrites.
- Pet and med settings use last-writer-wins and show an "edited by, time" line.
- A disconnected phone must visibly read as stale.

## Med reminders
Core Data imports are discretionary and cannot be forced, so a second phone can be behind.
- Each med has one reminder phone, the creator by default.
- A med reminder opens Now, which shows the last dose, who gave it, and the last sync time.
- Med notifications have no Mark done action. Non-med due items keep it.
- Copy never implies the app prevents a double dose.

## Paid
Free: one pet, solo, all logging, history, reminders, export.
Household: sharing, extra pets, sitter sheet. $2.99/month and $19.99/year, 7-day free trial on both. One purchase covers the household; joiners pay nothing and never see a paywall.
Placement: trial page in onboarding with a soft exit; again when a free user taps Invite, after they have seen the shared workflow.

This is a bet, and Gate 2 reads it. Baby Tracker gates reports and has no onboarding purchase screen, so its 1 trial in 101 installs does not prove or disprove paid sharing. Two council seats preferred free sharing.

Household entitlement: only the owner buys. The owner's device writes `householdActiveUntil` as a timestamp into the shared zone, and joiners compare it with the clock, so lapse needs no owner action. Participants could edit the field outside the app, so the gate only deters casual freeloading. That leak is accepted for v1. On lapse: no record removed or locked from view; banner on both phones; the owner keeps solo logging on the first pet; joiners become read-only 14 days after `householdActiveUntil` passes. On renewal or restore: writing resumes.
Fallback if Gate 1(f) cannot be proven: sharing becomes free and the sitter sheet is cut, with no new entitlement infrastructure.

## Economics (estimates; cumulative first-30-day receipts; renewals excluded)
| Case | Installs/week | $/install | 3 months | 6 months | 12 months |
|---|---|---|---|---|---|
| Low (Vehicle Log) | 5 | $0.16 | $10 | $21 | $42 |
| Base (Baby to Sober) | 20 | $0.35 | $91 | $182 | $364 |
| High (Total Calories) | 75 | $1.05 | $1,024 | $2,048 | $4,095 |

$1,000/month in new-cohort receipts needs about 660 installs/week at base. Search alone will not do that. Zero is plausible.

## TikTok
A topic page on life with a new dog for random scrollers. No app until it earns one. Competitor apps posting the same pill hook are flat at single digits to tens; non-app pet content reaches thousands to millions.
- Pillars: first-year puppy reality; two-person household humor; sitter and kennel prep.
- Hooks: "Your 9-week-old needs to pee after these 5 things" (facts sourced); "He has now eaten three breakfasts because you both fed him"; "What a boarding kennel asks for before a first stay"; "The sitter arrives in 20 minutes. Here is everything she needs"; "The dog has had her pill. Probably."
- Formats: stock-footage hook, list to save, POV humor, checklist. No identifiable people, no negation copy, no invented personal stories, no dosing advice.
- Cadence: 3/day, 42 posts, scheduled in TikTok Studio from a dedicated Chrome profile after Jack creates the account.
- Measure: verified views, saves and follows per 1,000 views, bio-link clicks with an App Store campaign token.
- Add the app after store release and either 1,000 followers or 3 posts over 5,000 views: bio link first, then one post in six.
- If median is under 150 after 21 posts, drop the lowest two formats and run the remaining 21 on the top two.
- Kill: median under 150 after 42 posts. Scale: 3 posts over 20,000 views. No paid creators without approval.
- Unknown: view-to-install rate. No evidence anywhere.

## Gates
**Gate 1, before submission.** Real phones, two iCloud accounts, TestFlight build on Production CloudKit. Production rejects every invitation until `cloudkit.share` is deployed.
a. Tests pass. Invite accepted by link and QR.
b. Foregrounded receiver sees 20 entries within 30 seconds at p90. A backgrounded phone is current within 30 seconds of opening.
c. 48-hour soak with airplane-mode and conflicting edits on both phones: every event appears on both after reconnect, zero lost, duplicates show as two attributed entries.
d. Disconnected phone reads as stale. Stale-phone med reminder case verified.
e. Share revoke, re-accept and reinstall recover.
f. Sandbox purchase unlocks sharing; joiner pays nothing; expiry gives the banner on both phones and joiner read-only after 14 days; restore recovers. Proves unlock, expiry and restore, not resistance to edits.
g. A scripted two-person journey shows every app-side Gate 2 counter on RevenueCat customers; verify installs separately in App Store Connect Units.
Any failure blocks submission. This proves this test case, not reliability at scale, and is not presented as more.

**Gate 2, day 60 after release.** Installs from App Store Connect Units, test devices excluded. Trials from RevenueCat.
- Continue if at least 100 non-test installs and at least 5% start a trial.
- Fold if under 50 installs or under 2% start a trial. Fleet log apps run 1 to 2%, so this has a real chance of folding.
- Otherwise one change, then one more 60-day read.
- Early stop at week 4: fold if weeks 3 and 4 average under 5 organic installs/week.
Judgment thresholds, not forecasts.
Directional only: 60% log day 1, 20% log day 7, 15% tap Invite, 60% of trial starters send an invite, 50% of invites accepted.

**Gate 3.** TikTok thresholds above.

**Fold policy.** No features or marketing. Critical sync, data-loss and compatibility fixes continue while it is distributed, with an orderly withdrawal option (export reminder first) if maintenance is not justified.

## Measurement
The fleet subscriber-attribute contract (`pitch_*`, `converted_surface` and the rest; see the `ios-dev` skill and `reference_paywall_funnel_attributes`), plus counts and dates only: `first_log_at`, `logged_day_7`, `invite_tapped_at`, `invite_sent_at`, `joined_share_at`, `trial_source`. Never pet names, med names or free text. No new vendor. Privacy label updated to match.

## Compliance
App Review 1.4.1: no diagnosis, treatment or dosing advice. A short disclaimer in settings and on the sitter sheet says the app is a record keeper and the vet directs care. Must not look vibe coded: no taglines, helper text, gradient cards, emoji headers or AI imagery.

## Top risks
1. Distribution, fatal if neither search nor TikTok produces installs.
2. The shared log showing stale or wrong state, a real-world harm.
3. Puppy churn, and sameness among clones.

## Who does what
- Sol: builds the app and tests.
- Claude: App Store Connect record, RevenueCat, Apple identifiers and CloudKit console work in Chrome, TikTok kit and scheduling.
- Jack: creates the TikTok account and signs in; second phone and iCloud account for Gate 1; OK for Production CloudKit deploy; submit word; any TestFlight testers beyond himself.
