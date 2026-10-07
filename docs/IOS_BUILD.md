# Eazy iOS build

The repository now includes the Flutter iOS target with:

- Bundle identifier: `com.eazy.app`
- Eazy app icon asset catalog
- Eazy display name
- Camera, photo-library, location, and microphone usage descriptions
- Existing Flutter/Dart feature implementation shared with Android

## Required before the first iOS run

1. In Firebase Console, add an iOS app to project `eazy-24e6` with bundle ID `com.eazy.app`.
2. Download the resulting `GoogleService-Info.plist`.
3. Copy it to `ios/Runner/GoogleService-Info.plist` and add it to the Runner target in Xcode.
4. Configure the Apple, Google, and Firebase providers for the iOS bundle ID.
5. Configure Apple Developer signing and an App ID for `com.eazy.app`.
6. Enable Push Notifications and Background Modes if push delivery is required.

Do not create `GoogleService-Info.plist` by editing the Android JSON; Firebase iOS client metadata is platform-specific.

## Build on macOS

```bash
flutter pub get
cd ios
pod install
cd ..
flutter build ios --release
flutter build ipa --release
```

For App Store distribution, open `ios/Runner.xcworkspace` in Xcode, select the `Runner` target, choose the Apple Team, configure signing, archive, and export the IPA through Organizer.

The current Linux sandbox can validate Flutter/Dart code and generate the iOS project files, but it cannot run Xcode, CocoaPods, Apple code signing, or produce an IPA.
