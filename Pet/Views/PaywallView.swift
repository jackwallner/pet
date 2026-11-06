import StoreKit
import SwiftUI

struct PaywallView: View {
    let source: String
    let onboarding: Bool
    var finished: (() -> Void)? = nil
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = AppConfig.yearly
    private var plan: PurchasePlan? { store.plans.first { $0.id == selected } ?? store.plans.first }
    private var cta: String { plan?.eligibleForTrial == true ? "Start 7-day free trial" : "Subscribe" }
    private var disclosure: String {
        guard let plan else { return "Household renews monthly or yearly. Pricing appears when plans load. Cancel in App Store Settings." }
        return plan.eligibleForTrial ? "7 days free, then \(plan.billing). Renews automatically. Cancel in App Store Settings." : "\(plan.billing). Renews automatically. Cancel in App Store Settings."
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if onboarding { Text("Household").font(.largeTitle.bold()) }
                SharedWorkflowPreview()
                VStack(alignment: .leading, spacing: 12) {
                    Label("One subscription for your household", systemImage: "person.2")
                    Label("Extra pets", systemImage: "pawprint")
                    Label("Sitter sheet PDF", systemImage: "doc")
                }.font(.body)
                if store.plans.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.busy ? "Loading plans" : "Plans unavailable").font(.headline)
                        if !store.busy { Button("Try again") { Task { await store.loadProducts() } } }
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.plans) { option in
                            Button { selected = option.id } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: selected == option.id ? "largecircle.fill.circle" : "circle").accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(option.title).font(.headline)
                                        Text(option.eligibleForTrial ? "7 days free, then \(option.billing)" : option.billing).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.primary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected == option.id ? Theme.accent : Color.secondary.opacity(0.25), lineWidth: selected == option.id ? 2 : 1))
                            }.buttonStyle(.plain).accessibilityIdentifier("plan.\(option.title.lowercased())").accessibilityAddTraits(selected == option.id ? .isSelected : [])
                        }
                    }.accessibilityValue(store.usingStoreKitTesting ? "StoreKit Testing products" : "Store products")
                }
                if let error = store.error { Text(error).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle(onboarding ? "" : "Household").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if onboarding {
                OnboardingFooter(title: cta, disclosure: disclosure, trial: true, disabled: plan == nil || store.busy,
                                 action: buy, exit: finish)
            } else {
                VStack(spacing: 12) {
                    Text(disclosure).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: store.busy ? "Please wait" : cta, disabled: plan == nil || store.busy, action: buy).accessibilityIdentifier("paywall.buy")
                    LegalLinks()
                }.padding(20).background(Theme.background)
            }
        }
        .toolbar { if !onboarding { ToolbarItem(placement: .cancellationAction) { DismissButton() } } }
        .onAppear {
            if let selection = LaunchOptions.value("-PaywallSnapshot") { selected = selection == "monthly" ? AppConfig.monthly : AppConfig.yearly }
            store.error = nil
            if events.isOwner { store.pitch(source) }
        }
    }
    private func buy() {
        guard let plan, events.isOwner else { return }
        Task { if await store.purchase(plan, source: source) { finish() } }
    }
    private func finish() { if let finished { finished() } else { dismiss() } }
}

struct SharedWorkflowPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shared log").font(.headline)
            HStack { Image(systemName: "fork.knife"); Text("Meal"); Spacer(); Text("Sam · 8:15 AM").foregroundStyle(.secondary) }
            Divider()
            HStack { Image(systemName: "figure.walk"); Text("Walk"); Spacer(); Text("Riley · 8:30 AM").foregroundStyle(.secondary) }
        }.font(.subheadline).padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Shared log preview. Meal by Sam at 8:15 AM. Walk by Riley at 8:30 AM.")
    }
}

struct LegalLinks: View {
    @EnvironmentObject private var store: StoreService
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { links }
            VStack(spacing: 12) { links }
        }.font(.footnote).frame(maxWidth: .infinity)
    }
    @ViewBuilder private var links: some View {
        Button("Restore") { Task { await store.restore() } }.disabled(store.busy).accessibilityIdentifier("purchase.restore")
        Link("Terms", destination: AppConfig.termsURL)
        Link("Privacy", destination: AppConfig.privacyURL)
    }
}

struct OnboardingFooter: View {
    let title: String
    var disclosure: String? = nil
    var trial = false
    var disabled = false
    let action: () -> Void
    var exit: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 12) {
            Text(disclosure ?? " ").font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 130 : 54, alignment: .bottomLeading)
                .fixedSize(horizontal: false, vertical: true).accessibilityHidden(disclosure == nil)
            PrimaryButton(title: title, disabled: disabled, action: action).accessibilityIdentifier("onboarding.primary")
            VStack(spacing: 12) {
                if trial {
                    Button("Get Started", action: { exit?() }).font(.subheadline).accessibilityIdentifier("onboarding.free")
                    LegalLinks()
                } else { Color.clear.accessibilityHidden(true) }
            }.frame(height: typeSize.isAccessibilitySize ? 140 : 70)
        }.padding(.horizontal, 20).padding(.bottom, 8).background(Theme.background)
    }
}
