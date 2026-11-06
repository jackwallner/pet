import Combine
import Foundation
import StoreKit
@preconcurrency import RevenueCat

struct PurchasePlan: Identifiable {
    let id: String
    let title: String
    let price: String
    let period: String
    let eligibleForTrial: Bool
    var billing: String { "\(price) per \(period)" }
}

@MainActor
final class StoreService: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = StoreService()
    @Published private(set) var plans: [PurchasePlan] = []
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var activeUntil: Date?
    @Published private(set) var usingStoreKitTesting = false
    private var packages: [String: Package] = [:]
    private var products: [String: StoreKit.Product] = [:]
    private var updates: Task<Void, Never>?
    private var started = false
    var didUpdateExpiry: ((Date?) -> Void)?
    var isPro: Bool { activeUntil.map { $0 > .now } ?? false }
    var isConfigured: Bool { Purchases.isConfigured }

    func start() async {
        guard !started else { return }
        started = true
        Measurements.didChange = { [weak self] in self?.syncAttributes() }
        #if targetEnvironment(simulator)
        // Simulator purchases use Apple's local StoreKit catalog exclusively.
        await loadProducts()
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self, case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self.refresh()
            }
        }
        return
        #else
        guard AppConfig.productionRevenueCatKey.hasPrefix("appl_") else {
            error = "Purchases are being prepared. Your free log is ready."
            return
        }
        Purchases.configure(withAPIKey: AppConfig.productionRevenueCatKey)
        Purchases.shared.delegate = self
        syncAttributes()
        await refresh()
        await loadProducts()
        #endif
    }

    func loadProducts() async {
        busy = true
        defer { busy = false }
        do {
            #if targetEnvironment(simulator)
            let fetched = try await StoreKit.Product.products(for: [AppConfig.yearly, AppConfig.monthly])
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            usingStoreKitTesting = !fetched.isEmpty
            var loaded: [PurchasePlan] = []
            for id in [AppConfig.yearly, AppConfig.monthly] {
                guard let product = products[id] else { continue }
                let eligible = await product.subscription?.isEligibleForIntroOffer ?? false
                loaded.append(PurchasePlan(id: id, title: id == AppConfig.yearly ? "Yearly" : "Monthly", price: product.displayPrice,
                                           period: id == AppConfig.yearly ? "year" : "month", eligibleForTrial: eligible))
            }
            plans = loaded
            #else
            guard isConfigured else { return }
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.offering(identifier: AppConfig.offering)
            // Two packages may name one product; a duplicate key must not crash the launch.
            packages = Dictionary((offering?.availablePackages ?? []).map { ($0.storeProduct.productIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: Array(packages.keys))
            plans = [AppConfig.yearly, AppConfig.monthly].compactMap { id in
                guard let package = packages[id] else { return nil }
                return PurchasePlan(id: id, title: id == AppConfig.yearly ? "Yearly" : "Monthly", price: package.storeProduct.localizedPriceString,
                                    period: id == AppConfig.yearly ? "year" : "month", eligibleForTrial: eligibility[id]?.status == .eligible)
            }
            #endif
            error = plans.isEmpty ? "Plans are unavailable. Please try again." : nil
        } catch { self.error = "Plans could not be loaded. Please try again." }
    }

    func pitch(_ surface: String) {
        ConversionDiagnostics.recordPitchView(impressionID: "pet_\(surface)")
        syncAttributes()
        guard isConfigured else { return }
        Purchases.shared.trackCustomPaywallImpression(CustomPaywallImpressionParams(paywallId: "pet_\(surface)"))
    }
    func syncAttributes() {
        guard isConfigured else { return }
        Purchases.shared.attribution.setAttributes(Measurements.attributes())
    }

    func purchase(_ plan: PurchasePlan, source: String) async -> Bool {
        busy = true
        error = nil
        defer { busy = false }
        do {
            #if targetEnvironment(simulator)
            guard let product = products[plan.id] else { error = "Open this app with StoreKit Testing to purchase."; return false }
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { error = "The purchase could not be verified."; return false }
                guard transaction.revocationDate == nil else { return false }
                activeUntil = transaction.expirationDate
                didUpdateExpiry?(activeUntil)
                await transaction.finish()
            case .pending: error = "Purchase awaiting approval."; return false
            case .userCancelled: return false
            @unknown default: return false
            }
            #else
            guard isConfigured, let package = packages[plan.id] else { error = "Plans are unavailable. Please try again."; return false }
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return false }
            apply(result.customerInfo)
            #endif
            guard isPro else { error = "Your purchase is still being confirmed."; return false }
            ConversionDiagnostics.recordConversion(plan: plan.id, startedTrial: plan.eligibleForTrial, offeringID: AppConfig.offering)
            Measurements.trialSource(source)
            syncAttributes()
            return true
        } catch { self.error = "The purchase could not be completed. Please try again."; return false }
    }

    func restore() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            #if targetEnvironment(simulator)
            try await AppStore.sync()
            await refresh()
            #else
            guard isConfigured else { error = "Restore is unavailable. Please try again later."; return }
            apply(try await Purchases.shared.restorePurchases())
            #endif
            if !isPro { error = "An active Household subscription was not found." }
        } catch { self.error = "Restore could not be completed. Please try again." }
    }

    func refresh() async {
        #if targetEnvironment(simulator)
        var expiry: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, [AppConfig.monthly, AppConfig.yearly].contains(transaction.productID),
                  transaction.revocationDate == nil, let until = transaction.expirationDate else { continue }
            expiry = max(expiry ?? .distantPast, until)
        }
        activeUntil = expiry
        var latestExpiry = expiry
        if latestExpiry == nil {
            for id in [AppConfig.monthly, AppConfig.yearly] {
                if case .verified(let transaction) = await StoreKit.Transaction.latest(for: id), let date = transaction.expirationDate {
                    let effective = transaction.revocationDate ?? date
                    latestExpiry = max(latestExpiry ?? .distantPast, effective)
                }
            }
        }
        didUpdateExpiry?(latestExpiry)
        #else
        guard isConfigured else { return }
        do { apply(try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)) }
        catch { self.error = "Purchase status could not be refreshed." }
        #endif
    }

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements.all[AppConfig.entitlement]
        let expiry = entitlement?.expirationDate
        activeUntil = entitlement?.isActive == true ? expiry : nil
        didUpdateExpiry?(expiry)
    }
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in self.apply(customerInfo) }
    }
}
