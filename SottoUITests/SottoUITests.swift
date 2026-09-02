import XCTest

final class SottoUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Fresh onboarding, in-memory store, no lock: deterministic regardless of the host's state.
        app.launchArguments += ["-hasCompletedOnboarding", "NO", "-storeConversations", "NO", "-requireAppLock", "NO"]
    }

    @MainActor
    func testOnboardingLeadsToEmptyChat() throws {
        app.launch()
        let start = app.descendants(matching: .any).matching(identifier: "onboarding.start").firstMatch
        if !start.waitForExistence(timeout: 10) {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "Accessibility tree"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("AXTREE-BEGIN\n" + app.debugDescription + "\nAXTREE-END")
        }
        XCTAssertTrue(start.exists, "Onboarding should offer a start button")
        start.tap()
        XCTAssertTrue(app.staticTexts["What are we working on?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "composer.editor").firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSendingProducesAResponseOrAClearError() throws {
        app.launch()
        let start = app.descendants(matching: .any).matching(identifier: "onboarding.start").firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let editor = app.descendants(matching: .any).matching(identifier: "composer.editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("Say hello in one word.")
        let send = app.descendants(matching: .any).matching(identifier: "composer.send").firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        // Either the on-device model answers (copy chip appears) or the engine reports why it can't.
        let answered = app.descendants(matching: .any).matching(identifier: "message.copy").firstMatch.waitForExistence(timeout: 90)
        let failed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Apple Intelligence' OR label CONTAINS[c] 'model'")).firstMatch.exists
        XCTAssertTrue(answered || failed, "After sending, the chat must show an answer or an explanatory error")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
