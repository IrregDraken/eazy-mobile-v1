# Eazy Mobile V1 — Store Release Checklist

**Status:** NOT READY FOR SUBMISSION
**Last reviewed:** 2026-10-10
**Rule:** Do not submit either store listing until every required evidence item is attached and approved.

## Shared legal, privacy and support gates

Business identity is confirmed, but policy approval, professional review, mailbox receipt, provider access and publication remain open.

- [x] Official operator/business identity, registration RC 2962026 and address are confirmed: Thony Dynamic Enterprises, 125/130 Nnamdi Azikiwe Street, Idumota, Lagos Island, Lagos State, Nigeria. Jurisdiction/policy approval remains open.
- [x] Anthony is the authorized policy approver and initial privacy/deletion overseer; no DPO/DPCO/professional reviewer has been designated.
- [ ] Lawyer/DPO/DPCO review completed for privacy notice, terms, community guidelines, payment/refund terms and deletion process.
- [ ] Public HTTPS pages published and tested: `/privacy`, `/terms`, `/cookies`, `/support`, `/delete-account`, `/community-guidelines`, `/payments-refunds`, `/security`.
- [ ] Public domain DNS and hosting verified for `eazy.name.ng`; current public DNS-over-HTTPS queries return no A record, so this remains open.
- [ ] In-app privacy and terms links added and tested.
- [ ] In-app account deletion tested; current Settings flow calls the existing authenticated deletion service.
- [ ] Public deletion request URL works without authentication and explains identity verification, deletion scope, retention exceptions and expected timing.
- [ ] `support@eazy.name.ng`, `privacy@eazy.name.ng`, `legal@eazy.name.ng` and `security@eazy.name.ng` have approved inbound mailbox or forwarding configurations. Resend sender verification alone does not prove inbound mail delivery.
- [ ] Support escalation SLA, moderation SLA, privacy-request procedure and security disclosure procedure approved.

## Google Play

### Policy and declarations

- [ ] Complete Data Safety form from the verified data inventory and enabled-provider configuration.
- [ ] Complete account/data deletion questions and add the public deletion URL.
- [ ] Disclose Firebase, Resend, Supabase, Railway, payment, push, location, translation and AI providers only where actually enabled.
- [ ] Declare financial features accurately, including payment initiation, wallet/ledger, transfers, bank features, fees, refunds and provider responsibility.
- [ ] Provide Terms/community policy acceptance before users create or upload UGC.
- [ ] Verify in-app report and block flows, moderation intake, filtering, enforcement and appeals.
- [ ] Provide published contact information and reviewer instructions for UGC moderation.
- [ ] Complete content rating, target audience, age-screen and sensitive-content declarations.
- [ ] Confirm whether the app is eligible for financial-services or other restricted-policy review.

### Android build and native verification

- [ ] Use Flutter/Android SDK environment; current execution environment has no `flutter`, `dart`, `adb` or `sdkmanager`.
- [ ] Resolve dependencies: `flutter pub get`.
- [ ] Analyze: `flutter analyze`.
- [ ] Run mobile tests: `flutter test`.
- [ ] Build release artifact: `flutter build appbundle --release` with approved production configuration.
- [ ] Confirm effective target API is Android 16/API 36 or higher for new apps and updates submitted from 2026-08-31.
- [ ] Configure `android/key.properties` outside Git and verify the AAB certificate fingerprint is the authorized release certificate, not debug.
- [ ] Install on representative Android devices and test auth, email verification, profile editing, permissions, deletion, UGC report/block, payments in test mode, network interruption, text scaling and keyboard/small screens.
- [ ] Verify Firebase Google sign-in, FCM/push, camera/QR, location and photo permissions on devices.

### Listing and reviewer access

- [ ] App name, short/full description, category, icon, feature graphic, screenshots and privacy URL approved.
- [ ] Reviewer account and test data are safe, non-financial or sandbox-only, and documented.
- [ ] No live payment or transfer credentials are included in reviewer materials.
- [ ] Store listing claims match actual enabled providers and capabilities.

## Apple App Store

### Privacy and account

- [ ] Add privacy-policy URL in App Store Connect and in-app accessible location.
- [ ] Complete App Privacy nutrition labels from the verified data inventory.
- [ ] Explain collection, use, sharing, retention/deletion and consent withdrawal accurately.
- [ ] Verify account deletion is available in-app from Settings and does not require contacting support alone.
- [ ] Publish support/contact information for UGC concerns, privacy and security.

### UGC and financial features

- [ ] Implement and test objectionable-content filtering.
- [ ] Implement and test report flow with timely moderation response.
- [ ] Implement and test user blocking.
- [ ] Publish terms/community standards and prohibit illegal, abusive, exploitative and unsafe content.
- [ ] Confirm age rating and any mature-content controls; safest V1 choice may be to prohibit mature/sexual content.
- [ ] Review payment architecture against Apple payment rules and document what is physical goods, digital goods, wallet, transfer or third-party payment functionality.
- [ ] Obtain legal and finance approval for fees, refunds, cancellations, chargebacks and supported territories.

### iOS/native verification

- [ ] Use macOS/Xcode environment; current execution environment has no `xcodebuild`.
- [ ] Run `flutter pub get`, `flutter analyze`, `flutter test` and `flutter build ipa`/archive.
- [ ] Configure Apple signing, provisioning, entitlements, push capability and Sign in with Apple Service ID/team/key/redirect.
- [ ] Test email, Google and Apple sign-in on real devices.
- [ ] Test camera, location, photo, notification permission grant/deny/retry and fallback behaviour.
- [ ] Verify small screens, keyboard, text scaling, VoiceOver/accessibility and app restart/session revocation.

### Listing and review notes

- [ ] App name, subtitle, description, category, age rating, screenshots, support URL, privacy URL and review notes approved.
- [ ] Reviewer credentials and non-live test scenario supplied.
- [ ] Explain optional provider-unavailable states honestly; do not claim live chat, live payments, translation, location or Assist availability unless enabled and tested.

## Evidence classification

### Completed and tested in available environment

- Backend build and TypeScript lint.
- Backend suite: 189 passed, 0 failed, 1 skipped real-database test (190 tests total).
- Reply-To configuration validation and Resend request-body tests.
- Source-level account-deletion, permissions, release-signing safety and profile-editor wiring.
- Internal legal drafts, data inventory and operations runbooks.

### Implemented but not verified end to end

- Flutter profile editor and Settings → Help & support flow.
- Reply-To delivery through the live Resend account.
- In-app report/block/filter behaviour on physical devices.
- Provider-backed authentication, notifications, storage, payments, translation, location and Assist.

### Blocked by missing tooling

- Flutter/Dart analysis and test execution.
- Android dependency resolution, target API inspection, signed AAB and device tests.
- iOS dependency/build/archive and device tests.

### Waiting for product-owner decisions

- Legal identity, jurisdictions, approved policy text and retention schedule.
- Support/privacy/security mailbox ownership and SLAs.
- Age rating, content policy, payment/refund scope and financial disclosures.
- Reviewer account and test-data policy.

### Waiting for external account/provider access

- Firebase native configuration and real auth.
- Resend sender/delivery and inbound mailbox routing.
- Supabase deployed schema/RLS/storage.
- Paystack test account/webhooks/reconciliation.
- FCM/APNs, translation, location and AI provider configuration.

### Requires explicit production authorization

- DNS changes.
- Railway environment changes or deployment.
- Live payment/transfer enablement.
- Production database deletion/RLS testing or restoration.
- Credential rotation/revocation.
- Store submission.
