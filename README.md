# NotchMate

A native macOS notch companion built on [OpenNook](https://github.com/twinkling-reality/opennook). It sits in the menu-bar notch, shows the current macOS Now Playing item, and can watch coding agents that opt in through hooks.

## Run

Open `NotchMate.xcodeproj` in Xcode and run the **NotchMate** scheme, or:

```bash
xcodebuild -scheme NotchMate -destination 'platform=macOS' build
```

The app is a menu extra (`LSUIElement`). Hover the notch or press ⌥⌘; to expand. Open Settings from the notch gear or the menu-bar extra.

App Sandbox is off so the MediaRemote Perl helper and agent status files in `~/Library/Application Support` can work.

## Agents

Turn on **Settings → Agents**, then click **Install hooks…**. That is the only time NotchMate writes Claude / Codex / Cursor / Pi config.

Status JSON is watched at:

`~/Library/Application Support/NotchMate/agent-status/`

The reporter script lives at:

`~/Library/Application Support/NotchMate/hooks/notchmate-agent-hook.py`

Compact chrome shows one circular icon per tool. Expanded chrome lists tool, project folder, and state. Icons bounce only when a tool actually reports `approval`.

## Layout

**Settings → Appearance** stores placement and sizes in UserDefaults (`notchmate.layout.*`). Compact slot size and extra width apply immediately. Expanded panel width and edge padding apply on the next launch.
