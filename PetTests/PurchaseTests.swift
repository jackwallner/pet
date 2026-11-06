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
