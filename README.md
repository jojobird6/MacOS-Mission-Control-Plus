# MCClose

Close windows straight from macOS Mission Control. Hover over a window thumbnail and click the ✕ button, or hover a running app's Dock icon and click ✕ to quit it. A free, open-source take on [Mission Control Plus](https://www.fadel.io/missioncontrolplus).

## Features
- **✕ button** on the hovered thumbnail closes that window.
- **✕ on Dock icons:** in Mission Control, hovering a running app's Dock icon shows a ✕ that quits the app. Finder is excluded.
- **Keyboard shortcuts** act on the hovered window. They work only inside Mission Control and don't change how these keys behave anywhere else:

  | Keys | Action |
  |---|---|
  | ⌘W | Close window |
  | ⌥⌘W | Close all windows of the app |
  | ⌘M / ⌥⌘M | Minimize window / all app windows |
  | ⌘H / ⌥⌘H | Hide app / hide other apps |
  | ⌘Q | Quit app |
  | ↩ | Open window |

  The shortcuts also work when a Dock icon is hovered. There, they act on the whole app: ⌘W and ⌘M close or minimize all of its windows, and ↩ switches to the app.

- **Windows stay in place while you close several.** Like Chrome's tabs, the rest of Mission Control doesn't jump around after each close. The closed window disappears right away, but the actual close (also quit, minimize and hide) waits until you pause for about 1.5 seconds, move the pointer away from the windows, or leave Mission Control. Hold ⌘ to keep everything in place for as long as you like; the windows rearrange once, when you release ⌘. This needs macOS 14 and the Screen Recording permission. Without them, actions take effect immediately.
- **Menu-bar icon** to turn it on or off and quit. It has no Dock icon.

## Requirements
- macOS 13 or later (tested on macOS 27); macOS 14 or later to keep windows in place
- Xcode or the Swift command-line tools

## Install
```sh
git clone https://github.com/jojobird6/MacOS-Mission-Control-Plus.git
cd MacOS-Mission-Control-Plus
./scripts/install.sh
```
The script builds the app, installs it to `/Applications`, and adds a LaunchAgent. The LaunchAgent starts MCClose at login and restarts it if it crashes.

When prompted, allow MCClose under **System Settings → Privacy & Security → Accessibility**, and under **Screen & System Audio Recording** so windows can stay in place while you close several. The menu-bar icon has a shortcut to that setting.

> **Tip:** If you have an Apple Development or Developer ID certificate, the script signs the app with it, so the Accessibility permission carries over when you reinstall. Otherwise the app is ad-hoc signed, and you may need to allow it again after each reinstall. To choose a specific certificate, set `SIGN_IDENTITY`.

## Uninstall
```sh
./scripts/uninstall.sh
```

## How it works
- **Detecting Mission Control:** the Dock creates an accessibility element (`AXGroup` with identifier `mc`) only while Mission Control is open.
- **Placing the ✕:** while Mission Control is open, macOS reports each window's thumbnail rectangle as its bounds (`CGWindowListCopyWindowInfo`), so the ✕ is drawn over that rectangle. Dock icon positions come from the Dock's accessibility items (`AXApplicationDockItem`).
- **Keeping windows in place:** Mission Control re-lays out as soon as a window closes, and there's no API to stop it. So MCClose waits to take the action and, meanwhile, covers the window's thumbnail with a matching piece of the Mission Control background. It captures that background with ScreenCaptureKit when Mission Control opens, with all app windows excluded. Clicks on a cover are ignored. Apps with unsaved changes ask to save only when the action is actually taken.
- **Taking actions:** close, minimize, and the other actions go through the Accessibility API. Shortcuts use a `CGEventTap` that is active only while Mission Control is open.

Mission Control has no public API, so a future macOS update may break this.

## License
GNU General Public License v3.0. See [LICENSE](LICENSE).
