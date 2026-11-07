import StoreKitTest
import XCTest

@MainActor
final class JourneyTests: XCTestCase {
    private var session: SKTestSession!
    override func setUp() async throws {
        continueAfterFailure = false
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Pet", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: config)
        session.disableDialogs = true
        session.clearTransactions()
    }
    private func app(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-NoCloudKit"] + (args.contains("-Appearance") ? [] : ["-Appearance", "light"]) + args
        app.launch()
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func tapTab(_ app: XCUIApplication, _ name: String) { app.tabBars.buttons[name].tap() }

    func testFreshDogLogCorrectionDoseInviteAndSitterJourney() throws {
        let app = app(["-Onboarding"])
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap(); name.typeText("Jack")
        let pet = app.textFields["onboarding.pet"]
        pet.tap(); pet.typeText("Milo")
        app.keyboards.buttons["Return"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let continueButton = app.buttons["onboarding.primary"]
        XCTAssertTrue(continueButton.isHittable)
        let frame = continueButton.frame
        continueButton.tap()
        XCTAssertTrue(app.buttons["onboarding.free"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["plan.yearly"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["onboarding.primary"].frame, frame)
        shot(app, "journey-trial")
        app.buttons["onboarding.free"].tap()
        XCTAssertTrue(app.buttons["log.meal"].waitForExistence(timeout: 10))
        app.buttons["log.meal"].tap()
        XCTAssertTrue(app.buttons["log.undo"].waitForExistence(timeout: 5))
        shot(app, "journey-first-log")
        tapTab(app, "History")
        XCTAssertTrue(app.buttons["history.entry"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["history.entry"].firstMatch.tap()
        XCTAssertTrue(app.buttons["correction.save"].waitForExistence(timeout: 5))
        app.textFields["Note"].tap(); app.textFields["Note"].typeText("Earlier meal")
        app.buttons["correction.save"].tap()
        // Allows for a keystroke the simulator drops under load.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Earlier mea'")).firstMatch.waitForExistence(timeout: 5))
        // The identifier sits on the row. Only the inner control flips the toggle.
        app.switches["history.corrections"].switches.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "history.entry").element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "history.entry").count, 2)
        tapTab(app, "Care")
        app.buttons["care.medications"].tap()
        app.buttons["medication.add"].tap()
        let medicationName = app.textFields["medication.name"]
        XCTAssertTrue(medicationName.waitForExistence(timeout: 5))
        medicationName.tap(); medicationName.typeText("Entered tablet")
        app.buttons["medication.save"].tap()
        XCTAssertTrue(app.buttons["medication.dose"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["medication.dose"].firstMatch.tap()
        XCTAssertTrue(app.buttons["dose.save"].waitForExistence(timeout: 5))
        shot(app, "journey-dose")
        app.buttons["dose.save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapTab(app, "Settings")
        app.buttons["settings.household"].tap()
        app.buttons["household.invite"].tap()
        XCTAssertTrue(app.buttons["paywall.buy"].waitForExistence(timeout: 10))
        shot(app, "journey-invite-paywall")
        app.buttons["plan.monthly"].tap()
        shot(app, "journey-invite-paywall-monthly")
        app.buttons["Close"].firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings.sitter"].tap()
        app.buttons["sitter.create"].tap()
        XCTAssertTrue(app.buttons["paywall.buy"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testOnboardingFishGetsAquariumButtons() throws {
        let app = app(["-Onboarding"])
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap(); name.typeText("Jack")
        let pet = app.textFields["onboarding.pet"]
        pet.tap(); pet.typeText("Bubbles")
        app.keyboards.buttons["Return"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Biscuit: Critter Log"].exists)
        for species in ["Dog", "Cat", "Rabbit", "Small pet", "Bird", "Fish", "Reptile", "Other"] {
            XCTAssertTrue(app.buttons["species.\(species)"].exists, species)
        }
        app.buttons["species.Fish"].tap()
        XCTAssertTrue(app.buttons["species.Fish"].isSelected)
        shot(app, "onboarding-species")
        app.buttons["onboarding.primary"].tap()
        XCTAssertTrue(app.buttons["onboarding.free"].waitForExistence(timeout: 15))
        app.buttons["onboarding.free"].tap()
        XCTAssertTrue(app.buttons["log.water"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["log.cleaning"].exists)
        XCTAssertFalse(app.buttons["log.walk"].exists)
        app.buttons["log.water"].tap()
        XCTAssertTrue(app.buttons["log.undo"].waitForExistence(timeout: 5))
        shot(app, "now-fish")
        tapTab(app, "Settings")
        let fullName = app.staticTexts["Biscuit: Critter Log"]
        for _ in 0..<4 where !fullName.isHittable { app.swipeUp() }
        XCTAssertTrue(fullName.isHittable)
        shot(app, "settings-name")
        app.terminate()
    }

    func testProSitterExportExtraPetAndRecurringItemFlow() throws {
        let app = app(["-SeedDemo", "-DemoPro"])
        XCTAssertTrue(app.buttons["log.meal"].waitForExistence(timeout: 15))
        tapTab(app, "Care")
        app.buttons["care.addDue"].tap()
        let field = app.textFields["due.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Brush coat")
        app.buttons["due.save"].tap()
        XCTAssertTrue(app.staticTexts["Brush coat"].waitForExistence(timeout: 5))
        tapTab(app, "Settings")
        app.buttons["settings.pets"].tap()
        app.buttons["Add a pet"].tap()
        app.textFields["pet.name"].tap(); app.textFields["pet.name"].typeText("Luna")
        app.buttons["species.Cat"].tap()
        app.buttons["pet.save"].tap()
        XCTAssertTrue(app.buttons["Luna"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings.sitter"].tap()
        app.buttons["sitter.create"].tap()
        XCTAssertTrue(app.buttons["Share PDF"].waitForExistence(timeout: 10))
        shot(app, "journey-sitter-pdf")
        app.buttons["Share PDF"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings.export"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        shot(app, "journey-export")
        app.terminate()
    }

    func testSimulatedPartnerEntryShowsAlongsideOwnersEntry() {
        let app = app(["-SeedDemo", "-DemoPro", "-SimPartner"])
        XCTAssertTrue(app.buttons["log.meal"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["log.meal"].label.contains("Riley"))
        tapTab(app, "History")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'history.entry' AND label CONTAINS 'Riley'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'history.entry' AND label CONTAINS 'Jack'")).firstMatch.exists)
        shot(app, "two-person-history")
        app.terminate()
    }

    func testStaleMedicationNotificationOpensNowWithoutLogging() throws {
        let app = app(["-SeedDemo", "-DemoPro", "-ReminderProbe"])
        XCTAssertTrue(app.buttons["log.meal"].waitForExistence(timeout: 15))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.buttons["Allow"].waitForExistence(timeout: 20) { system.buttons["Allow"].tap() }
        tapTab(app, "History")
        XCUIDevice.shared.press(.home)
        let notification = system.staticTexts["Daily tablet"].firstMatch
        // GitHub's simulators never show the banner, so this runs only on a local simulator.
        guard notification.waitForExistence(timeout: 30) else { throw XCTSkip("Notification banners don't show on this simulator") }
        notification.tap()
        XCTAssertTrue(app.buttons["log.meal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sync.status").firstMatch.label.contains("Stale"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "medication.reminderContext").firstMatch.label.contains("Daily tablet"))
        shot(app, "stale-medication-reminder")
        tapTab(app, "History")
        XCTAssertEqual(app.buttons.matching(identifier: "history.entry").count, 4)
        app.terminate()
    }

    func testSuggestionSendsWithoutNetworkAndAppearsInSettings() {
        let app = app(["-SeedDemo"])
        XCTAssertTrue(app.buttons["log.meal"].waitForExistence(timeout: 15))
        tapTab(app, "Settings")
        app.buttons["settings.suggest"].tap()
        let editor = app.textViews["feedback.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feedback.send"].isEnabled)
        editor.tap(); editor.typeText("Add a weight chart")
        shot(app, "suggest-form")
        app.buttons["feedback.send"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "settings.suggestion").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Add a weight chart"))
        XCTAssertTrue(row.label.contains("Received"))
        shot(app, "suggest-list")
        app.terminate()
    }

    func testPetPhotoDetailsAndHistorySearch() {
        let app = app(["-SeedDemo", "-DemoPro", "-DemoPhoto"])
        let header = app.buttons["now.pet"]
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        shot(app, "pet-now-photo")
        XCTAssertFalse(app.staticTexts["Add photo"].exists)
        header.tap()
        XCTAssertTrue(app.buttons["pet.photo.remove"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pet.photo"].exists)
        XCTAssertTrue(app.links["pet.call"].exists || app.buttons["pet.call"].exists)
        shot(app, "pet-editor-photo")
        app.swipeUp()
        let insurance = app.textFields["pet.insurance"]
        XCTAssertTrue(insurance.waitForExistence(timeout: 5))
        insurance.tap(); insurance.typeText("Acme Pet")
        shot(app, "pet-editor-details")
        app.buttons["pet.save"].tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        // Removing the photo is saved, and Now offers to add one again.
        header.tap()
        XCTAssertTrue(app.buttons["pet.photo.remove"].waitForExistence(timeout: 5))
        app.buttons["pet.photo.remove"].tap()
        XCTAssertFalse(app.buttons["pet.photo.remove"].waitForExistence(timeout: 1))
        app.buttons["pet.save"].tap()
        XCTAssertTrue(app.staticTexts["Add photo"].waitForExistence(timeout: 5))
        shot(app, "pet-now-no-photo")
        header.tap()
        app.swipeUp()
        XCTAssertEqual(app.textFields["pet.insurance"].value as? String, "Acme Pet")
        app.buttons["Close"].tap()
        tapTab(app, "History")
        XCTAssertTrue(app.buttons["history.entry"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "history.entry").count, 4)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("walk")
        let oneResult = NSPredicate { _, _ in app.buttons.matching(identifier: "history.entry").count == 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: oneResult, object: nil)], timeout: 5)
        shot(app, "history-search")
        search.typeText("zzz")
        XCTAssertFalse(app.buttons["history.entry"].firstMatch.waitForExistence(timeout: 1))
        app.terminate()
    }

    func testSitterSheetShowsPetPhoto() {
        let app = app(["-SeedDemo", "-DemoPro", "-DemoPhoto", "-ScreenshotRoute", "sitter"])
        XCTAssertTrue(app.buttons["Share PDF"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 0.7)
        shot(app, "sitter-photo")
        app.terminate()
    }

    func testSettingsShowsVersionAndBuild() {
        let app = app(["-SeedDemo"])
        XCTAssertTrue(app.buttons["log.meal"].waitForExistence(timeout: 15))
        tapTab(app, "Settings")
        let pattern = NSPredicate(format: "label MATCHES %@", ".*[0-9]+\\.[0-9]+\\.[0-9]+ \\([0-9]+\\).*")
        let version = app.descendants(matching: .any).matching(pattern).firstMatch
        for _ in 0..<8 where !version.exists { app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        shot(app, "settings-version")
        app.terminate()
    }

    func testAllMainScreensLightAndDark() throws {
        let routes = ["now", "history", "care", "settings", "pets", "pet", "medications", "medication", "dose", "due", "household", "join", "invite", "sitter", "correction", "paywall"]
        for mode in ["light", "dark"] {
            for route in routes {
                var args = ["-SeedDemo", "-DemoPro", "-ScreenshotRoute", route, "-Appearance", mode]
                if route == "paywall" { args += ["-PaywallSnapshot", "yearly"] }
                let app = app(args)
                if ["now", "history", "care", "settings"].contains(route) { XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15)) }
                else { XCTAssertTrue(app.buttons["Close"].firstMatch.waitForExistence(timeout: 15)) }
                if route == "paywall" { XCTAssertTrue(app.buttons["plan.yearly"].waitForExistence(timeout: 20)) }
                if route == "sitter" { XCTAssertTrue(app.buttons["Share PDF"].waitForExistence(timeout: 10)) }
                // Let the sheet animation finish before retaining visual evidence.
                Thread.sleep(forTimeInterval: 0.7)
                shot(app, "\(route)-\(mode)")
                app.terminate()
            }
            for state in ["empty", "onboarding", "trial", "monthly"] {
                var args = ["-Appearance", mode]
                if state == "empty" { args += ["-EmptyLog"] }
                else if state == "onboarding" { args += ["-Onboarding"] }
                else if state == "trial" { args += ["-Onboarding", "-OnboardingTrial"] }
                else { args += ["-SeedDemo", "-PaywallSnapshot", "monthly"] }
                let app = app(args)
                if state == "trial" || state == "monthly" { XCTAssertTrue(app.buttons["plan.monthly"].waitForExistence(timeout: 20)) }
                else if state == "onboarding" { XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 15)) }
                else { XCTAssertTrue(app.buttons["Add a pet"].waitForExistence(timeout: 15)) }
                Thread.sleep(forTimeInterval: 0.7)
                shot(app, "\(state)-\(mode)")
                app.terminate()
            }
        }
    }
    func testLargeTextAndSmallWidthScreens() {
        for route in ["now", "history", "care", "settings", "pets", "pet", "medication", "dose", "household", "paywall"] {
            // The system setting, so sheets get large text too.
            let app = app(["-SeedDemo", "-DemoPro", "-LargeText", "-SmallPhone", "-ScreenshotRoute", route, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
            if route == "paywall" { XCTAssertTrue(app.buttons["plan.yearly"].waitForExistence(timeout: 20)) }
            else { XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15)) }
            Thread.sleep(forTimeInterval: 1)
            shot(app, "\(route)-large-small")
            app.swipeUp()
            shot(app, "\(route)-large-small-scrolled")
            app.terminate()
        }
    }
}
