# MCClose

Close, minimize, hide, or quit windows directly from Mission Control, like Mission Control Plus.

## Usage
Open Mission Control and hover over a window. A ✕ button appears on its top-left corner; click it to close the window.

Keyboard shortcuts act on the hovered window and work only while Mission Control is open:

| Keys | Action |
|---|---|
| ⌘W / ⌥⌘W | Close window / all windows of that app |
| ⌘M / ⌥⌘M | Minimize window / all windows of that app |
| ⌘H / ⌥⌘H | Hide app / hide other apps |
| ⌘Q | Quit app |
| ↩ | Open window |

The menu-bar icon (✕ in a rectangle) lets you disable the app or quit it.

## Install
```sh
./scripts/install.sh      # build, sign, copy to /Applications, start at login
./scripts/uninstall.sh
```
The first time it runs, grant it permission under **System Settings → Privacy & Security → Accessibility**. The app is signed with your Apple Development certificate, so the permission carries over when you rebuild and reinstall.

A LaunchAgent (`~/Library/LaunchAgents/com.joseph.mcclose.plist`) starts it at login and restarts it if it crashes. Choosing **Quit MCClose** from the menu keeps it stopped until the next login.

## How it works
- **Detecting Mission Control:** the Dock exposes an accessibility group with identifier `mc` only while Mission Control is open.
- **Finding thumbnails:** on macOS 27, while Mission Control is open, `CGWindowListCopyWindowInfo` reports each window's *thumbnail* rect as its bounds. The Dock's accessibility tree no longer lists the thumbnails. Layer-0 windows from WindowManager, which draws the hover highlight, are ignored.
- **Actions:** the app matches each thumbnail to the app's AX window using `_AXUIElementGetWindow`, then presses that window's close button.
- **Shortcuts:** a `CGEventTap` handles them and swallows the keys only while Mission Control is open.

Set `MCCLOSE_DEBUG=1` when running the binary to log clicks and close attempts.
