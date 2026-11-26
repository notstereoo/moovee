import XCTest

final class CineBoardUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    // MARK: Помощники

    private func register(_ name: String = "ui_tester") {
        app.segmentedControls.buttons["Sign up"].tap()
        let user = app.textFields["Username"]
        XCTAssertTrue(user.waitForExistence(timeout: 5))
        user.tap()
        user.typeText(name)
        let password = app.secureTextFields["Password (8+ characters)"]
        password.tap()
        password.typeText("password123")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 10), "the feed should open after registration")
        dismissSavePasswordPrompt()
    }

    /// Если диалог уже на экране — закрывает его сразу, без ожидания.
    private func dismissSavePasswordPromptIfPresent() {
        for title in ["Not Now", "Не сейчас"] where app.buttons[title].exists {
            app.buttons[title].tap()
            return
        }
    }

    /// Системное предложение сохранить пароль перекрывает экран после регистрации.
    private func dismissSavePasswordPrompt() {
        for title in ["Not Now", "Не сейчас"] {
            let button = app.buttons[title]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    /// Нажатие сразу после системного диалога иногда теряется, поэтому проверяем, что вкладка выбрана.
    private func tab(_ title: String) {
        let button = app.tabBars.buttons[title]
        for _ in 0..<4 {
            dismissSavePasswordPromptIfPresent()
            button.tap()
            if button.isSelected { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("could not open the tab \"\(title)\"")
    }

    // MARK: Сценарии

    func testRegisterSearchAndSaveToNewCollection() {
        register()

        tab("Search")
        let search = app.searchFields["Movie title"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("The Matrix")

        let save = app.buttons["Save \"The Matrix\" to a collection"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the search result should appear")
        save.tap()

        app.buttons["Create collection"].tap()
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("My collection")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["My collection"].waitForExistence(timeout: 5), "the collection should appear in the sheet list")
        app.buttons["Done"].tap()

        tab("Collections")
        XCTAssertTrue(app.staticTexts["My collection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 film"].exists)
    }

    func testRateMovieShowsCommunityRatingAndProfileReview() {
        register("critic_1")

        let card = app.buttons["Poster: The Shawshank Redemption"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let rate = app.buttons["Rate"]
        // Нажатие сразу после системного диалога иногда теряется — повторяем.
        for _ in 0..<4 {
            dismissSavePasswordPromptIfPresent()
            card.tap()
            if rate.waitForExistence(timeout: 6) { break }
        }
        XCTAssertTrue(rate.exists)
        rate.tap()

        let picker = app.otherElements["Rating"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.35)).tap()  // 9-я звезда
        app.buttons["Save"].tap()

        let rating = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'CineBoard' AND label CONTAINS '1 rating'"))
        XCTAssertTrue(rating.firstMatch.waitForExistence(timeout: 5), "the community rating should update")
        XCTAssertTrue(app.buttons["My review"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        tab("Profile")
        XCTAssertTrue(app.staticTexts["My reviews"].waitForExistence(timeout: 5))
    }

    func testRegistrationRejectsShortPassword() {
        app.segmentedControls.buttons["Sign up"].tap()
        let user = app.textFields["Username"]
        user.tap()
        user.typeText("short_pw")
        let password = app.secureTextFields["Password (8+ characters)"]
        password.tap()
        password.typeText("abc")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.staticTexts["Password must be at least 8 characters."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Feed"].exists)
    }
}
