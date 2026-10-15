import AppKit
import Observation
import ServiceManagement

/// Decides when ⌘Space should be blocked and keeps the Spotlight shortcut in sync with that.
@MainActor
@Observable
final class Controller {
    enum Mode: String, CaseIterable, Identifiable {
        case gameSessions
        case whileInFront
        case never

        var id: Self { self }

        var title: String {
            switch self {
            case .gameSessions: "During Game Sessions"
            case .whileInFront: "Whenever GeForce NOW Is in Front"
            case .never: "Never"
            }
        }
    }

    private static let geForceNowBundleID = "com.nvidia.gfnpc.mall"
    private static let modeKey = "mode"
    /// Set while we have the shortcut turned off, so it can be restored after a crash.
    private static let restoreKey = "restoreSpotlightShortcutOnLaunch"

    var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            update()
        }
    }

    private(set) var isBlocking = false
    private(set) var geForceNowRunning = false
    private(set) var geForceNowInFront = false
    private(set) var inSession = false
    private(set) var sessionStart: Date?
    private(set) var logReadable = true
    private(set) var shortcutOffInSettings = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private let watcher = StreamLogWatcher()
    @ObservationIgnored private var geForceNowPID: pid_t?
    @ObservationIgnored private var hasPolled = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var appNapActivity: NSObjectProtocol?

    init() {
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .gameSessions
    }

    func start() {
        if UserDefaults.standard.bool(forKey: Self.restoreKey) {
            SpotlightHotKey.setEnabled(true)
            UserDefaults.standard.removeObject(forKey: Self.restoreKey)
        }

        // React to app switches immediately; the timer covers the log.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func restoreShortcut() {
        guard isBlocking else { return }
        SpotlightHotKey.setEnabled(true)
        isBlocking = false
        UserDefaults.standard.removeObject(forKey: Self.restoreKey)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Couldn't change launch at login: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var headline: String {
        isBlocking ? "⌘Space is blocked" : "⌘Space opens Spotlight"
    }

    var detail: String {
        if !SpotlightHotKey.isAvailable { return "This macOS can't toggle the Spotlight shortcut" }
        if shortcutOffInSettings { return "Spotlight shortcut is off in System Settings" }
        if !geForceNowRunning { return "GeForce NOW isn't running" }
        if !logReadable { return "Can't read GeForce NOW's log to detect games" }
        guard inSession else { return "GeForce NOW is open, no game running" }
        var text = "Playing"
        if let sessionStart { text += " since \(sessionStart.formatted(date: .omitted, time: .shortened))" }
        if !geForceNowInFront { text += " (GeForce NOW in background)" }
        return text
    }

    private func poll() {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.geForceNowBundleID)
            .first { !$0.isTerminated }?.processIdentifier
        if pid != geForceNowPID {
            // On the very first poll GeForce NOW may already be mid-game, so read the whole log;
            // after a (re)launch anything already in it belongs to the previous run.
            if pid != nil { watcher.reset(skipExisting: hasPolled) }
            geForceNowPID = pid
            preventAppNap(pid != nil)
        }
        hasPolled = true
        if pid != nil { watcher.poll() }

        geForceNowRunning = pid != nil
        geForceNowInFront = pid != nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        inSession = geForceNowRunning && watcher.isStreaming
        sessionStart = inSession ? watcher.streamStart : nil
        logReadable = watcher.isReadable
        update()
    }

    private func update() {
        if !isBlocking { shortcutOffInSettings = !SpotlightHotKey.isEnabled }

        let shouldBlock = switch mode {
        case .gameSessions: inSession && geForceNowInFront
        case .whileInFront: geForceNowInFront
        case .never: false
        }

        if shouldBlock, !isBlocking, !shortcutOffInSettings {
            UserDefaults.standard.set(true, forKey: Self.restoreKey)
            if SpotlightHotKey.setEnabled(false) {
                isBlocking = true
            } else {
                UserDefaults.standard.removeObject(forKey: Self.restoreKey)
            }
        } else if !shouldBlock {
            restoreShortcut()
        }
    }

    /// A menu bar app counts as hidden, so App Nap would otherwise stretch the one-second poll
    /// to many seconds. Only needed while there's a GeForce NOW to watch.
    private func preventAppNap(_ prevent: Bool) {
        if prevent, appNapActivity == nil {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Watching for GeForce NOW game sessions")
        } else if !prevent, let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
            self.appNapActivity = nil
        }
    }
}
