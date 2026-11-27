import XCTest
@testable import RhythmCore

final class PersistenceTests: XCTestCase {
    func testExistingPreferencesUpgradeWithSystemAccentWithoutLosingSettings() throws {
        let legacy = Data(#"{"appearance":"dark","soundEnabled":false,"notificationsEnabled":false,"pauseOnLock":false,"defaultMinutes":45,"lastMode":"stopwatch"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(preferences.accentChoice, .system)
        XCTAssertEqual(preferences.backgroundOpacity, GlassStyle.defaultOpacity)
        XCTAssertEqual(preferences.backgroundBlur, GlassStyle.defaultBlur)
        XCTAssertTrue(preferences.showMenuBarTime)
        XCTAssertEqual(preferences.menuBarIcon, .rhythm)
        XCTAssertEqual(preferences.glowWidth, GlowStyle.defaultWidth)
        XCTAssertEqual(preferences.glowIntensity, GlowStyle.defaultIntensity)
        XCTAssertEqual(preferences.appearance, "dark")
        XCTAssertEqual(preferences.defaultMinutes, 45)
        XCTAssertEqual(preferences.lastMode, .stopwatch)
        XCTAssertFalse(preferences.soundEnabled)
        XCTAssertFalse(preferences.notificationsEnabled)
        XCTAssertFalse(preferences.pauseOnLock)
    }

    func testCustomAccentPersistsAlongsideExistingLedger() throws {
        var ledger = Ledger()
        ledger.preferences.accentChoice = .custom
        ledger.preferences.customAccentHex = "36A18B"
        ledger.preferences.backgroundOpacity = 0.23
        ledger.preferences.backgroundBlur = 0.4
        ledger.preferences.showMenuBarTime = false
        ledger.preferences.breakEdgeGlowEnabled = false
        ledger.preferences.animateLogo = false
        ledger.preferences.glowWidth = 236
        ledger.preferences.glowIntensity = 0.73
        ledger.preferences.menuBarIcon = .timer
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
        XCTAssertEqual(decoded.preferences.accentChoice, .custom)
        XCTAssertEqual(decoded.preferences.customAccentHex, "36A18B")
    }

    func testDefaultGlassMatchesPreviousAppearance() {
        let glass = GlassStyle()
        XCTAssertEqual(glass.materialOpacity, 1)
        XCTAssertEqual(glass.tintOpacity, 0)
    }

    func testBackgroundExtremesAndBlurIndependence() {
        let clear = GlassStyle(opacity: 0, blur: 1)
        XCTAssertEqual(clear.materialOpacity, 0)
        XCTAssertEqual(clear.tintOpacity, 0)
        let solid = GlassStyle(opacity: 1, blur: 0.2)
        XCTAssertEqual(solid.tintOpacity, 1, accuracy: 0.0001)
        let unblurred = GlassStyle(opacity: 0.4, blur: 0)
        XCTAssertEqual(unblurred.materialOpacity, 0)
        XCTAssertEqual(unblurred.tintOpacity, 0.4)
    }

    func testTransparencyPreferencesClampOnDecode() throws {
        let data = Data(#"{"backgroundOpacity":2,"backgroundBlur":-4}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(preferences.backgroundOpacity, 1)
        XCTAssertEqual(preferences.backgroundBlur, 0)
    }

    func testRoundTripAndRecoveryCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        XCTAssertNil(try file.load())
        let first = Ledger()
        try file.save(first, at: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try file.load()?.ledger, first)
        var second = first
        second.categories.append(TimeCategory(name: "Тест", color: .lavender))
        try file.save(second, at: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(try file.load()?.ledger, second)
        XCTAssertEqual(try file.loadBackup()?.ledger, first)
        try Data("broken".utf8).write(to: file.url)
        XCTAssertThrowsError(try file.load())
        // A malformed primary file must never overwrite the valid backup.
        try file.save(second, at: Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(try file.loadBackup()?.ledger, first)
    }

    func testCSVQuotesMultilineTitlesAndEscapesSpreadsheetFormulas() {
        XCTAssertEqual(CSVExport.field("=1+1"), "\"'=1+1\"")
        XCTAssertEqual(CSVExport.field("Задача, \"A\"\nпотом B"), "\"Задача, \"\"A\"\"\nпотом B\"")
        let category = TimeCategory(name: "Работа", color: .mint)
        let start = Date(timeIntervalSince1970: 1000)
        var session = WorkSession(title: "Фокус", categoryID: category.id, mode: .stopwatch, startedAt: start)
        session.finish(at: start.addingTimeInterval(125))
        let csv = CSVExport.sessions([session], categories: [category])
        XCTAssertTrue(csv.contains("\"Работа\""))
        XCTAssertTrue(csv.contains(",125,"))
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
    }
}
