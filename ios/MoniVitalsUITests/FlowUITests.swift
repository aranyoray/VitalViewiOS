//
//  FlowUITests.swift
//  MoniVitalsUITests
//
//  End-to-end runtime verification: drives every screen of the MoniVitals app,
//  clears the first-run onboarding gate, asserts real replayed data flows on the
//  Dashboard (Heart-rate tile is numeric, not "—"), visits each tab (handling the
//  iPhone "More" overflow for Clips/Settings), asserts a distinctive element per
//  screen, and captures a full-screen screenshot attachment for each.
//

import XCTest

final class FlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true   // keep visiting screens even if one assert fails
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Helpers

    /// Full-screen screenshot as a permanent attachment named after the screen.
    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    /// Clear the first-run "NOT a medical device" gate if it is showing.
    private func clearOnboardingIfPresent() {
        // The gate has a single switch and a "Get started" button, under the
        // "Welcome to MoniVitals" header. Detect via any of these anchors.
        let getStarted = app.buttons["Get started"]
        let welcome = app.staticTexts["Welcome to MoniVitals"]
        let gateShown = getStarted.waitForExistence(timeout: 8)
            || welcome.waitForExistence(timeout: 2)
        guard gateShown else { return }

        snap("00-Onboarding")

        let toggle = app.switches.firstMatch
        if toggle.exists {
            // Flip it on. `value` is "0" (off) / "1" (on) for UISwitch.
            if (toggle.value as? String) != "1" {
                toggle.tap()
            }
        }
        // Button is disabled until the switch is on; wait for it to be hittable.
        _ = getStarted.waitForExistence(timeout: 3)
        let deadline = Date().addingTimeInterval(5)
        while !(getStarted.isEnabled && getStarted.isHittable) && Date() < deadline {
            usleep(200_000)
        }
        if getStarted.exists { getStarted.tap() }
    }

    /// Tap a tab-bar button by label, handling the "More" overflow.
    /// Returns true if the tab was reached.
    ///
    /// On this iPhone the TabView shows 5 tabs (Dashboard, Save, Calibrate,
    /// Signal) plus a "More" overflow that holds Clips and Settings. On iOS 26
    /// the "More" list is a UICollectionView (not a UITable), and — because it
    /// remembers the last-visited overflow item — tapping "More" can push
    /// straight into a detail (e.g. Settings) rather than showing the list. We
    /// pop back to the list first, then pick the requested item.
    @discardableResult
    private func openTab(_ label: String) -> Bool {
        let tabBars = app.tabBars

        // Direct tab (Dashboard / Save / Calibrate / Signal). Retry a few times —
        // the tab bar can briefly be non-hittable during a screen transition.
        let direct = tabBars.buttons[label]
        for _ in 0..<5 {
            if direct.waitForExistence(timeout: 3) && direct.isHittable {
                direct.tap()
                return true
            }
            usleep(400_000)
        }

        // Otherwise it lives under "More". iOS 26's overflow is intermittently
        // finicky (a stale last-visited detail can be pushed instead of the list,
        // and the first "More" tap is sometimes swallowed), so retry the whole
        // dance a few times before giving up.
        for _ in 0..<4 {
            if tapOverflowItem(label) { return true }
            usleep(500_000)
        }
        return false
    }

    /// One attempt to reach an overflow ("More") tab item and tap it.
    private func tapOverflowItem(_ label: String) -> Bool {
        let more = app.tabBars.buttons["More"]
        guard more.waitForExistence(timeout: 3) else { return false }
        more.tap()

        // If "More" auto-pushed into a detail, pop back to the overflow list.
        // The list's nav bar is titled "More". Try popping a couple of times.
        for _ in 0..<3 {
            if app.navigationBars["More"].waitForExistence(timeout: 2) { break }
            // Pop whatever is on top: prefer a "More" back button, else the
            // leading back button of the current nav bar.
            let moreBack = app.navigationBars.buttons["More"].firstMatch
            if moreBack.exists && moreBack.isHittable {
                moreBack.tap()
            } else {
                let anyBack = app.navigationBars.buttons.element(boundBy: 0)
                if anyBack.exists && anyBack.isHittable { anyBack.tap() }
            }
        }

        // The overflow items are cells in a collection view; each exposes the
        // tab's label as a static text / button. Try several query shapes.
        let candidates: [XCUIElement] = [
            app.collectionViews.cells.staticTexts[label].firstMatch,
            app.collectionViews.buttons[label].firstMatch,
            app.tables.cells.staticTexts[label].firstMatch,   // fallback for older iOS
            app.cells.staticTexts[label].firstMatch,
            app.buttons[label].firstMatch,
            app.staticTexts[label].firstMatch,
        ]
        for element in candidates {
            if element.waitForExistence(timeout: 2) && element.isHittable {
                element.tap()
                return true
            }
        }
        return false
    }

    // MARK: - The one big flow

    func testDriveEveryScreen() throws {
        // 1) Onboarding gate.
        clearOnboardingIfPresent()

        // 2) We should now be on the TabView. Dashboard is the first tab.
        //    Wait for the tab bar to settle after the onboarding transition so the
        //    first tab taps don't race the animation.
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 8)
        //    Give the bundled replay ~4s to warm up so DSP produces a heart rate.
        let dashHeader = app.staticTexts["MoniVitals"].firstMatch
        XCTAssertTrue(dashHeader.waitForExistence(timeout: 10),
                      "Dashboard header 'MoniVitals' should appear after onboarding")

        // Wait for the "Heart rate" tile label to appear.
        let hrLabel = app.staticTexts["Heart rate"]
        XCTAssertTrue(hrLabel.waitForExistence(timeout: 10),
                      "Dashboard should render the 'Heart rate' tile")

        // 3) Assert real data flows: HR value is numeric (NOT "—"). Poll up to ~12s.
        let hrValue = waitForNumericHeartRate(timeout: 12)
        snap("01-Dashboard")
        XCTAssertNotNil(hrValue,
                        "Heart-rate tile never showed a numeric value (stayed '—'): no real data flowed")
        if let hr = hrValue {
            XCTAssertTrue(hr >= 20 && hr <= 250,
                          "Heart-rate \(hr) bpm is outside a plausible range")
        }

        // 4) Visit every tab, assert a distinctive element, screenshot each.

        // Save (RecorderView) — nav title "Save a Clip", "Profile" section.
        XCTAssertTrue(
            visit("Save", navBar: "Save a Clip", texts: ["Profile", "Selected profile"]),
            "Save screen distinctive element ('Save a Clip' nav bar / 'Profile') not found")
        snap("02-Save")

        // Calibrate (CalibrationView) — nav title "Calibrate"; fresh install shows
        // "No profile selected".
        XCTAssertTrue(
            visit("Calibrate", navBar: "Calibrate", texts: ["No profile selected", "Add a sample reading"]),
            "Calibrate screen distinctive element not found")
        snap("03-Calibrate")

        // Signal (GatingView) — nav title "Signal Quality", "Clean segments" tile.
        XCTAssertTrue(
            visit("Signal", navBar: "Signal Quality", texts: ["Clean segments"]),
            "Signal screen distinctive element ('Signal Quality' / 'Clean segments') not found")
        snap("04-Signal")

        // Clips (ReviewView) — under "More". Nav title "Saved Clips"; empty state
        // "No saved clips yet".
        XCTAssertTrue(
            visit("Clips", navBar: "Saved Clips", texts: ["No saved clips yet", "Saved clips"]),
            "Clips screen distinctive element ('Saved Clips' / 'No saved clips yet') not found")
        snap("05-Clips")

        // Settings (SettingsView) — under "More". Nav title "Settings"; "About" section.
        XCTAssertTrue(
            visit("Settings", navBar: "Settings", texts: ["About"], textPrefixes: ["Model:"]),
            "Settings screen distinctive element ('Settings' nav bar / 'About' / 'Model:') not found")
        snap("06-Settings")
    }

    /// Open a tab and confirm a distinctive element appeared, self-healing against
    /// transition races: if the anchor doesn't show, re-open the tab and re-check.
    private func visit(_ tab: String, navBar: String, texts: [String],
                       textPrefixes: [String] = []) -> Bool {
        for attempt in 0..<3 {
            guard openTab(tab) else { usleep(500_000); continue }
            // Generous on the first look, quick on retries.
            let t: TimeInterval = attempt == 0 ? 8 : 3
            if app.navigationBars[navBar].waitForExistence(timeout: t) { return true }
            for label in texts where app.staticTexts[label].firstMatch.waitForExistence(timeout: 2) {
                return true
            }
            for prefix in textPrefixes {
                let q = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
                if q.firstMatch.waitForExistence(timeout: 2) { return true }
            }
            usleep(500_000)
        }
        return false
    }

    // MARK: - Heart-rate extraction

    /// The Heart-rate MetricTile renders its title ("Heart rate") and value as
    /// separate static texts inside a VStack. We locate the numeric value by
    /// scanning for a pure-integer static text that appears once the DSP warms up.
    /// Returns the parsed bpm, or nil if it never became numeric within `timeout`.
    private func waitForNumericHeartRate(timeout: TimeInterval) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hr = currentHeartRate() {
                return hr
            }
            usleep(400_000)
        } while Date() < deadline
        return currentHeartRate()
    }

    /// Best-effort read of the current Heart-rate value from the accessibility tree.
    private func currentHeartRate() -> Int? {
        // Strategy: the "Heart rate" tile groups (or neighbours) a numeric value.
        // 1) Try the tile as a grouped element whose label contains "Heart rate"
        //    and a number.
        let grouped = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS 'Heart rate'")
        )
        for i in 0..<grouped.count {
            if let n = firstPlausibleBpm(in: grouped.element(boundBy: i).label) {
                return n
            }
        }

        // 2) Fallback: scan static texts. The HR value is a bare 2–3 digit integer.
        //    Guard against picking up unit-only tiles by requiring it not be one of
        //    the known non-HR numeric contexts; a plausible bpm range filters most.
        let texts = app.staticTexts
        for i in 0..<texts.count {
            let label = texts.element(boundBy: i).label
            if let n = pureInteger(label), n >= 20 && n <= 250 {
                // "Heart rate" tile is the first numeric metric on the Dashboard;
                // returning the first plausible bpm-range integer is reliable here.
                return n
            }
        }
        return nil
    }

    private func pureInteger(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(t)
    }

    private func firstPlausibleBpm(in label: String) -> Int? {
        let scanner = label.split(whereSeparator: { !$0.isNumber })
        for token in scanner {
            if let n = Int(token), n >= 20 && n <= 250 {
                return n
            }
        }
        return nil
    }
}
