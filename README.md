# time_

A menu bar timer and daily planner for macOS. Requires macOS 14 or later and a Mac with Apple Silicon.

**[Download time_ for Mac](https://github.com/dd0d/time_/releases/latest/download/time_-macOS-arm64.zip)** · [Release notes and SHA-256](https://github.com/dd0d/time_/releases/latest)

## Install

1. Unzip the download and move `time_.app` to Applications.
2. Open time_. Click the circle in the menu bar or press **Control-Option-Space** to open the panel.

The app has an ad hoc signature and is not notarized. If macOS blocks it as an app from an unidentified developer, you can build it locally. If you trust the downloaded copy, Apple documents how to approve it in [Privacy & Security](https://support.apple.com/en-us/102445).

## Use time_

- Click the circle in the panel to start, pause, or resume. The square stops the timer and saves the session.
- Click the time to choose a countdown, stopwatch, or Pomodoro. Click the task name to set a title or category.
- Open **Daily Plan** with **Command-2**. Tasks can repeat daily, and time goals are optional.
- Open **History** to see sessions and daily totals. **Analytics** shows activity over time and totals by category.
- Change the theme, accent color, transparency, menu bar icon, sounds, notifications, idle threshold, and Pomodoro intervals in **Settings**.

## Data

time_ runs locally. Tasks and sessions are stored in `~/Library/Application Support/Rhythm/ledger.json`. Settings has CSV export and JSON backup. Updating preserves existing task and category names.

## Build

Install Xcode or Command Line Tools with Swift 6.

```sh
zsh Scripts/test.sh
zsh Scripts/build.sh
```

Open `dist/time_.app` after building. The build also creates a ZIP and SHA-256 checksum. See [RELEASE.md](RELEASE.md) for publishing.
