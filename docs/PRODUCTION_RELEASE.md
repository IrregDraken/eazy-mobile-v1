# Eazy V1 Production Release

## Implemented
- Firebase email/password, Google, and Apple authentication.
- V2 authenticated API sessions and onboarding.
- Social feed, posting, media upload, engagement.
- Marketplace, cart, orders, Paystack initialization and verification.
- Wallet, transfers, virtual account, and idempotency handling.
- Direct chat, replies, reactions, edit/delete, reports, translation, secured realtime fallback.
- Eazy Assist sessions and messages.
- Translation and explicit location utilities.
- In-app notifications, read state, preferences, and push-device registration.
- Settings, block management, server-side session revocation.
- Secure token storage and production error mapping.

## Required production configuration
No provider secrets are committed.

Dart build definitions:
- EAZY_API_URL
- GOOGLE_SERVER_CLIENT_ID
- APPLE_SERVICE_ID
- APPLE_REDIRECT_URI

Native Firebase:
- Android Firebase application configuration.
- iOS Firebase application configuration and APNs setup.
- Google Sign-In Android/iOS OAuth configuration.
- Apple Sign-In Service ID, Team ID, Key ID and private key on the provider/Firebase side.

Backend/provider configuration:
- DATABASE_URL
- SUPABASE_PROJECT_REF
- MEDIA_BUCKET
- Paystack production credentials and webhooks
- AI provider base URL, API key and model
- Translation provider credentials
- HERE/location credentials
- Resend/email credentials
- Firebase Admin / FCM production configuration

## Release gate
1. Configure Firebase native files and OAuth providers.
2. Configure backend production providers.
3. Run flutter pub get.
4. Run flutter analyze --no-fatal-infos.
5. Run flutter test.
6. Run flutter build apk --release with production Dart defines.
7. Sign the Android artifact with the production keystore.
8. Build and archive iOS on macOS with the production bundle ID, signing, APNs and Firebase configuration.
9. Test authentication, onboarding, feed, media upload, marketplace checkout, wallet deposit/transfer, chat/realtime, notifications, Assist, translation and location on physical devices.
10. Verify provider health before store submission.

CI now performs analysis/tests and an Android release smoke build using generated Android scaffolding. Native credentials and signing material remain deployment secrets and are deliberately not committed.
