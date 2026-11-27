# Publishing a release

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. Create an annotated tag of the form `v<version>` on the release commit. Use the tag annotation for release notes.
2. Push the commit and tag. The [macOS workflow](../.github/workflows/macos.yml) checks the tag, runs tests, builds the app and uploads the verified DMG, ZIP and checksums as `time_-macOS-arm64`. Wait for the run for your tag to pass.
3. Download the artifacts from that run. Publish them with GitHub CLI while authenticated as the release author.

```sh
tag=v1.7.3
run_id=123456789 # The ID in the URL of the successful run for this tag
release_dir=$(mktemp -d)

gh run download "$run_id" --repo dd0d/time_ --name time_-macOS-arm64 --dir "$release_dir"
(
    cd "$release_dir" &&
    shasum -a 256 -c time_-macOS-arm64.dmg.sha256 time_-macOS-arm64.zip.sha256
) &&
gh release create "$tag" --repo dd0d/time_ --verify-tag --notes-from-tag --latest \
    "$release_dir"/time_-macOS-arm64.{dmg,zip} \
    "$release_dir"/time_-macOS-arm64.{dmg,zip}.sha256
```

4. Check the download button in the README after publishing. The DMG it serves should pass verification against the checksum from this release.

```sh
curl --fail --location --output "$release_dir/time_-macOS-arm64.dmg" \
    https://github.com/dd0d/time_/releases/latest/download/time_-macOS-arm64.dmg
(cd "$release_dir" && shasum -a 256 -c time_-macOS-arm64.dmg.sha256)
```

## Developer ID releases

GitHub Actions builds with an ad hoc signature. To ship a notarized release, build from the tag on Apple Silicon with a Developer ID Application certificate and a `notarytool` credentials profile in your Keychain. [Apple's notarization instructions](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

```sh
export TIME_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
export TIME_NOTARY_PROFILE="time_-notary"
zsh Scripts/test.sh
zsh Scripts/build.sh
zsh Scripts/make-dmg.sh
```

Use the verified files in `dist/` for step 3. Update the signing information in both READMEs before tagging a notarized release.
