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

    /// Exporting is the only place Sotto writes outside its own container, so it is the only
    /// place the App Sandbox's user-selected-files entitlement is exercised. A read-only
    /// entitlement lets the save panel pick a destination and then denies the write, which no
    /// unit test can see: the failure lives in the sandbox, not in the code.
    ///
    /// macOS only — `fileExporter` on iOS goes through the document picker, which copies the
    /// file on the app's behalf and needs no entitlement.
    #if os(macOS)
    @MainActor
    func testExportingConversationsWritesAFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SottoUITests", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("export.json")

        app.launch()
        let start = app.descendants(matching: .any).matching(identifier: "onboarding.start").firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        // Export stays disabled until there is a conversation to export.
        app.typeKey("n", modifierFlags: .command)
        app.typeKey(",", modifierFlags: .command)
        let privacy = app.descendants(matching: .any).matching(identifier: "settings.pane.privacy").firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 10), "Settings should open on ⌘,")
        privacy.tap()
        let export = app.descendants(matching: .any).matching(identifier: "privacy.export").firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(export.isEnabled, "A conversation exists, so export should be offered")
        export.tap()

        // The save panel belongs to Powerbox, not to Sotto, when the app is sandboxed.
        let panel = XCUIApplication(bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService")
        let saveButton = panel.buttons["OKButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 20), "The save panel should appear")
        panel.typeKey("g", modifierFlags: [.command, .shift])
        panel.typeText(file.path)
        panel.typeKey(.return, modifierFlags: [])
        saveButton.click()

        let written = expectation(description: "the export file appears")
        let deadline = Date().addingTimeInterval(20)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            if FileManager.default.fileExists(atPath: file.path) || Date() > deadline {
                timer.invalidate()
                written.fulfill()
            }
        }
        wait(for: [written], timeout: 25)

        XCTAssertFalse(
            app.staticTexts["Export failed"].exists,
            "The sandbox refused the write the save panel had already granted"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Export should write the file the user chose")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        XCTAssertNotNil(json?["conversations"], "The export should hold the conversations")
    }
    #endif

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
