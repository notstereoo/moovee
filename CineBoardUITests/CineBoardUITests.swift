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
        app.segmentedControls.buttons["Регистрация"].tap()
        let user = app.textFields["Имя пользователя"]
        XCTAssertTrue(user.waitForExistence(timeout: 5))
        user.tap()
        user.typeText(name)
        let password = app.secureTextFields["Пароль (от 8 символов)"]
        password.tap()
        password.typeText("password123")
        app.buttons["Создать аккаунт"].tap()
        XCTAssertTrue(app.tabBars.buttons["Лента"].waitForExistence(timeout: 10), "после регистрации должна открыться лента")
        dismissSavePasswordPrompt()
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
            button.tap()
            if button.isSelected { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("не удалось открыть вкладку «\(title)»")
    }

    // MARK: Сценарии

    func testRegisterSearchAndSaveToNewCollection() {
        register()

        tab("Поиск")
        let search = app.searchFields["Название фильма"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Матрица")

        let save = app.buttons["Сохранить «Матрица» в подборку"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "результат поиска должен появиться")
        save.tap()

        app.buttons["Создать подборку"].tap()
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Моя подборка")
        app.buttons["Сохранить"].tap()

        XCTAssertTrue(app.staticTexts["Моя подборка"].waitForExistence(timeout: 5), "подборка должна появиться в списке шита")
        app.buttons["Готово"].tap()

        tab("Подборки")
        XCTAssertTrue(app.staticTexts["Моя подборка"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 фильм"].exists)
    }

    func testRateMovieShowsCommunityRatingAndProfileReview() {
        register("critic_1")

        let card = app.buttons["Постер: Побег из Шоушенка"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let rate = app.buttons["Оценить"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap()

        let picker = app.otherElements["Оценка"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.35)).tap()  // 9-я звезда
        app.buttons["Сохранить"].tap()

        let rating = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'CineBoard' AND label CONTAINS '1 оценка'"))
        XCTAssertTrue(rating.firstMatch.waitForExistence(timeout: 5), "рейтинг сообщества должен обновиться")
        XCTAssertTrue(app.buttons["Мой отзыв"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        tab("Профиль")
        XCTAssertTrue(app.staticTexts["Мои отзывы"].waitForExistence(timeout: 5))
    }

    func testRegistrationRejectsShortPassword() {
        app.segmentedControls.buttons["Регистрация"].tap()
        let user = app.textFields["Имя пользователя"]
        user.tap()
        user.typeText("short_pw")
        let password = app.secureTextFields["Пароль (от 8 символов)"]
        password.tap()
        password.typeText("abc")
        app.buttons["Создать аккаунт"].tap()
        XCTAssertTrue(app.staticTexts["Пароль должен содержать не менее 8 символов."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Лента"].exists)
    }
}
