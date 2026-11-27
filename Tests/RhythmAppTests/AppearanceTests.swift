import AppKit
import SwiftUI
import XCTest
@testable import Rhythm

final class AppearanceTests: XCTestCase {
    @MainActor
    func testSystemRestoresInheritedAppearanceAfterBothOverrides() async throws {
        let app = NSApplication.shared
        let previous = app.appearance
        defer { app.appearance = previous }
        app.appearance = nil
        let system = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let hosting = NSHostingView(rootView: Text("time_"))
        panel.contentView = hosting

        for (preference, expected) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua), ("light", .aqua)] {
            AppAppearance.apply(preference, to: app)
            XCTAssertEqual(app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            AppAppearance.apply("system", to: app)
            XCTAssertNil(app.appearance)
            XCTAssertNil(panel.appearance)
            XCTAssertEqual(app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), system)
            XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), system)
            XCTAssertEqual(hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), system)
        }
    }
}
