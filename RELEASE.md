# time_ 1.7.0

## GitHub release description

time_ now uses English for the interface, notifications, and CSV headings. Existing tasks, category names, and history are preserved.

Requires macOS 14 or later and a Mac with Apple Silicon.

Open `time_-macOS-arm64.dmg` and drag `time_` to Applications. A ZIP is also available. Both the app and disk image are ad hoc signed and are not notarized. See the [install instructions](https://github.com/dd0d/time_/blob/main/README.md#install) for the first launch.

## Publish

1. Push the release commit and tag `v1.7.0`. Match the tag to `CFBundleShortVersionString` in `Resources/Info.plist`.
2. Run the **macOS** workflow on `main` to get the DMG, ZIP, and SHA-256 files. For a local build, run `zsh Scripts/build.sh` followed by `zsh Scripts/make-dmg.sh`.
3. Create a release for `v1.7.0`. Use `time_ 1.7.0` as the title and copy the description above. Attach the packages and their checksums before publishing.
4. Set it as the latest release to update the download link in README.

Keep the DMG and ZIP asset names for future releases. GitHub uses them to resolve the [latest-release download URLs](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases).

```sh
shasum -a 256 -c time_-macOS-arm64.dmg.sha256
shasum -a 256 -c time_-macOS-arm64.zip.sha256
```

The checksums verify the downloads against the published checksum files. They do not identify the developer.
