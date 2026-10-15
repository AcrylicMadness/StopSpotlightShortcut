import Foundation

/// Turns the "Show Spotlight search" system shortcut (symbolic hot key 64, ⌘Space by default)
/// on and off through WindowServer's private API — the same switch System Settings flips, but
/// without touching the user's saved preferences.
///
/// The change is global to the login session and outlives this process, so whoever disables
/// the shortcut is responsible for turning it back on.
@MainActor
enum SpotlightHotKey {
    private static let spotlightSearch: UInt32 = 64

    private typealias IsEnabledFunction = @convention(c) (UInt32) -> Bool
    private typealias SetEnabledFunction = @convention(c) (UInt32, Bool) -> Int32

    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    private static let isEnabledFunction = dlsym(rtldDefault, "CGSIsSymbolicHotKeyEnabled")
        .map { unsafeBitCast($0, to: IsEnabledFunction.self) }
    private static let setEnabledFunction = dlsym(rtldDefault, "CGSSetSymbolicHotKeyEnabled")
        .map { unsafeBitCast($0, to: SetEnabledFunction.self) }

    static var isAvailable: Bool { isEnabledFunction != nil && setEnabledFunction != nil }

    static var isEnabled: Bool { isEnabledFunction?(spotlightSearch) ?? true }

    /// Returns whether WindowServer accepted the change.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        setEnabledFunction?(spotlightSearch, enabled) == 0
    }
}
