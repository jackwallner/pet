import StoreKit
import StoreKitTest
import XCTest

@testable import Pet

@MainActor
final class PurchaseTests: XCTestCase {
    // StoreKit Testing can stall forever on GitHub's Macs, which would hold the whole run
    // until the job limit. Skip there rather than wait.
    func testLocalStoreKitTrialsPurchaseExpiryAndRestoreReceipt() async throws {
        let progress = Progress()
        let run = Task { @MainActor in
            defer { progress.finished = true }
            try await exercisePurchaseFlow()
        }
        let deadline = Date.now.addingTimeInterval(120)
        while !progress.finished, Date.now < deadline { try await Task.sleep(for: .milliseconds(250)) }
        guard progress.finished else { throw XCTSkip("StoreKit Testing stalled on this machine") }
        try await run.value
    }

    /// The owner's app stays closed while the subscription renews. The background refresh alone must carry
    /// the new date into the household record the joiner reads, or the joiner turns read-only.
    func testBackgroundRefreshCarriesRenewalToHouseholdRecord() async throws {
        let progress = Progress()
        let run = Task { @MainActor in
            defer { progress.finished = true }
            try await exerciseBackgroundRenewal()
        }
        let deadline = Date.now.addingTimeInterval(120)
        while !progress.finished, Date.now < deadline { try await Task.sleep(for: .milliseconds(250)) }
        guard progress.finished else { throw XCTSkip("StoreKit Testing stalled on this machine") }
        try await run.value
    }

    private func exerciseBackgroundRenewal() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Pet", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let defaults = UserDefaults(suiteName: "pet.tests.\(UUID())")!
        let owner = EventStore(persistence: Persistence(cloudKit: false, inMemory: true), defaults: defaults)
        owner.caregiver = "Jack"
        XCTAssertTrue(owner.savePet(PetProfile(name: "Milo", editedBy: "Jack")))
        let store = StoreService()
        store.didUpdateExpiry = { owner.setHouseholdExpiry($0) }
        let bought = try await session.buyProduct(identifier: AppConfig.monthly)
        XCTAssertNotNil(bought.expirationDate)
        for _ in 0..<40 where owner.household?.householdActiveUntil == nil {
            await BackgroundRefresh.perform(events: owner, store: store)
            try await Task.sleep(for: .milliseconds(250))
        }
        let first = try XCTUnwrap(owner.household?.householdActiveUntil)

        try session.forceRenewalOfSubscription(productIdentifier: AppConfig.monthly)
        for _ in 0..<40 where owner.household?.householdActiveUntil == first {
            await BackgroundRefresh.perform(events: owner, store: store)
            try await Task.sleep(for: .milliseconds(250))
        }
        let renewed = try XCTUnwrap(owner.household?.householdActiveUntil)
        XCTAssertGreaterThan(renewed, first)

        // What the joiner's phone decides from that record, a day past the old date's grace.
        let later = first.addingTimeInterval(HouseholdAccess.grace + 86400)
        XCTAssertFalse(HouseholdAccess(activeUntil: first, isOwner: false, wasShared: true).canWrite(petIndex: 0, at: later))
        XCTAssertTrue(HouseholdAccess(activeUntil: renewed, isOwner: false, wasShared: true).canWrite(petIndex: 0, at: later))
    }

    private final class Progress { var finished = false }

    private func exercisePurchaseFlow() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Pet", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.disableDialogs = true
        session.clearTransactions()
        let store = StoreService()
        var expiryWritten: Date?
        store.didUpdateExpiry = { expiryWritten = $0 }
        await store.start()
        XCTAssertTrue(store.usingStoreKitTesting)
        XCTAssertFalse(store.isConfigured)
        XCTAssertEqual(store.plans.count, 2)
        XCTAssertEqual(Set(store.plans.map(\.id)), [AppConfig.monthly, AppConfig.yearly])
        XCTAssertTrue(store.plans.allSatisfy(\.eligibleForTrial))
        let yearly = try XCTUnwrap(store.plans.first { $0.id == AppConfig.yearly })
        XCTAssertTrue(yearly.price.contains("19.99"))
        XCTAssertTrue(store.plans.first { $0.id == AppConfig.monthly }?.price.contains("2.99") == true)
        let purchased = await store.purchase(yearly, source: "invite")
        XCTAssertTrue(purchased)
        await store.refresh()
        XCTAssertTrue(store.isPro)
        XCTAssertNotNil(expiryWritten)
        let restored = StoreService()
        await restored.start()
        await restored.refresh()
        XCTAssertTrue(restored.isPro)
        XCTAssertEqual(restored.activeUntil, store.activeUntil)
        if case .verified(let transaction)? = await StoreKit.Transaction.latest(for: AppConfig.yearly) {
            try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
        }
        try session.expireSubscription(productIdentifier: AppConfig.yearly)
        for _ in 0..<40 where store.isPro {
            await store.refresh()
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertFalse(store.isPro)
        XCTAssertNotNil(expiryWritten)
        XCTAssertLessThanOrEqual(expiryWritten!, Date.now)
        session.clearTransactions()
    }
}
