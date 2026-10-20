# BitChord for iOS

This is an initial iOS port, not yet a feature-complete Android replacement.
It bundles the existing `web/app` screens, data parsing, queue and lyrics in
WKWebView. Native URLSession replaces the browser extension's HTTP transport;
AVPlayer handles audio, interruptions, AirPlay and lock-screen play/pause/seek.
The application does not load its UI from a hosted website.

The first acceptance gate is a successful simulator build and a device playback
test. A signed IPA additionally requires the Apple setup below. An unsigned
archive or simulator `.app` cannot be installed on an iPhone as an IPA.

## What is and is not ported

| Capability | Initial implementation / remaining validation |
| --- | --- |
| Existing Web appearance and screens | Reused directly, with native safe-area layout |
| Exact Android appearance | Not implemented; Android and Web have separate UIs upstream |
| Anonymous home, search, albums, artists, playlists | Shared upstream code, native HTTP; live device verification required |
| YouTube audio | Direct AAC streams through AVPlayer; device playback and long-track validation required |
| Background audio for the current track | Native audio session configured; device lock/interruption validation required |
| Queue, shuffle, repeat, crossfade | Shared foreground logic; transitions while WebKit is suspended are not implemented |
| Lock-screen play/pause/seek and AirPlay | Native implementation; device verification required |
| Lock-screen next/previous | Disabled until the queue moves into the native host |
| Lyrics, artwork, HTTPS addon requests | Shared implementation with native HTTP; provider/device verification required |
| Google / Spotify / Discord accounts | Not implemented; not advertised as supported bridge capabilities |
| SABR-only streams, offline downloads, local files, Automix, Android EQ, Cast, watch integration | Not ported |

YouTube can change stream eligibility independently of this app. A successful
build does not establish that its playback clients still work. Verify a track
past 90 seconds and seek near its end, not only its first few seconds.

## First run on your Mac

Install Xcode 16.4 or later, open it once, accept its licence and install the
iOS platform. Select that Xcode under Settings → Locations → Command Line Tools.
Install Node 22 or later, the pnpm version declared in `web/package.json`, and
XcodeGen (`brew install xcodegen`).

```bash
git clone https://github.com/rtk19/BitChord.git
cd BitChord
git switch ios/port
bash scripts/ios/prepare.sh
open ios/BitChord.xcodeproj
```

Choose the BitChord scheme and an iPhone simulator, then Run. For a physical
iPhone, select your Apple team under Signing & Capabilities and connect the
device. Developer Mode must be enabled on the iPhone for development installs.

Command-line simulator build:

```bash
bash scripts/ios/build.sh simulator
```

Rerun `prepare.sh` after web source changes; `build.sh` alone reuses the prepared
bundle. Generated Xcode files and the bundled web build stay out of Git.

## Signed IPA from your Mac

Register an explicit App ID (default `io.github.rtk19.BitChord`) in Apple
Developer. Use the same identifier throughout Xcode, provisioning and App Store
Connect. The Team ID is the 10-character value under Apple Developer Membership.
Do not put certificates, profiles, passwords or API keys in Git or chat.

```bash
export APPLE_TEAM_ID=YOURTEAMID
export IOS_BUNDLE_ID=io.github.rtk19.BitChord
export IOS_VERSION=0.1.0
export IOS_BUILD_NUMBER=1
bash scripts/ios/prepare.sh
bash scripts/ios/build.sh ad-hoc
```

With your account signed into Xcode, the script uses automatic provisioning.
Ad Hoc needs registered device UDIDs and an appropriate distribution profile.
For TestFlight, create the matching App Store Connect app record, run
`bash scripts/ios/build.sh app-store-connect`, then upload the exported IPA
through Transporter or Xcode Organizer. A TestFlight IPA is installed through
TestFlight after Apple processes it; it is not directly sideloadable.

The signed IPA is `ios/build/export/BitChord.ipa`. Increase `IOS_BUILD_NUMBER`
for every upload. `development` is also available for local development signing.

## GitHub Actions signing

The `iOS` workflow builds a simulator app on pushes and pull requests. It also
supports manual unsigned device archives and signed IPA exports. Signed jobs
are limited to `main`, so pull requests do not receive signing material.

Set repository **Variables**:

| Variable | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID |
| `IOS_BUNDLE_ID` | The registered explicit bundle ID |
| `IOS_AUTO_DISTRIBUTION` | Optional: `ad-hoc` or `app-store-connect` to export signed IPAs automatically on changes pushed/merged to main; default is simulator |

Set repository **Secrets**:

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | Base64 of an Apple Distribution certificate exported with its private key |
| `IOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64 of the profile matching the bundle ID, team, certificate and distribution method |

Export the certificate from Keychain Access or Xcode. Create/download the
distribution profile in Apple Developer. On macOS, `base64 -i file.p12 | pbcopy`
copies a value directly to the clipboard for a GitHub Secret without printing it.
Repeat for the `.mobileprovision` file. An Ad Hoc profile and an App Store
Connect profile are different: install the profile for your selected method.

After merging the port into `main`, open Actions → iOS → Run workflow and choose
`ad-hoc` or `app-store-connect`. Download the `BitChord-iOS-IPA-*` artifact. The
workflow imports signing into a temporary keychain and removes it at the end.
Uploading to TestFlight is a separate step; no Apple account password is needed
by this workflow.

## Upstream releases

After merging into `main`, the `iOS upstream sync` workflow checks the latest
published release of `kushagrasinghx/BitChord` every six hours. It merges that
release into a dedicated automation branch, opens/updates a PR and explicitly
dispatches an iOS simulator build for that branch. This explicit dispatch is
needed because PRs created using `GITHUB_TOKEN` do not trigger normal PR CI.
Enable “Allow GitHub Actions to create and approve pull requests” in the
repository's Actions settings. No personal access token is required.

Clean textual merges are automatic. Conflicts stop the workflow with an error.
Changes to the Web/native boundary may need code changes even after a clean
merge. Review the iOS build and device acceptance checks before merging; full
automatic feature porting is not provided. After configuring signing, set
`IOS_AUTO_DISTRIBUTION` to automatically export a signed IPA when a release
update is merged into main. Uploading that IPA to TestFlight remains separate.

## Device acceptance checklist

- Browse home, search, open an album and play several tracks on Wi-Fi and mobile data.
- Play longer than 90 seconds, seek forward/back, pause/resume and check lyrics timing.
- Lock the device for several minutes, resume from Control Center and unlock.
- Receive a phone call; verify interruption and resumption. Disconnect headphones.
- Change tracks and exercise repeat/shuffle in the foreground. Record background queue limitations.
- Test AirPlay, landscape layout, iPad layout and a cold start without connectivity.
- Confirm unsupported account integrations show an unavailable state, not a login loop.

## Source and licence

The port retains upstream's GPLv3 licence and attribution. Distribute the
corresponding source with any distributed IPA; the branch and build commit
identify that source. See [LICENSE](LICENSE).
