<p align="center">
  <img src="TypeSwitch/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="160" alt="TypeSwitch icon">
</p>

<h1 align="center">TypeSwitch</h1>

<hr>

<p align="center">TypeSwitch is a macOS menu bar utility for switching input methods per app. Choose how each app should behave, set the rule for unconfigured apps, and let TypeSwitch switch to the right input method when the frontmost app changes.</p>

<p align="center">
  <a href="https://swift.org"><img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-orange.svg"></a>
  <a href="https://www.apple.com/macos/"><img alt="Platform" src="https://img.shields.io/badge/Platform-macOS%2014.0+-blue.svg"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-MIT-green.svg"></a>
  <a href="https://github.com/ygsgdbd/homebrew-tap"><img alt="Homebrew" src="https://img.shields.io/badge/homebrew-available-brightgreen.svg"></a>
  <a href="https://github.com/ygsgdbd/TypeSwitch/releases"><img alt="Release" src="https://img.shields.io/github/v/release/ygsgdbd/TypeSwitch?include_prereleases"></a>
  <a href="https://github.com/ygsgdbd/TypeSwitch/pulls"><img alt="PRs Welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

<p align="center"><a href="README.zh-CN.md">简体中文</a> • <strong>English</strong></p>

## Screenshots

![TypeSwitch light appearance showing the main menu and current-app input method strategy](Documentation/Screenshots/en-light.png#gh-light-mode-only)

![TypeSwitch dark appearance showing the main menu and current-app input method strategy](Documentation/Screenshots/en-dark.png#gh-dark-mode-only)

## Features

- **Auto switch per app**: Switch input methods when the active app changes.
- **Current App**: Configure the frontmost app directly at the top of the menu.
- **Unconfigured and Running groups**: Review running apps without rules separately from running apps that already have rules.
- **Configured apps**: Manage saved app rules from the menu bar.
- **Unconfigured Apps rule**: Set the fallback behavior for apps without their own rule.
- **Rule strategies**: Choose `Don't Switch`, `Last Switch`, or a `Specific Input Method`.
- **Unavailable cleanup**: Review rules for missing apps and clear unavailable settings.
- **Switch statistics**: Track successful input method switches per app and clear the counts.
- **Launch at Login**: Start TypeSwitch automatically after login, with a Login Items shortcut when macOS requires approval.
- **Manual update checks**: Use `Check for Updates...` in the menu bar app for manual installs.
- **Quick project access**: Open the GitHub repository from the menu.
- **Keyboard shortcut**: Press `Command + Q` to quit TypeSwitch.

## System Requirements

- macOS 14.0 or later
- Enabled macOS keyboard layouts or input methods
- macOS permissions needed for app activation monitoring, system input method switching, and optional Login Items

## Installation

### Homebrew

```bash
brew install ygsgdbd/tap/typeswitch --cask
```

Update Homebrew installations with:

```bash
brew upgrade typeswitch
```

### Manual Installation

1. Download the latest build from [Releases](https://github.com/ygsgdbd/TypeSwitch/releases).
2. Drag `TypeSwitch.app` to the Applications folder.
3. Launch TypeSwitch and grant any system permissions macOS requests.
4. Use `Check for Updates...` from the menu bar app to check GitHub Releases for future updates.

## Usage

1. Launch TypeSwitch. Its keyboard icon appears in the menu bar.
2. Open the menu and use `Current App` to configure the frontmost app.
3. Use `Unconfigured` to assign rules to running apps that do not have one yet.
4. Use `Running` and `Configured` to review and change existing app rules.
5. For each app, choose `Default`, `Last Switch`, `Don't Switch`, or a specific input method.
6. Use `Unconfigured Apps` to set the fallback rule for apps without their own rule.
7. Check `Unavailable` and `Switches` when you want to clean missing rules or review successful switches.

## Privacy and Permissions

- App rules, the unconfigured-apps rule, and switch statistics are stored locally.
- TypeSwitch has no server-side component in this repository.
- The GitHub link and `Check for Updates...` contact GitHub only when you use them.
- Input method switching uses macOS system input sources.
- Launch at Login uses macOS Login Items, with a LaunchAgent fallback when needed.

## Tech Stack

This project uses:

- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) `1.26.0` for app architecture and state management
- [Sharing](https://github.com/pointfreeco/swift-sharing) `2.9.1` for file-backed shared state
- [Sparkle](https://github.com/sparkle-project/Sparkle) `2.9.4` for manual update checks and appcast support
- [SwifterSwift](https://github.com/SwifterSwift/SwifterSwift) `8.0.0` for Swift extensions
- Point-Free support libraries: CasePaths, Dependencies, and PerceptionCore
- [Tuist](https://github.com/tuist/tuist) for project generation and build configuration

## Development

### Requirements

- Xcode 15.0+
- Swift 5.9+
- macOS 14.0+
- [Tuist](https://github.com/tuist/tuist)
- [ImageMagick](https://imagemagick.org/)
- RTK (`rtk`, required by the screenshot generation script)

### Build Steps

Install Tuist:

```bash
brew tap tuist/tuist
brew install --formula tuist
```

Clone and generate the Xcode project:

```bash
git clone https://github.com/ygsgdbd/TypeSwitch.git
cd TypeSwitch
tuist generate
open TypeSwitch.xcworkspace
```

Run tests:

```bash
tuist test
```

To regenerate the deterministic, privacy-safe README screenshots, grant your terminal or Codex Screen Recording and Accessibility permissions, quit other running TypeSwitch instances, and run:

```bash
./script/generate_readme_screenshots.sh
```

### Release Workflow

Production releases are built by GitHub Actions when a `vX.Y.Z` tag is pushed:

```bash
git tag v0.6.0
git push origin v0.6.0
```

The workflow validates the tag, runs tests, builds a universal macOS app, packages a zip, generates checksums, creates a signed Sparkle `appcast.xml`, publishes a GitHub Release, and updates the Homebrew cask.

## Acknowledgments

TypeSwitch was inspired by:

- [SwitchKey](https://github.com/itsuhane/SwitchKey), an input method switcher for macOS
- The Swift and SwiftUI community
- Contributors and users who shared feedback
