# Todoist Floating

Free menu-bar Pomodoro for Todoist. Pick a task, start a session, get an always-on-top floating card with the task name, countdown and a water wave filling up as time passes.

## Build (macOS)

    brew install xcodegen
    xcodegen generate
    xcodebuild -scheme TodoistFloating -configuration Debug -derivedDataPath build build
    open build/Build/Products/Debug/TodoistFloating.app

Core logic lives in `Packages/TodoistCore` (shared with the future iOS app): `cd Packages/TodoistCore && swift test`.

## Setup

Menu bar timer icon → Settings… → paste a personal API token from https://app.todoist.com/app/settings/integrations/developer.

## Roadmap

- OAuth (PKCE public client with a GitHub-Pages hosted client metadata document)
- iOS (same core, Live Activity countdown)
- Android (Kotlin port of the 3 API calls + timer)
