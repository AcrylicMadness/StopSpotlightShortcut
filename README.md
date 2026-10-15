# Stop Spotlight Shortcut

A menu bar app that turns off the Spotlight shortcut (⌘Space) while you're in a GeForce NOW
game, so a missed Space doesn't pull the game out of focus and leave keys stuck.

## Build and install

Needs only the Xcode Command Line Tools.

```sh
./build.sh            # builds build/StopSpotlightShortcut.app
./build.sh install    # also copies it to /Applications and launches it
```

Turn on **Launch at Login** from its menu once it's in /Applications.

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
