# Eazy Launch Readiness Progress

Branch: `work/eazy-launch-readiness`
Base: `main` at `11cd49b8c35664eaf8bbaabc10cdb96656931cab`
Scope: the owner-provided launch-readiness execution prompt only.

## Rules / execution notes
- One item at a time, in the prescribed order.
- No item is DONE without a code change (where applicable) and verification evidence.
- Missing credentials, external approvals, or unavailable test infrastructure are BLOCKED with the exact unblock requirement.
- No secrets, production keys, or fabricated data will be committed.
- Apple/iOS credential work is out of scope as directed.
- Suggestions: none recorded yet.

## Phase 0 — Orientation

| Area | Verified repository finding |
|---|---|
| Client | Flutter app, Dart SDK >=3.7, Flutter >=3.29. Dependencies include go_router, Firebase Auth/Messaging, secure storage, HTTP, image_picker, local_auth, QR/scanner. |
| Client entry/navigation | `lib/main.dart`, `lib/app/app.dart`, `lib/app/router.dart`; bottom-tab shell is `lib/features/home/home_shell.dart`. |
| State/network | Feature-local StatefulWidgets/state; shared `ApiClient` in `lib/core/network/api_client.dart`, base URL configurable by `EAZY_API_URL`, token/profile snapshot in Flutter secure storage. |
| Theme | `lib/app/theme/eazy_theme.dart` and `theme_controller.dart`; light/dark themes exist. |
| Media | `lib/core/media/media_service.dart` requests authenticated `media/upload-url`, uploads bytes to signed URL; backend media module and Supabase migrations provide storage integration. |
| Backend | Node 22+, TypeScript, Express 5, PostgreSQL, Firebase Admin, Zod. Source under `backend/src`; scripts: build/lint/test/db:migrate. |
| Backend routing/modules | `backend/src/app.ts`; modules include auth, assist, chat, media, posts/social, marketplace, cart, orders, payments, wallet, ledger, notifications, settings, translation and bank virtual accounts. |
| Database | SQL migrations `backend/migrations/001_initial_schema.sql` through `028_wallet_payment_pins.sql` present. RLS/security and wallet PIN migrations exist. |
| Android | `android/app/src/main/AndroidManifest.xml`, Gradle Kotlin DSL; main activity `MainActivity.kt`; app currently requests INTERNET permission and uses adjustResize. |
| Tests | Flutter tests under `test/`; backend test script exists at `backend/package.json`. |
| CI | `.github/workflows/flutter.yml` exists. |
| Open PRs observed at audit | PR #8 (draft Android release artifact) and PR #1 (draft CI validation). PRs #13/#14 were not in the current open-PR API response. |

### Phase 1 defect map (candidate code locations; root causes to confirm before edits)

| ID | Status | Candidate code to inspect / reproduce |
|---|---|---|
| D1 Photo messages | PARTIAL | `lib/features/chat/chat_page.dart`, `lib/core/media/media_service.dart`, backend `modules/media` and `modules/chat`. Current media service uploads and returns a storage path, but does not expose progress/retry UI. |
| D2 Send money | PARTIAL | `lib/features/wallet/wallet_page.dart`, backend `modules/wallet`, `modules/ledger`; inspect balance validation, PIN gating, transfer transaction and refresh. |
| D3 Home feed | PARTIAL | `lib/features/social/social_page.dart`; feed load has loading/error states, but no explicit cache or pull-to-refresh has yet been verified. |
| D4 Discover | PARTIAL | `lib/features/marketplace/marketplace_page.dart`; inspect empty-state/filter rendering and category selection. |
| D5 Chat preview | TODO | `lib/features/chat/chat_home_screen.dart`; latest-message and realtime refresh logic present; confirm event payload and ordering after send/receive. |
| D6 Eazy Assist | TODO | `lib/features/assist/assist_page.dart`, backend `modules/assist/context.ts`, `service.ts`, `repository.ts`; session bootstrap exists; message ordering, New chat and context need inspection. |
| D7 Bag / Settings loading | TODO | `lib/features/marketplace/cart_page.dart`, `lib/features/settings/settings_page.dart`; Settings currently waits on a remote load before rendering. |
| D8 Android system bars | TODO | `lib/app/app.dart`, `lib/features/home/home_shell.dart`, all route/page scaffolds and `AndroidManifest.xml`; audit safe areas, keyboard and navigation insets. |
| D9 Floating AI orb | TODO | `lib/core/ui/eazy_assist_fab.dart`, `lib/features/home/home_shell.dart`; current FAB is fixed-position and not draggable/scroll-aware. |
| D10 Toasts | TODO | Search all SnackBar/ScaffoldMessenger usage and central navigation lifecycle. |
| D11 Chat visuals | TODO | `lib/features/chat/chat_page.dart`; inspect message bubble, timestamp, attachment layout and header theme contrast. |
| D12 Profile link | TODO | `lib/features/profile/profile_page.dart`; inspect copy-link control constraints. |
| D13 Bottom navigation | TODO | `lib/features/home/home_shell.dart`; selected index is local shell state; verify transitions and duplicate selection. |
| D14 Dialogs | TODO | Search AlertDialog/showDialog/showModalBottomSheet across client; verify opaque surfaces and theme contrast. |
| D15 Appearance/language | TODO | `lib/features/settings/settings_page.dart`, `lib/app/theme/theme_controller.dart`; settings currently models theme as light/dark only. |
| D16 Wallet polish | TODO | `lib/features/wallet/wallet_page.dart`, `wallet_amount_input.dart`, backend wallet/ledger; audit currency formatting and recipient flow. |

### Phase 2 partial implementation noted (not yet functionally verified)
- Settings/account routes, account deletion preflight, notification preferences, wallet PIN routes/migration, cart, seller setup, product discovery, orders, Paystack payment and virtual-account modules, notifications, translation capabilities, QR and wallet ledger modules already exist in some form.
- Presence of files/routes/migrations is not proof of complete or secure behavior. Each item remains subject to code-level inspection and tests in its phase.

### D1 — Photo messages (partial)
- Status: PARTIAL.
- Cause confirmed: `_MessageBubble` rendered every attachment as a generic attachment chip; image URLs were only signed when the user tapped the chip. Composer also showed a generic file icon/name even when a local image path was available.
- Files changed: `lib/features/chat/chat_page.dart`.
- Changes: message image attachments now request a cached signed URL and render inline in the bubble; tapping the image still opens the existing full-screen interactive viewer. Composer shows a local photo thumbnail and the label “Photo”.
- Verification: GitHub file updates succeeded in two commits (`ff016dd`, `01dc02a`); source was re-fetched for edits. A Flutter analyzer/build has not yet been run, so this is not DONE. Upload progress and retry-on-upload-failure are still missing because the current media service uploads synchronously before adding an attachment to the composer.
- Remaining: implement observable upload progress and retryable failed uploads, then run Flutter analyze/tests/build.

### D2 — Send money balance gate (partial)
- Status: PARTIAL.
- Cause confirmed: the review screen displayed the available balance but did not compare the requested amount against it before continuing to device authentication and PIN entry. The backend wallet service already performs an authoritative balance check inside a database transaction and records the two-sided ledger transfer.
- Files changed: `lib/features/wallet/wallet_page.dart`.
- Changes: parse both amount and available balance into integer kobo; reject invalid/zero amounts and amounts above the displayed available balance before showing the review/PIN step; remove mandatory device biometric authentication from this Eazy-user transfer path so the server-verified payment PIN is the authorization; inspect the server response and show success only when transaction status is `succeeded`; refresh wallet state/history after the response.
- Verification: source re-fetched after edits; confirmed backend `WalletService.transferToUser` compares ledger balance against amount in minor units and writes debit/credit entries in one DB transaction. No Flutter analyzer, widget test, backend test, or device test has run yet. Therefore PARTIAL, not DONE.
- Remaining: add automated client test coverage for the kobo comparison and execute CI/device verification.

### D3 — Home feed states (partial)
- Status: PARTIAL.
- Cause confirmed: the feed already had loading, error/retry, and pull-to-refresh states. The no-content state used generic copy and its action inherited the misleading “Try again” label even though it opened the post composer.
- Files changed: `lib/features/social/social_page.dart`.
- Changes: empty feed now says “No posts yet” and its action is explicitly “Create post”. The feed is kept alive inside the existing `IndexedStack`, so tab switching does not dispose and re-trigger its initial shimmer.
- Verification: source inspected and updated through GitHub; `RefreshIndicator`, retained `IndexedStack` page and retry state confirmed in code. Flutter analyzer/widget tests/device check not yet run. PARTIAL until CI and on-device verification.
- Remaining: verify behavior under offline/error and after switching tabs on a device; add/execute tests if existing coverage permits.

### D4 — Discover empty state and filters (partial)
- Status: PARTIAL.
- Cause confirmed: every empty catalogue response used “No products match your search”, even when neither search nor category filter was active. Active filters were not surfaced with a clear action.
- Files changed: `lib/features/marketplace/marketplace_page.dart`.
- Changes: empty unfiltered catalogue now says “No products yet”; filtered empty results retain “No products match your search”. Active search/category criteria are displayed with a “Clear filters” action that clears both and reloads listings.
- Verification: source inspected and updated through GitHub. No analyzer/widget test/device test has run. PARTIAL pending CI and interactive verification.
- Remaining: test search/category combinations, clear action, and no-category mapping behavior.

### Phase 0 completion
- Status: DONE (repository map and Phase 1/Phase 2 candidate locations recorded).
- Files changed: `docs/BUILD_PROGRESS.md` only.
- Verification: GitHub tree for `work/eazy-launch-readiness` enumerated 510 entries; key client/backend manifests, routing, theme, API client, media service, settings, chat, wallet, translation and Android manifest were read. No code changes made in Phase 0.
- Limitation: no local checkout/build/test runtime is available through the connected GitHub interface. Static review and GitHub Actions evidence will be used; commands that cannot be run locally will be explicitly recorded.

## Phase 1 — Defect fixes
All D1–D16: TODO. Begin D1 after this orientation record.

## Phase 2 — Launch features
All S1–S7, C1–C6, L1–L4, F1–F3, E1–E9: TODO. Do not start until Phase 1 is DONE or BLOCKED.

## Phase 3 — Paystack wallet
P0–P11: TODO. Do not start until Phases 1 and 2 are DONE or BLOCKED.

## Phase 4 — Premium visual polish
V1–V5: TODO. Do not start until Phases 1–3 are DONE or BLOCKED.
