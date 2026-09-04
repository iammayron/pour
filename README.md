# Pour

Pour 25 minutes into a Todoist task.

A free macOS menu bar Pomodoro for Todoist. Pick a task, start a session, and a small always-on-top glass card shows the task, the countdown, and water rising as the time goes by. When it ends you get a sound, a notification, a break, and the session logged as a comment on the task.

## Features

- Menu bar app, no Dock icon. Search and filter your Todoist tasks (Today, Overdue, 7 days).
- Floating card over every app and Space. Liquid Glass on macOS 26, translucent material before that. Wide or compact.
- Blue water fills while you focus, green water drains during the break.
- Pause, +5 min, Complete task, Stop. Right-click the card for the menu.
- Session end: sound, notification, automatic break, `🍅 25 min focus` and `☕ 5 min break` comments on the task.
- Menu bar glyph fills with progress. A cup replaces it during breaks.

## Install

Pour is not signed with an Apple Developer ID yet, so macOS will refuse to open it the first time.

1. Download `Pour.app` from [Releases](https://github.com/iammayron/pour/releases) and move it to `/Applications`.
2. Remove the quarantine flag:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Pour.app
   ```

   Or right-click `Pour.app` → Open, then confirm in System Settings → Privacy & Security → Open Anyway.
3. Open Pour. Click the timer icon in the menu bar → cog → paste your Todoist API token.

Get a token at Todoist → Settings → Integrations → Developer, or open https://app.todoist.com/app/settings/integrations/developer. The token is stored in your Keychain and never leaves your Mac except to talk to Todoist.

## Build from source

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
./scripts/dev-cert.sh      # once: local signing certificate so Keychain stops prompting after rebuilds
xcodegen generate
xcodebuild -scheme Pour -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Pour.app
```

Shared logic lives in `Packages/TodoistCore` (Todoist API client, Keychain, Pomodoro state machine). Run its tests with `cd Packages/TodoistCore && swift test`.

Design source is in `design/` (Claude Design artboards).

## Roadmap

- Signed and notarized builds
- OAuth login (PKCE public client)
- iOS app on the same core, with a Live Activity countdown
- Android
