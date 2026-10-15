import AppKit
import SwiftUI

@main
struct StopSpotlightShortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller)
        } label: {
            Image(systemName: appDelegate.controller.isBlocking ? "gamecontroller.fill" : "gamecontroller")
        }
    }
}

struct MenuContent: View {
    @Bindable var controller: Controller

    var body: some View {
        Text(controller.headline)
        Text(controller.detail)
        Divider()
        Picker("Block ⌘Space", selection: $controller.mode) {
            ForEach(Controller.Mode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        Toggle("Launch at Login", isOn: Binding(
            get: { controller.launchAtLogin },
            set: { controller.setLaunchAtLogin($0) }))
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()

        // Give the shortcut back when killed from the terminal or by an installer, too.
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreShortcut()
    }
}
