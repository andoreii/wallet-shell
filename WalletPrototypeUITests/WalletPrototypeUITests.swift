// WalletPrototypeUITests.swift
// Exercises the main gestures and captures the important Wallet screen states.

import XCTest

// Startup motion is disabled here so interaction checks begin from a settled stack.
@MainActor
final class WalletPrototypeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-DisableWalletStartupAnimation"
        ]
        app.launch()
    }

    func testPrimaryFlowAndCaptureStates() {
        XCTAssertTrue(app.staticTexts["Wallet"].waitForExistence(timeout: 3))
        attachScreenshot(named: "01-initial-stack")

        let frontCard = app.descendants(matching: .any)["wallet-card-halo"]
        XCTAssertTrue(frontCard.waitForExistence(timeout: 2))
        frontCard.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 2))
        attachScreenshot(named: "02-card-detail")

        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Wallet"].waitForExistence(timeout: 2))

        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Add to Wallet"].waitForExistence(timeout: 2))
        attachScreenshot(named: "03-add-sheet")
        app.buttons["Close"].tap()
    }

    func testPassDetailCapture() {
        let pass = app.descendants(matching: .any)["wallet-pass-skylark-pass"]
        XCTAssertTrue(pass.waitForExistence(timeout: 3))
        pass.tap()
        XCTAssertTrue(app.staticTexts["Pass Information"].waitForExistence(timeout: 2))
        attachScreenshot(named: "04-pass-detail")
    }

    func testEveryCardCanBeSelectedAndTappedAgainToDeselect() {
        for id in ["aurora", "evergreen", "signal", "halo"] {
            let card = app.descendants(matching: .any)["wallet-card-\(id)"]
            XCTAssertTrue(card.waitForExistence(timeout: 2), "Missing card hit region: \(id)")
            card.tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 2), "Card did not expand: \(id)")

            let expandedCard = app.descendants(matching: .any)["wallet-card-\(id)"]
            expandedCard.tap()
            XCTAssertTrue(app.staticTexts["Wallet"].waitForExistence(timeout: 2), "Card did not collapse: \(id)")
        }
    }

    func testHeaderPinsAndTitleFadesWhileCardsScroll() {
        let addButton = app.buttons["Add"]
        let moreButton = app.buttons["More"]
        let title = app.staticTexts["Wallet"]
        let frontCard = app.descendants(matching: .any)["wallet-card-halo"]

        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(moreButton.exists)
        XCTAssertTrue(frontCard.exists)

        let initialAddY = addButton.frame.minY
        let initialCardY = frontCard.frame.minY
        app.swipeUp()
        app.swipeUp()

        XCTAssertEqual(addButton.frame.minY, initialAddY, accuracy: 2)
        XCTAssertTrue(moreButton.exists)
        XCTAssertLessThan(frontCard.frame.minY, initialCardY - 40)
        XCTAssertTrue(title.waitForNonExistence(timeout: 2))
        attachScreenshot(named: "05-pinned-header-scrolled-stack")
    }

    func testStackPullDownSpringsBackToItsRestPosition() {
        let frontCard = app.descendants(matching: .any)["wallet-card-halo"]
        XCTAssertTrue(frontCard.waitForExistence(timeout: 2))
        let initialMinY = frontCard.frame.minY

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)

        let returned = NSPredicate { _, _ in
            abs(frontCard.frame.minY - initialMinY) <= 2
        }
        expectation(for: returned, evaluatedWith: frontCard)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(frontCard.frame.minY, initialMinY, accuracy: 2)
        XCTAssertTrue(frontCard.isHittable)

        // This held drag guards against the old frozen overscroll gap.
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        let returnedAfterHeldPull = NSPredicate { _, _ in
            abs(frontCard.frame.minY - initialMinY) <= 2 && frontCard.isHittable
        }
        expectation(for: returnedAfterHeldPull, evaluatedWith: frontCard)
        waitForExpectations(timeout: 2)

        frontCard.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 2))
    }

    func testDetailHeaderCrossFadesWithoutMovingOverflowControl() {
        let moreButton = app.buttons["More"]
        let addButton = app.buttons["Add"]
        let title = app.staticTexts["Wallet"]
        let card = app.descendants(matching: .any)["wallet-card-evergreen"]

        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(moreButton.exists)
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(card.exists)

        let initialMoreFrame = moreButton.frame
        card.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 2))
        XCTAssertTrue(title.waitForNonExistence(timeout: 2))
        XCTAssertFalse(addButton.isHittable)
        XCTAssertEqual(moreButton.frame.minX, initialMoreFrame.minX, accuracy: 0.5)
        XCTAssertEqual(moreButton.frame.minY, initialMoreFrame.minY, accuracy: 0.5)
        XCTAssertEqual(moreButton.frame.size.width, initialMoreFrame.size.width, accuracy: 0.5)
        XCTAssertEqual(moreButton.frame.size.height, initialMoreFrame.size.height, accuracy: 0.5)

        app.buttons["Close"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))
        XCTAssertEqual(moreButton.frame.minX, initialMoreFrame.minX, accuracy: 0.5)
        XCTAssertEqual(moreButton.frame.minY, initialMoreFrame.minY, accuracy: 0.5)
    }

    func testOverflowMenuMatchesWalletEntries() {
        let moreButton = app.buttons["More"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 2))
        moreButton.tap()

        XCTAssertTrue(app.buttons["Orders"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Preauthorized Payments"].exists)
        XCTAssertTrue(app.buttons["AutoFill"].exists)
        XCTAssertTrue(app.buttons["Expired"].exists)
        XCTAssertTrue(app.buttons["Notifications"].exists)
        attachScreenshot(named: "06-overflow-menu")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
