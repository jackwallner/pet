import BackgroundTasks
import Foundation

/// The owner's subscription renews without the app opening, but joiners only see the new date once the
/// owner's phone writes it to the shared log. A periodic background refresh writes it, so a partner who
/// does all the logging is never cut to read-only by an owner who rarely opens the app. The same run
/// replans reminders, which keeps the 30-day horizon moving on a phone left unopened.
@MainActor
enum BackgroundRefresh {
    static let identifier = "com.jackwallner.pet.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            nonisolated(unsafe) let task = task
            MainActor.assumeIsolated { run(task) }
        }
    }

    static func schedule() {
        guard !LaunchOptions.contains("-UITesting") else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func run(_ task: BGTask) {
        schedule()
        nonisolated(unsafe) var finished = false
        // A stalled purchase fetch ignores cancellation, so expiry completes the task itself, exactly once.
        let complete = { @MainActor (success: Bool) in
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
        }
        let work = Task { @MainActor in
            // After a reboot the files may have reopened local-only; sync must be on before the expiry is written,
            // or the date never reaches the joiner this refresh exists for.
            EventStore.shared.activate()
            await StoreService.shared.start()
            await StoreService.shared.refresh()
            EventStore.shared.reload()
            // Finishing before the replacement is done could leave old requests unpruned or new ones missing.
            // A sync landing meanwhile starts a newer one, so wait until the latest has finished.
            while let current = Reminders.replacing {
                await current.value
                if Reminders.replacing == current { break }
            }
            complete(!Task.isCancelled)
        }
        // Not main-actor isolated: iOS may call expiry from any thread.
        task.expirationHandler = { @Sendable in
            work.cancel()
            Task { @MainActor in complete(false) }
        }
    }
}
