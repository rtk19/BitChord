# BitChord for iOS — test build

This package is self-contained. Node, pnpm, CocoaPods and XcodeGen are **not** required.
Requires Xcode 16.4 or newer and iOS 16.4 or newer.

1. Extract the ZIP and open **BitChord.xcodeproj**.
2. Select the **BitChord** target → **Signing & Capabilities**.
3. Enable **Automatically manage signing** and select your Apple Developer Team.
4. Keep `io.github.rtk19.BitChord` or choose a unique Bundle Identifier if Xcode requests one.
5. Connect your iPhone, enable Developer Mode if requested, select it and press **Run**.

To export an IPA, select **Any iOS Device (arm64)**, then **Product → Archive**.
In Organizer choose **Distribute App → Custom → Debugging** for a registered test device,
or **Release Testing** for an Ad Hoc distribution. Xcode will create/select the certificate
and provisioning profile using your Apple account. Both methods require the destination
device to be registered. Export the resulting IPA. For TestFlight, choose **App Store Connect**.

All visible screens are SwiftUI, with AVPlayer playback, lock-screen controls and AirPlay.
The bundled JavaScript shares catalogue and stream resolution with upstream BitChord.
Favorites and listening history are local to this device. Account sync, offline downloads,
lyrics and Android-specific integrations are not implemented in this preview.
Playback availability depends on YouTube offering a usable AAC stream. Continuous queue
playback while locked still needs a physical-device test; the next track is prepared ahead,
but iOS may suspend the resolver before later tracks are prepared.

Source and build instructions: https://github.com/rtk19/BitChord/tree/ios/port
Original project: https://github.com/kushagrasinghx/BitChord
