# Eazy V1 Production Release

## Implemented
- Firebase email/password, Google, and Apple authentication flows in the Flutter client.
- Authenticated API sessions and onboarding against the configured Eazy API.
- Social feed, posting, media upload boundary, and engagement.
- Marketplace, cart, orders, Paystack initialization and verification flows.
- Wallet transfer/receive flows with provider-unavailable states when configuration is missing.
- Direct chat, replies, reactions, edit/delete, reports, translation boundary, and realtime fallback.
- Eazy Assist sessions/messages with an explicit unavailable state when no AI provider is configured.
- In-app notifications, preferences, push-device registration, settings, block management, and session revocation.
- Secure token storage and production error mapping.

These are implementation statements, not confirmation that every third-party provider has been enabled or tested in production.

## Verified CI baseline
The GitHub Actions run [38110972234](https://github.com/IrregDraken/eazy-mobile-v1/actions/runs/38110972234) completed successfully for the Firebase configuration commit: Flutter analysis/tests, Android **debug** build smoke test, and backend build/lint/tests passed. The optional real Supabase Storage job was skipped. This workflow does not build or archive iOS, and Android release signing is only attempted when signing secrets are configured.

## Current native configuration findings
- Android includes `android/app/google-services.json` for Firebase project `eazy-24e6a` and package `com.eazy.app`.
- `ios/Runner/GoogleService-Info.plist` is now present on the validation branch. Its Firebase project (`eazy-24e6a`) and bundle ID (`com.eazy.app`) were checked, and `ios/Runner.xcodeproj/project.pbxproj` includes it in the Runner Resources build phase. This verifies repository wiring, not a successful native iOS build.
- iOS archive/signing, Apple Sign-In capabilities, and APNs have not been verified by the Linux Android CI workflow.
- Android release signing is conditional on repository signing secrets. The previously passed build was an unsigned debug smoke build, not a signed release APK.
- The client defaults to `https://eazy-mobile-v1-production.up.railway.app/v1`; verify that this is the intended V1 production backend before a store build.

## Required production configuration
No private provider credentials should be committed.

Dart build definitions:
- `EAZY_API_URL`
- `GOOGLE_SERVER_CLIENT_ID`
- `APPLE_SERVICE_ID`
- `APPLE_REDIRECT_URI`

Native Firebase and identity:
- Run a native iOS build on macOS to verify CocoaPods resolution, Firebase initialization, Apple signing/provisioning, and archive generation. A Flutter-compatible `ios/Podfile` has now been added to the validation branch with iOS 15.0 deployment settings. It has not yet been executed by CocoaPods or validated by an Xcode build, so the macOS build remains the proof point.
- Confirm Android Firebase app configuration and signing-certificate fingerprints for the release key.
- Configure Google OAuth client IDs for Android and iOS.
- Configure Apple Sign-In Service ID, Team ID, key, redirect URL, Firebase provider, and iOS capability.
- Configure APNs and validate push delivery on a physical iOS device.

Backend/provider configuration:
- `DATABASE_URL`
- `SUPABASE_PROJECT_REF`
- `MEDIA_BUCKET`
- Paystack production credentials and verified webhooks
- AI provider base URL, API key, and model
- Translation provider credentials
- HERE/location credentials
- Resend sender/domain and API credentials
- Firebase Admin / FCM production configuration

## Release gate
1. Confirm the Railway API URL and database/storage targets match the intended production environment.
2. Add and verify native Firebase configuration for Android and iOS.
3. Configure and test Google and Apple sign-in on the target platforms.
4. Configure backend production providers and validate webhook signatures.
5. Run `flutter pub get`, `flutter analyze --no-fatal-infos`, and `flutter test`.
6. Build a signed Android release APK/AAB with production Dart defines and the production keystore.
7. Build and archive iOS on macOS with the correct bundle ID, signing, APNs, and Firebase configuration.
8. Exercise authentication, onboarding, feed/media, marketplace checkout, wallet transfers/receiving, chat/realtime, notifications, Assist, translation, and location on physical devices.
9. Verify provider health and release/privacy requirements before store submission.

A green CI run is not proof of store readiness. Do not mark signing, iOS archiving, production provider verification, or the optional real Supabase Storage integration complete until each has actually been run and checked.
