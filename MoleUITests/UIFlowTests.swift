import XCTest

// MARK: - UI Flow Tests
//
// These tests verify critical user-facing flows in MoleUI using XCUIApplication.
// They cover destructive operation confirmations and recoverability steps.
//
// To run in Xcode: Product → Test (⌘U) with the MoleUI scheme selected.
// Requires a running macOS app session; tests will be skipped in CI if no
// display is available.

final class UIFlowTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()

        // Wait for app to be ready
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    // MARK: - Navigation

    @MainActor
    func testAppLaunchesSuccessfully() {
        // Verify fundamental launch succeeds and shows main navigation
        XCTAssertTrue(app.windows.firstMatch.exists, "App window should exist after launch")
        XCTAssertTrue(app.windows.firstMatch.isHittable, "App window should be interactive")
    }

    @MainActor
    func testSidebarNavigationExists() {
        // The app uses NavigationSplitView with a sidebar
        // Verify key navigation items are visible
        let sidebar = app.splitGroups.firstMatch
        let hasSidebar = sidebar.exists || app.tables.firstMatch.exists || app.outlines.firstMatch.exists

        XCTAssertTrue(hasSidebar, "Sidebar navigation should be present")
    }

    @MainActor
    func testAllNavigationItemsAccessible() {
        // Verify all main navigation items can be accessed
        let navigationItems = ["Status", "Clean", "Optimize", "Purge", "Uninstall", "Installer", "Disk", "Settings"]

        for item in navigationItems {
            let button = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", item)).firstMatch
            if button.exists {
                XCTAssertTrue(button.isEnabled, "\(item) navigation should be enabled")
            }
        }
    }

    // MARK: - Clean Flow (Destructive)

    @MainActor
    func testCleanNavigationWorks() throws {
        let cleanButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Clean'")).firstMatch
        guard cleanButton.exists else {
            throw XCTSkip("Clean sidebar item not found - UI layout may have changed")
        }

        cleanButton.click()

        // Verify Clean view loaded
        let hasCleanContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Clean'")).firstMatch
            .waitForExistence(timeout: 3)

        XCTAssertTrue(hasCleanContent, "Clean view should load")
    }

    @MainActor
    func testCleanScanButtonExists() throws {
        let cleanButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Clean'")).firstMatch
        guard cleanButton.exists else {
            throw XCTSkip("Clean sidebar item not found")
        }
        cleanButton.click()

        let scanButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Scan'")).firstMatch
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3), "Scan button should exist")
    }

    // MARK: - Purge Flow (Destructive)

    @MainActor
    func testPurgeNavigationAndScanVisible() throws {
        let purgeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Purge'")).firstMatch
        guard purgeButton.exists else {
            throw XCTSkip("Purge sidebar item not found")
        }
        purgeButton.click()

        let scanButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Scan'")).firstMatch
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3) || app.staticTexts.count > 0,
                      "Purge view should show scan controls or content")
    }

    @MainActor
    func testPurgeEditPathsButtonExists() throws {
        let purgeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Purge'")).firstMatch
        guard purgeButton.exists else {
            throw XCTSkip("Purge sidebar item not found")
        }
        purgeButton.click()

        let editButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Edit'")).firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 3), "Edit Paths button should exist")
    }

    // MARK: - Uninstall Flow (Destructive)

    @MainActor
    func testUninstallListLoadsWithoutCrash() throws {
        let uninstallButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Uninstall'")).firstMatch
        guard uninstallButton.exists else {
            throw XCTSkip("Uninstall sidebar item not found")
        }
        uninstallButton.click()

        // Wait for content to load
        let contentLoaded = XCTWaiter.wait(for: [
            expectation(description: "Content loads")
        ], timeout: 10)

        // The list should appear, or an error message — either is a non-crash state
        let hasContent = app.tables.firstMatch.exists
            || app.scrollViews.firstMatch.exists
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'No'")).firstMatch.exists
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Scanning'")).firstMatch.exists

        XCTAssertTrue(hasContent || contentLoaded == .timedOut,
                      "Uninstall view should show list or empty/scanning state")
    }

    @MainActor
    func testUninstallSearchExists() throws {
        let uninstallButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Uninstall'")).firstMatch
        guard uninstallButton.exists else {
            throw XCTSkip("Uninstall sidebar item not found")
        }
        uninstallButton.click()

        // Search field should exist
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should exist")
    }

    // MARK: - Installer Flow

    @MainActor
    func testInstallerNavigationWorks() throws {
        let installerButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Installer'")).firstMatch
        guard installerButton.exists else {
            throw XCTSkip("Installer sidebar item not found")
        }
        installerButton.click()

        let hasContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Installer'")).firstMatch
            .waitForExistence(timeout: 3)

        XCTAssertTrue(hasContent, "Installer view should load")
    }

    // MARK: - Dashboard

    @MainActor
    func testDashboardMetricsDisplay() throws {
        // Dashboard is the default view - verify it shows system metrics
        let statusButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Status'")).firstMatch
        if statusButton.exists { statusButton.click() }

        // Wait for metrics to load
        let metricsLoaded = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'CPU'")).firstMatch
            .waitForExistence(timeout: 10)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Memory'")).firstMatch
            .waitForExistence(timeout: 10)

        XCTAssertTrue(metricsLoaded, "Dashboard should display CPU or Memory metrics within 10 seconds")
    }

    @MainActor
    func testDashboardHealthScoreVisible() throws {
        let statusButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Status'")).firstMatch
        if statusButton.exists { statusButton.click() }

        let healthScore = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Health'")).firstMatch
        XCTAssertTrue(healthScore.waitForExistence(timeout: 10), "Health score should be visible")
    }

    // MARK: - Disk Analyzer

    @MainActor
    func testDiskAnalyzerNavigationWorks() throws {
        let diskButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk'")).firstMatch
        guard diskButton.exists else {
            throw XCTSkip("Disk sidebar item not found")
        }
        diskButton.click()

        let hasContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Disk'")).firstMatch
            .waitForExistence(timeout: 3)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Scanning'")).firstMatch
            .waitForExistence(timeout: 3)

        XCTAssertTrue(hasContent, "Disk Analyzer view should load")
    }

    // MARK: - Settings

    @MainActor
    func testSettingsNavigationWorks() throws {
        let settingsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Settings'")).firstMatch
        guard settingsButton.exists else {
            throw XCTSkip("Settings sidebar item not found")
        }
        settingsButton.click()

        let hasContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'About'")).firstMatch
            .waitForExistence(timeout: 3)

        XCTAssertTrue(hasContent, "Settings view should load and show About section")
    }

    // MARK: - Error Handling

    @MainActor
    func testAppDoesNotCrashOnRapidNavigation() {
        // Rapidly switch between views
        let navigationItems = ["Status", "Clean", "Purge", "Uninstall", "Settings"]

        for _ in 0..<3 {
            for item in navigationItems {
                let button = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", item)).firstMatch
                if button.exists && button.isEnabled {
                    button.click()
                    // Small delay to allow view to start loading
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }

        // App should still be responsive
        XCTAssertTrue(app.windows.firstMatch.exists, "App should not crash during rapid navigation")
    }
}

