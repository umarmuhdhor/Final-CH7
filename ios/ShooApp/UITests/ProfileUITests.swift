import XCTest

/// Fase 06: Profile (PF-01 redesign), pushed from the avatar button: Pribadi, Guardian, Protected.
final class ProfileUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openProfile(mode: String, familyMode: Bool = false, language: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMock", "YES",
            "-settings.onboardingCompleted", "YES",
            "-settings.onboardingConnectPassed", "YES",
            "-settings.mode", mode,
            "-settings.language", language,
            "-settings.familyModeOn", familyMode ? "YES" : "NO",
            "-settings.textSize", "1",
            "-settings.theme", "light",
            "-UITestExtensionActive", "YES",
        ] + extra
        app.launch()
        let button = app.buttons["profileButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()
        XCTAssertTrue(app.buttons["profile.manage"].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }

    /// Scrolls until the element can be tapped (rows below the card start off screen).
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.exists || !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    func testPersonalShowsInviteExtensionAndMode() {
        let app = openProfile(mode: "guardian")
        XCTAssertTrue(app.buttons["profile.invite"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["profile.extension.active"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["profile.member.dev_mom"].exists)
        XCTAssertFalse(app.buttons["profile.connection"].exists)
        app.buttons["profile.invite"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["invite.code"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testModeSwitchShowsTheFamily() {
        let app = openProfile(mode: "guardian")
        let mode = app.buttons["profile.mode"]
        reveal(mode, in: app)
        mode.tap()
        let guardian = app.buttons["mode.guardian"]
        XCTAssertTrue(guardian.waitForExistence(timeout: 5), app.debugDescription)
        guardian.tap()
        let switchButton = app.buttons["mode.switch"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 5), app.debugDescription)
        switchButton.tap()
        XCTAssertFalse(switchButton.waitForExistence(timeout: 1), "Nothing left to switch")
        app.buttons["profile.back"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.member.dev_mom"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testDeleteAccountStartsOnboardingOver() {
        let app = openProfile(mode: "guardian")
        let delete = app.buttons["profile.delete"]
        reveal(delete, in: app)
        delete.tap()
        let confirm = app.buttons["profile.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.buttons["splash.skip"].waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    func testLanguageSwitchesTheWholeAppAtOnce() {
        let app = openProfile(mode: "guardian")
        let language = app.buttons["profile.language"]
        reveal(language, in: app)
        language.tap()
        let indonesian = app.buttons["language.id"]
        XCTAssertTrue(indonesian.waitForExistence(timeout: 5), app.debugDescription)
        indonesian.tap()
        XCTAssertTrue(app.staticTexts["Bahasa"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["profile.back"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Profil"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["profile.back"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Aktivitas"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Kamu terlindungi"].exists, app.debugDescription)

        // Back to English for the next run.
        app.buttons["profileButton"].tap()
        reveal(app.buttons["profile.language"], in: app)
        app.buttons["profile.language"].tap()
        XCTAssertTrue(app.buttons["language.en"].waitForExistence(timeout: 5))
        app.buttons["language.en"].tap()
        XCTAssertTrue(app.staticTexts["Language"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testNameEditFollowsTheOnboardingRule() {
        let app = openProfile(mode: "guardian")
        let manage = app.buttons["profile.manage"]
        reveal(manage, in: app)
        manage.tap()
        XCTAssertTrue(app.buttons["profile.changePhoto"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["profile.username"].label.contains("@adhella"), app.debugDescription)
        app.buttons["profile.displayName"].tap()
        let field = app.textFields["profile.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(field.value as? String, "Adhella")
        field.tap()
        field.typeText(String(repeating: "x", count: 15))
        XCTAssertTrue(app.staticTexts["Use 20 characters or fewer."].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["profile.saveName"].isEnabled)
    }

    @MainActor
    func testProtectedDisconnectGoesBackToConnect() {
        let app = openProfile(mode: "protected")
        XCTAssertFalse(app.buttons["profile.invite"].exists)
        let connection = app.buttons["profile.connection"]
        reveal(connection, in: app)
        connection.tap()
        let guardian = app.descendants(matching: .any)["profile.guardian"]
        XCTAssertTrue(guardian.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(guardian.label.contains("Adhella"), guardian.debugDescription)
        app.buttons["profile.disconnect"].tap()
        let confirm = app.buttons["profile.disconnect.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Connect your account"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor
    func testGuardianDisconnectsAMemberFromTheDetail() {
        let app = openProfile(mode: "guardian", familyMode: true)
        let dad = app.descendants(matching: .any)["profile.member.dev_dad"].firstMatch
        XCTAssertTrue(dad.waitForExistence(timeout: 5), app.debugDescription)
        dad.tap()
        XCTAssertTrue(app.descendants(matching: .any)["member.status.off"].waitForExistence(timeout: 5), app.debugDescription)
        let disconnect = app.buttons["member.disconnect"]
        reveal(disconnect, in: app)
        disconnect.tap()
        let confirm = app.buttons["member.disconnect.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.member.dev_mom"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["profile.member.dev_dad"].exists)
    }

    @MainActor
    func testMemberSeeAllShowsOnlyTheirActivity() {
        let app = openProfile(mode: "guardian", familyMode: true)
        let mom = app.descendants(matching: .any)["profile.member.dev_mom"].firstMatch
        XCTAssertTrue(mom.waitForExistence(timeout: 5), app.debugDescription)
        mom.tap()
        let seeAll = app.buttons["member.seeAll"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 5), app.debugDescription)
        reveal(seeAll, in: app)
        seeAll.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["person.everyone"].exists)
    }

    // MARK: PF-01 settings pages

    @MainActor
    func testChangePhotoPicksAnOnboardingAvatar() {
        let app = openProfile(mode: "guardian")
        app.buttons["profile.manage"].tap()
        let change = app.buttons["profile.changePhoto"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), app.debugDescription)
        change.tap()
        let avatar = app.buttons["avatar.avatar_02"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5), app.debugDescription)
        avatar.tap()
        XCTAssertFalse(avatar.waitForExistence(timeout: 2), "The picker closes after a save")
    }

    @MainActor
    func testNotificationsShowFamilySwitchesOnlyForAGuardian() {
        let app = openProfile(mode: "guardian", familyMode: true)
        let row = app.buttons["profile.notifications"]
        reveal(row, in: app)
        row.tap()
        let warning = app.switches["notifications.warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.switches["notifications.family"].exists)
        XCTAssertTrue(app.switches["notifications.protectionOff"].exists)
        let summary = app.switches["notifications.summary"]
        reveal(summary, in: app)
        XCTAssertEqual(summary.value as? String, "0")
        summary.switches.firstMatch.tap()
        XCTAssertEqual(summary.value as? String, "1")

        let personal = openProfile(mode: "guardian", familyMode: false)
        reveal(personal.buttons["profile.notifications"], in: personal)
        personal.buttons["profile.notifications"].tap()
        XCTAssertTrue(personal.switches["notifications.blocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(personal.switches["notifications.family"].exists)
    }

    @MainActor
    func testQuietHoursTimeOpensAPicker() {
        let app = openProfile(mode: "protected")
        reveal(app.buttons["profile.notifications"], in: app)
        app.buttons["profile.notifications"].tap()
        let time = app.buttons["notifications.quietTime"]
        reveal(time, in: app)
        XCTAssertTrue(time.label.contains("22:00"), time.label)
        time.tap()
        XCTAssertTrue(app.buttons["quiet.save"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["quiet.save"].tap()
        XCTAssertTrue(time.waitForExistence(timeout: 5))
    }

    @MainActor
    func testThemeAndTextSizeChangeAtOnce() {
        let app = openProfile(mode: "guardian")
        let theme = app.buttons["profile.theme"]
        reveal(theme, in: app)
        XCTAssertTrue(theme.label.contains("Light"), theme.label)
        theme.tap()
        let dark = app.buttons["theme.dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5), app.debugDescription)
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        app.buttons["profile.back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["profile.theme"].label.contains("Dark"), app.buttons["profile.theme"].label)

        app.buttons["profile.accessibility"].tap()
        let slider = app.descendants(matching: .any)["accessibility.textSize"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(slider.value as? String, "Standard")
        slider.swipeRight()
        XCTAssertNotEqual(slider.value as? String, "Standard")
        XCTAssertTrue(app.switches["accessibility.haptics"].exists)
    }

    @MainActor
    func testAboutShowsLegalShareAndContact() {
        let app = openProfile(mode: "guardian")
        let about = app.buttons["profile.about"]
        reveal(about, in: app)
        about.tap()
        for id in ["about.privacy", "about.terms", "about.licenses", "about.rate", "about.share", "about.contact"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), id)
        }
        app.buttons["about.licenses"].tap()
        XCTAssertTrue(app.staticTexts["Third-party licenses"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    /// "Punya kode undangan?": a guardian without members joins another family and is protected from then on.
    @MainActor
    func testGuardianWithoutMembersJoinsAnotherFamily() {
        let app = openProfile(mode: "guardian", extra: ["-mock.scenario", "empty"])
        reveal(app.buttons["profile.mode"], in: app)
        app.buttons["profile.mode"].tap()
        let join = app.buttons["mode.joinFamily"]
        reveal(join, in: app)
        join.tap()
        let field = app.textFields["connect.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("482193")
        app.buttons["connect.join"].tap()
        let title = app.staticTexts["protectedBy.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(title.label.contains("Budi"), title.label)
        app.buttons["protectedBy.continue"].tap()

        let profile = app.buttons["profileButton"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10), app.debugDescription)
        profile.tap()
        let connection = app.buttons["profile.connection"]
        reveal(connection, in: app)
        connection.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.guardian"].label.contains("Budi"), app.debugDescription)
    }

    @MainActor
    func testGuardianWithMembersIsAskedToDisconnectThemFirst() {
        let app = openProfile(mode: "guardian")
        reveal(app.buttons["profile.mode"], in: app)
        app.buttons["profile.mode"].tap()
        let join = app.buttons["mode.joinFamily"]
        reveal(join, in: app)
        join.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.textFields["connect.code"].exists)
    }
}
