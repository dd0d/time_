# time_ 1.7.0

## GitHub release description

time_ now uses English for the interface, notifications, and CSV headings. Existing tasks, category names, and history are preserved.

Requires macOS 14 or later and a Mac with Apple Silicon.

Download `time_-macOS-arm64.zip`, unzip it, and move `time_.app` to Applications. The app is ad hoc signed and is not notarized. See the [install instructions](https://github.com/dd0d/time_/blob/v1.7.0/README.md#install) for the first launch.

## Publish

1. Push the release commit and tag `v1.7.0`. Match the tag to `CFBundleShortVersionString` in `Resources/Info.plist`.
2. Use the ZIP and SHA-256 from the GitHub Actions run or build them locally with `zsh Scripts/build.sh`.
3. Create a release for `v1.7.0`. Use `time_ 1.7.0` as the title and copy the description above. Attach both files before publishing.
4. Set it as the latest release to update the download link in README.

Keep the asset name `time_-macOS-arm64.zip` for future releases. GitHub uses it to resolve the [latest-release download URL](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases).

```sh
shasum -a 256 -c time_-macOS-arm64.zip.sha256
```

The checksum verifies the ZIP against the published checksum file. It does not identify the developer. The app bundle is signed ad hoc during the build.
