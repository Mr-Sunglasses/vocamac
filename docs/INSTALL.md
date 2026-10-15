# Installing VocaMac

VocaMac needs an Apple Silicon Mac (M1 or later) on macOS 14 Sonoma or later. Intel Macs are not supported.

Release and nightly builds are Developer ID signed and notarized by Apple, so macOS opens them without warnings, and permissions carry over when you update.

## Homebrew (recommended)

```bash
brew tap vocahq/vocamac
brew trust vocahq/vocamac
brew install --cask vocamac
```

VocaMac installs to `/Applications/VocaMac.app`. To update:

```bash
brew upgrade --cask vocamac
```

**Still have the old tap?** If you installed from `jatinkrmalik/vocamac`, remove it first, or Homebrew stops with `Cask vocamac exists in multiple taps`:

```bash
brew untap jatinkrmalik/vocamac
brew tap vocahq/vocamac && brew trust vocahq/vocamac && brew install --cask vocamac
```

More in the [Homebrew guide](HOMEBREW.md).

## Download the DMG

1. Download `VocaMac-x.y.z-arm64.dmg` from the [latest release](https://github.com/VocaHQ/vocamac/releases/latest).
2. Open it and drag VocaMac to Applications.
3. Open VocaMac and grant **Microphone**, **Accessibility**, and **Input Monitoring** when asked.

VocaMac checks for updates itself and can install them for you (**Settings → About → Check for Updates**).

## Nightly builds

A nightly build is made from the latest `main` every day at midnight UTC when there are new commits. Use it to try features before they reach a release, and [report what breaks](https://github.com/VocaHQ/vocamac/issues/new/choose). It is signed and notarized like a release, but may contain unfinished work.

With the tap added (see above):

```bash
brew install --cask vocamac-nightly
```

Or download `VocaMac-nightly-*.dmg` from the [nightly release](https://github.com/VocaHQ/vocamac/releases/tag/nightly).

**Settings → About** shows the build date and commit, for example `1.2.0-nightly.20261015+abc1234`. Include it when you report a bug.

| | Release | Nightly |
|---|---|---|
| Made | When a version is tagged | Daily, from `main` |
| Signed and notarized | Yes | Yes |
| Best for | Everyday use | Testing and early feedback |

## Build from source

Needs Xcode (for `xcodebuild`).

```bash
git clone https://github.com/VocaHQ/vocamac.git
cd vocamac
make install
```

This builds VocaMac, installs it to `/Applications`, and opens it. Without a Developer ID certificate the build is ad-hoc signed, and macOS resets Accessibility and Input Monitoring on every rebuild. See [Troubleshooting](TROUBLESHOOTING.md#permissions-keep-resetting-on-source-builds).

`make install-cli` adds two helpers to `~/.local/bin`:

- `vocamac` opens VocaMac in the background. With arguments (`vocamac --list-models --json`) it runs the [command-line transcriber](CLI.md) instead and leaves a running app alone.
- `vocamac-build` rebuilds from source after you pull.

Because these run a development binary from Terminal, macOS may give its permissions to your terminal app rather than to VocaMac.

More for contributors in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Uninstall

Homebrew (`--zap` also removes VocaMac's settings and its Application Support folder):

```bash
brew uninstall --zap --cask vocamac
```

From a source checkout, to remove the app and all its data (models, preferences, caches):

```bash
./scripts/uninstall.sh              # add --keep-build to keep build artifacts
```
