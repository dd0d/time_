import CoreGraphics

enum SystemActivity {
    static func idleSeconds() -> Double {
        // A system counter only; no event tap, keystroke collection or extra process.
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return 0 }
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return seconds.isFinite ? max(0, seconds) : 0
    }
}
