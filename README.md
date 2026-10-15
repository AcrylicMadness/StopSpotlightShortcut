# Stop Spotlight Shortcut

A menu bar app that turns off the Spotlight shortcut (⌘Space) while you're in a GeForce NOW
game, so a missed Space doesn't pull the game out of focus and leave keys stuck.

## Install

Download the DMG from [Releases](https://github.com/AcrylicMadness/StopSpotlightShortcut/releases),
drag the app to Applications, and turn on **Launch at Login** from its menu. Requires macOS 14
or later.

## Build

Needs Xcode. The Command Line Tools alone don't include `actool`, which compiles the icon.

```sh
./build.sh            # builds build/StopSpotlightShortcut.app (universal)
./build.sh install    # also copies it to /Applications and launches it
```

To make a release DMG, run `./release.sh`. It signs the app with your Developer ID
certificate, notarizes and staples both the app and the DMG, and writes
`build/StopSpotlightShortcut-<version>.dmg`. The script's header explains the one-time
notarization setup. Then:

```sh
gh release create v1.0 build/StopSpotlightShortcut-1.0.dmg --title "Stop Spotlight Shortcut 1.0"
```

## Icon

`Resources/AppIcon.icon` is an Icon Composer document; open it in Icon Composer to edit it.
It's original artwork. Apple's license doesn't allow SF Symbols, or look-alikes, in app icons.
The menu bar item does use the system `gamecontroller` symbol, because in-app UI is what SF
Symbols are licensed for.

## Menu

- **Block ⌘Space**
  - **During Game Sessions** (default): blocks the shortcut only while a game is streaming and
    GeForce NOW is the front app.
  - **Whenever GeForce NOW Is in Front**: ignores session detection. Use it as a fallback if a
    GeForce NOW update ever breaks detection.
  - **Never**: pauses the app.
- The menu bar icon fills in (`gamecontroller.fill`) while the shortcut is blocked.

## How it works

**Session detection.** GeForce NOW streams inside its main process. Browsing the library,
waiting in the queue and playing all look the same from outside the app. Its streaming engine
logs to `~/Library/Application Support/NVIDIA/GeForceNOW/geronimo.log`, though:
`onStreamerConnected:` / `onStreamingBegin` when the video stream connects, and
`nvbStopStreaming(` / `onStreamerDisconnected` when it ends. The app reads new lines once a
second while GeForce NOW is running. These markers were checked against GeForce NOW 2.0.89.154.

**Toggling the shortcut.** The app calls WindowServer's private
`CGSSetSymbolicHotKeyEnabled` for hot key 64 ("Show Spotlight search"). This is the same switch
System Settings flips, but it doesn't edit your saved preferences and it needs no permissions.
The change outlives the process, so the app turns the shortcut back on:
- when you switch to another app,
- when it quits or gets killed with SIGTERM, SIGINT or SIGHUP,
- on its next launch, if it ever crashed while blocking.

If the shortcut is already off in System Settings, the app leaves it alone.

## Limitations

- Only Spotlight's own shortcut is blocked. Shortcuts that launchers like Raycast or Alfred
  register on ⌘Space are not affected, and neither is ⌥⌘Space (Finder search).
- If NVIDIA changes those log messages, detection stops working. When that happens the app
  simply never blocks; it won't leave the shortcut off. The menu shows "GeForce NOW is open, no
  game running" during a game. Switch to **Whenever GeForce NOW Is in Front** until the markers
  are updated in `StreamLogWatcher.swift`.
- It covers the GeForce NOW app, not play.geforcenow.com in a browser.

## License

MIT. See [LICENSE](LICENSE).
