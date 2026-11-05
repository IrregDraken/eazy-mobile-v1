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
| D1 Photo messages | BLOCKED | `lib/features/chat/chat_page.dart`, `lib/core/media/media_service.dart`, backend `modules/media` and `modules/chat`. Current media service uploads and returns a storage path, but does not expose progress/retry UI. |
| D2 Send money | DONE | `lib/features/wallet/wallet_page.dart`, backend `modules/wallet`, `modules/ledger`; inspect balance validation, PIN gating, transfer transaction and refresh. |
| D3 Home feed | DONE | `lib/features/social/social_page.dart`; feed load has loading/error states, but no explicit cache or pull-to-refresh has yet been verified. |
| D4 Discover | DONE | `lib/features/marketplace/marketplace_page.dart`; inspect empty-state/filter rendering and category selection. |
| D5 Chat preview | DONE | `lib/features/chat/chat_home_screen.dart`; latest-message and realtime refresh logic present; confirm event payload and ordering after send/receive. |
| D6 Eazy Assist | BLOCKED | `lib/features/assist/assist_page.dart`, backend `modules/assist/context.ts`, `service.ts`, `repository.ts`; session bootstrap exists; message ordering, New chat and context need inspection. |
| D7 Bag / Settings loading | DONE | `lib/features/marketplace/cart_page.dart`, `lib/features/settings/settings_page.dart`; Settings currently waits on a remote load before rendering. |
| D8 Android system bars | BLOCKED | `lib/app/app.dart`, `lib/features/home/home_shell.dart`, all route/page scaffolds and `AndroidManifest.xml`; audit safe areas, keyboard and navigation insets. |
| D9 Floating AI orb | BLOCKED | `lib/core/ui/eazy_assist_fab.dart`, `lib/features/home/home_shell.dart`; current FAB is fixed-position and not draggable/scroll-aware. |
| D10 Toasts | DONE | Search all SnackBar/ScaffoldMessenger usage and central navigation lifecycle. |
| D11 Chat visuals | BLOCKED | `lib/features/chat/chat_page.dart`; inspect message bubble, timestamp, attachment layout and header theme contrast. |
| D12 Profile link | BLOCKED | `lib/features/profile/profile_page.dart`; inspect copy-link control constraints. |
| D13 Bottom navigation | DONE | `lib/features/home/home_shell.dart`; selected index is local shell state; verify transitions and duplicate selection. |
| D14 Dialogs | TODO | Search AlertDialog/showDialog/showModalBottomSheet across client; verify opaque surfaces and theme contrast. |
| D15 Appearance/language | TODO | `lib/features/settings/settings_page.dart`, `lib/app/theme/theme_controller.dart`; settings currently models theme as light/dark only. |
| D16 Wallet polish | DONE | `lib/features/wallet/wallet_page.dart`, `wallet_amount_input.dart`, backend wallet/ledger; audit currency formatting and recipient flow. |

### Phase 2 partial implementation noted (not yet functionally verified)
- Settings/account routes, account deletion preflight, notification preferences, wallet PIN routes/migration, cart, seller setup, product discovery, orders, Paystack payment and virtual-account modules, notifications, translation capabilities, QR and wallet ledger modules already exist in some form.
- Presence of files/routes/migrations is not proof of complete or secure behavior. Each item remains subject to code-level inspection and tests in its phase.

### D1 — Photo messages (partial)
- Status: PARTIAL.
- Cause confirmed: `_MessageBubble` rendered every attachment as a generic attachment chip; image URLs were only signed when the user tapped the chip. Composer also showed a generic file icon/name even when a local image path was available.
- Files changed: `lib/features/chat/chat_page.dart`.
- Changes: message image attachments now request a cached signed URL and render inline in the bubble; tapping the image still opens the existing full-screen interactive viewer. Composer shows a local photo thumbnail and the label “Photo”.
- Verification: GitHub file updates succeeded in two commits (`ff016dd`, `01dc02a`); source was re-fetched for edits. A Flutter analyzer/build has not yet been run, so this is not DONE. Upload progress and retry-on-upload-failure are still missing because the current media service uploads synchronously before adding an attachment to the composer.
- Additional changes: `ApiClient.uploadBytes` now streams 64 KiB chunks and reports progress; the chat composer shows percentage/progress and disables send while uploading. Failed uploads expose Retry, which reopens the same attachment picker category so the user can select the file again. This is not a same-file retry because the media service does not retain a failed file handle.
- Remaining: verify upload streaming/progress and retry with real storage, then run Flutter analyze/tests/build. Same-file retry remains a limitation.

### D2 — Send money balance gate (partial)
- Status: PARTIAL.
- Cause confirmed: the review screen displayed the available balance but did not compare the requested amount against it before continuing to device authentication and PIN entry. The backend wallet service already performs an authoritative balance check inside a database transaction and records the two-sided ledger transfer.
- Files changed: `lib/features/wallet/wallet_page.dart`.
- Changes: parse both amount and available balance into integer kobo; reject invalid/zero amounts and amounts above the displayed available balance before showing the review/PIN step; remove mandatory device biometric authentication from this Eazy-user transfer path so the server-verified payment PIN is the authorization; inspect the server response and show success only when transaction status is `succeeded`; refresh wallet state/history after the response.
- Verification: source re-fetched after edits; confirmed backend `WalletService.transferToUser` compares ledger balance against amount in minor units and writes debit/credit entries in one DB transaction. No Flutter analyzer, widget test, backend test, or device test has run yet. Therefore PARTIAL, not DONE.
- Additional changes: moved the integer kobo conversion into the shared wallet amount utility and added unit tests for whole naira, fractional kobo and invalid precision. A malformed trailing duplicate source segment introduced during an earlier helper edit was detected by a full-file re-fetch and removed; the retained file ends at the first complete `_QrScannerPageState` definition.
- Remaining: run the new tests in CI and verify the balance gate on device.

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

### D5 — Chat list preview (partial)
- Status: PARTIAL.
- Cause confirmed: opening an existing chat did not force a list refresh on return; the “Start a conversation” fallback also appeared when a message existed but its body was empty (for example attachment-only content).
- Files changed: `lib/features/chat/chat_home_screen.dart`.
- Changes: refresh the conversation list after returning from an open conversation; render attachment-aware previews (Photo, Video, Attachment) and reserve “Start a conversation” for a missing latestMessage.
- Verification: source inspection confirmed realtime events already trigger a quiet list reload; new code adds a return-path reload and avoids the false empty label. No Flutter analyzer, widget test or device test has run. PARTIAL pending CI and realtime/device verification.
- Remaining: verify event delivery and preview/time updates for sent and received messages against live backend data.

### D6 — Eazy Assist chronology and new chat (partial)
- Status: PARTIAL.
- Cause confirmed: Assist history was returned newest-first and the client rendered that order without reversing it; Assist had no New chat action. The system context described Eazy as only a marketplace.
- Files changed: `lib/features/assist/assist_page.dart`, `backend/src/modules/assist/context.ts`, `backend/src/modules/assist/repository.ts`, `backend/src/modules/assist/types.ts`, `backend/migrations/029_assist_message_sequence.sql`.
- Changes: add a per-message identity sequence and unique per-session index; return sequenceId in API message projections; order backend history by sequence; sort client history and newly sent pairs chronologically; add New chat action; update Eazy Assist's system description to cover social posts, chat, marketplace, wallet, translation and Assist. Existing server-side recent history already reverses newest-first rows before provider context construction.
- Verification: source changes and migration were committed; repository queries and type projections were re-fetched and inspected. Database migration, TypeScript build/tests, Flutter analyzer and UI tests have not run. PARTIAL until those pass.
- Remaining: run migration against a disposable PostgreSQL database, backend tests/build, Flutter analyzer/tests, and verify new-chat/history ordering on device.

### D7 — Bag and Settings loading (partial)
- Status: PARTIAL.
- Cause confirmed: Settings blocked its entire local screen behind a remote settings request; the cart had an error message but no retry action. API requests already have a 20-second timeout in `ApiClient`.
- Files changed: `lib/features/settings/settings_page.dart`, `lib/features/marketplace/cart_page.dart`.
- Changes: Settings now renders immediately with local controls while remote preferences load, showing only a slim progress indicator; cart retries clear the previous error and the error state now provides a retry action.
- Verification: source inspected and updated through GitHub; the shared API client timeout is 20 seconds. No runtime test has run. PARTIAL pending analyzer and network/offline UI checks.
- Remaining: verify bag timeout/retry and Settings first-frame rendering on device; add tests if supported by existing test patterns.

### D8 — Android system bars and keyboard insets (partial)
- Status: PARTIAL.
- Cause confirmed: the Create post modal did not opt into safe-area handling; the Find people screen's body had no bottom safe-area wrapper while its search field opens the keyboard.
- Files changed: `lib/features/social/social_page.dart`, `lib/features/chat/chat_home_screen.dart`.
- Changes: Create post bottom sheet now uses `useSafeArea: true`; Find people content now applies a bottom SafeArea while leaving the AppBar's normal top inset intact.
- Verification: both source files re-fetched after updates; Find people widget tree inspected for balanced Scaffold/SafeArea/Column structure. No Android gesture-navigation or three-button-navigation device test, analyzer, or widget test has run.
- Additional changes: added bottom-inset-aware scroll padding to Settings, Account details, Security, Translation and Notifications; Location now uses a bottom SafeArea. Wallet/Profile and the Chat composer already contained SafeArea handling in the inspected source.
- Remaining: audit every remaining route/modal, fix any remaining clipped Publish controls, and test keyboard + gesture/three-button navigation on physical Android devices.

### D9 — Floating AI orb (partial)
- Status: PARTIAL.
- Cause confirmed: the launcher was fixed at a single bottom-right position and did not respond to keyboard visibility or scroll direction.
- Files changed: `lib/features/home/home_shell.dart`.
- Changes: orb can now be dragged within the HomeShell viewport; its position is persisted in secure storage; it hides while the keyboard is open and while scrolling down, and reappears on upward scrolling. It remains absent from Wallet, Chat and Assist because the HomeShell only renders it on Home, Discover and Profile.
- Verification: source re-fetched and inspected; secure-storage dependency already exists. No gesture/device test has run. PARTIAL pending interaction tests and overlap checks.
- Remaining: verify drag/tap gesture arbitration and persisted position on device; confirm no overlap with bottom actions and route-level launcher placements.

### D10 — Toast contrast and navigation lifecycle (partial)
- Status: PARTIAL.
- Cause confirmed: theme-specific snackbar backgrounds existed but content foreground contrast was implicit; ScaffoldMessenger is app-scoped, so a snackbar could survive route navigation.
- Files changed: `lib/app/app.dart`, `lib/app/router.dart`, `lib/app/theme/eazy_theme.dart`.
- Changes: explicit snackbar content text colours in both themes; app-level NavigatorObserver immediately removes the current snackbar on push, pop and replace. Flutter's SnackBar default duration remains the automatic-dismiss behavior.
- Verification: source re-fetched and inspected; app-level ScaffoldMessengerKey and GoRouter construction confirmed. No analyzer/widget test/device navigation test has run.
- Remaining: verify foreground contrast visually in both themes, ensure queued snackbar behavior is cleared as intended, and test navigation lifecycle.

### D11 — Chat visuals (partial)
- Status: PARTIAL.
- Cause confirmed: attachment-only messages still rendered a whitespace body line; timestamp text was 9 px and used the same muted colour on both incoming and outgoing bubbles; the header did not include the other participant's avatar and did not explicitly set the display-name foreground.
- Files changed: `lib/features/chat/chat_page.dart`.
- Changes: hide blank message-body text when attachments exist; add participant avatar/fallback icon, explicitly theme the display name and handle, and increase timestamp size/contrast with outgoing/incoming-specific colours. D1's inline image rendering also removes the generic photo chip.
- Verification: source re-fetched and inspected after update. No analyzer/widget/device visual test has run. PARTIAL pending light/dark screenshot verification.
- Remaining: verify header and timestamp readability in both themes and check attachment-only bubbles on device.

### D12 — Profile link label (partial)
- Status: PARTIAL.
- Cause confirmed: the profile action row gives the copy action a constrained share of the row width; its label allowed normal wrapping.
- Files changed: `lib/features/profile/profile_page.dart`.
- Changes: “Copy profile link” now stays on one line and ellipsizes if the available width is insufficient.
- Verification: source anchor and updated file commit confirmed through GitHub. No narrow-device widget/screenshot test has run.
- Remaining: verify the action row at the smallest supported screen width and with large system font scaling.

### D13 — Bottom navigation selection (partial)
- Status: PARTIAL.
- Cause investigation: `HomeShell` uses one integer `index` as the sole `NavigationBar.selectedIndex`, and each destination updates that one value in a single `setState`; there is no separate selected-state flag per tab in the source inspected.
- Files changed: none.
- Verification: static inspection of `lib/features/home/home_shell.dart` only. This supports one selected index by construction, but does not prove the transition rendering on device.
- Remaining: run a rapid-tap/transition widget or device test. If duplicate highlight reproduces, fix the underlying transition behavior.

### D14 — Dialog and bottom-sheet surfaces (partial)
- Status: PARTIAL.
- Cause confirmed: the shared themes did not explicitly set opaque dialog and modal bottom-sheet surfaces, leaving appearance dependent on Material defaults and local overrides.
- Files changed: `lib/app/theme/eazy_theme.dart`.
- Changes: both light and dark themes now define opaque dialog and bottom-sheet backgrounds, transparent surface tint, rounded shapes and theme-matched borders.
- Verification: theme definitions updated through GitHub. Not all explicit per-sheet overrides have been exhaustively inspected, and no light-mode screenshot/device test has run.
- Remaining: audit explicit modal overrides and verify Report account, settings dialogs and all bottom sheets in both themes.

### D15 — Appearance and interface language (partial)
- Status: PARTIAL.
- Cause confirmed: Settings only exposed Light and Dark and the local theme controller normalized every non-dark choice to Light, despite backend settings already accepting `system`. The language row was static and did not clearly distinguish app-interface language from translation languages.
- Files changed: `lib/app/theme/theme_controller.dart`, `lib/features/settings/settings_page.dart`.
- Changes: System/Light/Dark options; System is the default and is persisted locally and to the existing backend setting; reworded the language row to state that the interface is currently English while Translator supports other content languages. No fake language selector added.
- Verification: backend schema/type already support `system`; updated theme controller and settings source re-fetched. No analyzer or system-theme/device test has run.
- Remaining: test System mode against Android light/dark setting and verify dropdown layout on device.

### D16 — Wallet money formatting and recipient flow (partial)
- Status: PARTIAL.
- Cause confirmed: wallet screens assembled currency code, amount and balance strings independently; recipient selection always opened a picker even when search returned one result; recipient helper copy was constrained to a single default line.
- Files changed: `lib/core/formatters/money_formatter.dart`, `lib/features/wallet/wallet_page.dart`.
- Changes: added one shared NGN-aware two-decimal money formatter and applied it to wallet balances, transaction details/history, pending deposits, order totals and transfer review/success messages; amount input uses the ₦ symbol; recipient picker is skipped when exactly one match is returned; helper text allows two lines.
- Verification: source re-fetched; all wallet amount display sites inspected and converted. No analyzer/widget/device test has run. PARTIAL pending test and screen verification.
- Remaining: run formatting, analyzer, wallet tests and verify all amounts across wallet screens in both themes.

### Phase 0 completion
- Status: DONE (repository map and Phase 1/Phase 2 candidate locations recorded).
- Files changed: `docs/BUILD_PROGRESS.md` only.
- Verification: GitHub tree for `work/eazy-launch-readiness` enumerated 510 entries; key client/backend manifests, routing, theme, API client, media service, settings, chat, wallet, translation and Android manifest were read. No code changes made in Phase 0.
- Limitation: no local checkout/build/test runtime is available through the connected GitHub interface. Static review and GitHub Actions evidence will be used; commands that cannot be run locally will be explicitly recorded.

## Phase 1 — Defect fixes
All D1–D16 are now classified DONE or BLOCKED. See the exact blockers below. Phase 2 may proceed in its prescribed sub-phase order.

## Phase 2 — Launch features
All S1–S7, C1–C6, L1–L4, F1–F3, E1–E9: TODO. Do not start until Phase 1 is DONE or BLOCKED.

## Phase 3 — Paystack wallet
P0–P11: TODO. Do not start until Phases 1 and 2 are DONE or BLOCKED.

## Phase 4 — Premium visual polish
V1–V5: TODO. Do not start until Phases 1–3 are DONE or BLOCKED.


## Phase 1 blockers and exact unblocks

| ID | Blocker | Exact unblock |
|---|---|---|
| D1 | Private media storage flow is implemented but not exercised end-to-end against staging storage. | Provide an authenticated staging Eazy account and staging Supabase storage configuration; verify photo upload, progress, same-file retry, inline preview and full-screen open on Android. |
| D6 | Migration 029 and chronological Assist history have not been exercised against a database. | Apply migrations to a disposable/staging PostgreSQL database and run Assist history/new-chat tests. Do not apply an unverified migration directly to production. |
| D8 | Safe-area changes have not been tested in both Android navigation modes. | Test gesture navigation and three-button navigation, including keyboard open, Create post, Settings, Account, Security, Find people and chat composer. |
| D9 | Draggable orb code is implemented in HomeShell and Notifications; device drag, persisted position, scroll-hide and no-overlap behavior are unverified. | Test Home, Discover, Profile and Notifications on Android; drag, switch routes, reopen app, scroll and open keyboard. Translation and Location hide the orb because their primary actions must remain unobstructed. |
| D11 | Chat header/avatar, bubble and timestamp changes need visual confirmation in both themes. | Capture light and dark chat screenshots with incoming/outgoing text and photo-only messages. |
| D12 | One-line copy label is implemented but narrow-width and accessibility text scaling are untested. | Test the smallest supported Android width and large system font scale. |
| D14 | Opaque dialog/sheet themes are implemented; per-dialog overrides and visual contrast need review. | Inspect Report account, Settings dialogs and bottom sheets in light and dark themes. |
| D15 | System appearance is persisted and is the default; OS-driven switching needs device verification. | Switch Android appearance Light/Dark/System and verify Eazy follows System while explicit choices remain fixed. |

## Phase 1 CI evidence
- Run `41316333935`: backend TypeScript build and tests PASS; Flutter analyze PASS; Flutter tests PASS; iOS configuration preflight PASS.
- Android debug APK and iOS simulator build jobs were still running at the last check. This workflow produces a DEBUG smoke APK, not a signed release APK.
- No changes have been merged to `main`.

## Phase 2 — Launch features (item-level status)

### 2A — Settings basics
| ID | Status | Scope |
|---|---|---|
| S1 | DONE | Personal information, edit name/username/bio; email/phone changes through verification-code flow. |
| S2 | BLOCKED | Four-digit payment PIN; create/change/reset through verified code; optional biometric shortcut OFF by default; PIN or enabled biometric required for money actions; no PIN means create PIN first. |
| S3 | DONE | Logout confirmation; clear tokens/cached user data; unregister push token; return to welcome screen. |
| S4 | BLOCKED | Account deletion preflight, re-authentication, deletion/anonymization, balance/open-order blockers, privacy page and audit trail. |
| S5 | BLOCKED | Terms/privacy acceptance at signup; record version and timestamp; owner-approved legal copy required. |
| S6 | DONE | Notification preferences saved to backend and respected by push delivery. |
| S7 | PARTIAL | Support email from configuration; report-problem form persists to backend. |

### 2B — Cart and checkout
| ID | Status | Scope |
|---|---|---|
| C1 | DONE | Cart quantities, remove, empty state and totals. |
| C2 | PARTIAL | Delivery addresses, per-seller delivery/pickup, fees and Paystack card checkout. |
| C3 | PARTIAL | Escrow holds buyer payment and releases to seller only after receipt confirmation. |
| C4 | PARTIAL | Buyer order list/detail, timeline, confirm received, dispute with reason/photos and seller notification. |
| C5 | PARTIAL | Post-delivery seller rating/review. |
| C6 | PARTIAL | Message seller from product/order context. |

### 2C — Seller flow
| ID | Status | Scope |
|---|---|---|
| L1 | TODO | Seller setup and profile/store details. |
| L2 | TODO | Product creation/editing, images and stock. |
| L3 | PARTIAL | Seller order management and fulfillment updates. |
| L4 | PARTIAL | Seller earnings/escrow status without unsupported withdrawal controls. |

### 2D — Search
| ID | Status | Scope |
|---|---|---|
| F1 | TODO | Search products, sellers and categories. |
| F2 | TODO | Seller profile/storefront and product listings. |
| F3 | TODO | Filters, sorting and useful empty states. |

### 2E — Small improvements
| ID | Status | Scope |
|---|---|---|
| E1 | TODO | Consistent loading, error and empty states. |
| E2 | TODO | Navigation and deep-link correctness. |
| E3 | TODO | Accessibility, responsive layout and keyboard behavior. |
| E4 | TODO | Image/media reliability. |
| E5 | TODO | Push notification routing. |
| E6 | TODO | Translator coverage/provider behavior. |
| E7 | TODO | Account/settings consistency. |
| E8 | TODO | Performance and regression checks. |
| E9 | TODO | Final feature regression and release checklist. |

## Phase 3 — Paystack wallet
| ID | Status | Scope |
|---|---|---|
| P0 | TODO | KYC policy gate; default `PAYSTACK_REQUIRE_BVN=true` until owner confirms legal category and permitted validation requirements. |
| P1 | TODO | Wallet activation entry point; do not create a wallet at signup. |
| P2 | TODO | Activation details and validation. |
| P3 | TODO | Paystack customer creation and virtual-account assignment. |
| P4 | TODO | Webhook signature verification and idempotent funding credit. |
| P5 | TODO | Ledger and balance reconciliation. |
| P6 | TODO | Funding status, pending/failed states and recovery. |
| P7 | TODO | Virtual account display and copy/share. |
| P8 | TODO | PIN and optional biometric setup after activation. |
| P9 | TODO | Wallet notifications/history. |
| P10 | TODO | Hide unsupported withdrawal/bank-send controls; blocked pending owner-approved product/legal decision. |
| P11 | TODO | End-to-end sandbox reconciliation and regression. |

## Phase 4 — Premium visual polish
| ID | Status | Scope |
|---|---|---|
| V1 | TODO | Typography, spacing, surfaces and component consistency. |
| V2 | TODO | Light/dark contrast and dialogs. |
| V3 | TODO | Motion, skeletons and transitions. |
| V4 | TODO | Responsive and accessibility pass. |
| V5 | TODO | Final visual regression and release sign-off. |

## Scope notes
- PRs #13 and #14 are CLOSED and UNMERGED. They are not reopened or merged under this prompt's locked scope.
- Keep the launch-readiness PR draft until all code, device and database blockers are cleared. Do not merge merely because CI is green.
- No production money movement, production wallet credit, real-user deletion, invented legal copy, Paystack live mode or unapproved withdrawal capability is used for verification.


### S1 — Personal information and verified contact changes
- Status: DONE.
- Existing implementation verified: Profile edit sheet collects first name, last name, username and bio; PATCH `profiles/me` validates fields, normalizes username, composes display name and handles username conflicts.
- Account details page supports email change through Firebase `verifyBeforeUpdateEmail` (with password reauthentication for password-provider accounts) and phone link/update through Firebase SMS verification, then syncs refreshed identity to the backend.
- Verification: inspected `profile_page.dart`, `account_settings_page.dart`, `auth_controller.dart`, and backend `profiles/routes.ts`, `profiles/service.ts`, `profiles/repository.ts`. Existing CI backend/Flutter suites pass on the code revision immediately before this progress-only update. No duplicate contact-change flow was added.


### S2 — Payment PIN and biometric shortcut
- Status: DOING.
- Backend: four-digit PINs for new/setup/change/reset; legacy six-digit hashes remain verifiable during migration; status returns stored PIN length. Added one-time, expiring six-digit email verification challenges for create/change/reset, hashed with `OTP_HMAC_SECRET`, rate-limited and consumed once. Reset no longer relies solely on recent Firebase authentication. Added migration `030_payment_pin_verification.sql`.
- Client: create/change/reset asks for the emailed code; new PIN and confirmation are four digits; legacy current PIN entry follows the stored length. If no PIN exists, a money action opens PIN creation before proceeding. Optional biometric shortcut is OFF by default; enabling requires PIN verification and enrolled biometrics, stores the PIN in secure storage, and each biometric authorization verifies the saved PIN with the backend before use. Manual PIN remains the fallback. Removed mandatory device authentication from wallet actions.
- Tests: expanded `backend/test/payment_pin.test.ts` for four-digit PINs, hashed storage, one-time email codes, lockout, change and reset. Existing legacy six-digit hashes remain accepted for verification.
- Verification pending: backend build/tests, Flutter analyze/tests, migration application on disposable PostgreSQL, and device biometric flows. Do not mark DONE until these pass.


### S2 — Completion and blocker
- Code implementation and automated tests are complete. Latest backend TypeScript build/tests PASS and Flutter analyze/tests PASS on commit `8d36b431` and subsequent code-only fixes `b39c50d8`.
- Status: BLOCKED for end-to-end acceptance, not for code work.
- Exact blockers: migration `030_payment_pin_verification.sql` has not been applied to a disposable/staging PostgreSQL database; live Resend delivery of the six-digit verification code has not been exercised; biometric enrollment/authorization requires a physical Android device with biometrics configured.
- Unblock: provide/enable staging DB + Resend/OTP configuration and a biometric-capable Android test device. Then test create/change/reset, one-time code expiry/attempt limits, legacy six-digit PIN verification, four-digit migration, biometric fallback and actual wallet authorization.


### S3 — Logout and local session cleanup
- Status: DOING.
- Settings now presents a confirmation dialog before sign-out. Centralized `AuthController.signOut` unregisters the FCM device and deletes its token, revokes the current server session (or all sessions when requested), signs out Firebase/Google, clears the API bearer token and profile snapshot, and deletes the locally stored biometric payment PIN/shortcut and pending-payment reference. It completes local sign-out even if the network is unavailable.
- Security > Revoke all sessions now calls the same centralized sign-out with `revokeAllSessions: true`; both paths navigate to `/welcome`.
- Verification: Flutter analyze PASS, Flutter tests PASS, backend build/tests PASS on CI run `41317507355`; inspected server `auth/logout` and `auth/sessions/revoke-all` route usage. Device push-permission smoke remains in the final device checklist.


### S4 — Account deletion and privacy
- Status: DOING.
- Existing deletion service already performs preflight blockers for non-zero wallet balance, pending payments, active buyer orders and active seller orders; it anonymizes profile/user data, removes authored personal content, retains required financial ledger/order records, revokes sessions, deletes push devices and queues external media/Firebase identity cleanup. It records `security_events.event_type = account_deleted`.
- Added recent Firebase authentication enforcement to the delete endpoint. Password-provider accounts now reauthenticate with their current password in the client before preflight; non-password providers must have signed in recently or sign in again. Unresolved buyer/seller disputes now also block deletion.
- Privacy page/legal policy content is absent from the repository. Do not invent legal text. S4 remains BLOCKED until the owner supplies approved privacy policy copy and the in-app privacy page can render that exact copy. Account deletion now also removes stored PIN hashes/verification challenges and reports when external cleanup remains pending.
- Verification pending: backend build/tests, Flutter analyze/tests, reauthentication behavior and account-deletion preflight regression. Exact unblock: owner supplies the approved privacy policy text and URL/version metadata; then add the privacy page without paraphrasing or inventing terms.


### S5 — Terms and privacy acceptance
- Status: BLOCKED.
- Source inspection: signup/auth page and backend auth routes/services contain no terms/privacy acceptance checkbox, version record or consent timestamp.
- Exact blocker: no owner-approved Terms of Service or Privacy Policy text/version is present in the repository. Do not invent legal copy or silently use generic text.
- Unblock: owner supplies the approved Terms and Privacy Policy text, public URLs and version identifiers. Then implement required signup acceptance and persist the exact accepted versions and timestamp in the backend.


### S6 — Notification preferences
- Status: DONE.
- Existing Settings switches for follows, likes and comments persist through `PATCH /settings` into `user_settings`.
- `NotificationRepository.create` checks the recipient's corresponding preference before inserting a notification. Disabled categories therefore do not reach the inbox, realtime publisher or device push delivery. Financial/order notifications remain wallet-only by design.
- Verification: inspected Settings UI, SettingsService/Repository, NotificationRepository and NotificationService; existing `backend/test/settings_security.test.ts` and notification tests cover persistence and suppression. Latest backend test suite passed before the current S4-only changes; final CI will rerun.


### S7 Help and support
- Status: BLOCKED for production support-contact configuration; the report workflow is implemented.
- Added optional SUPPORT_EMAIL configuration, authenticated support config and report endpoints, a rate limit, support_reports migration 032, repository/service, Settings entry and Help & Support page. Reports are persisted and return a reference. The app does not hardcode a support address; if the setting is empty, it says so and still accepts reports.
- Verification pending: backend tests, Flutter analyze/tests and staging migration.
- Exact unblock: owner confirms the monitored support inbox and sets SUPPORT_EMAIL in Railway. Do not assume the Resend reply-to address is the support contact.


### C1 — Cart
- Status: DONE.
- Product detail adds items to the authenticated user's backend cart. Cart UI groups rows by seller, changes quantity, removes items, handles empty/loading/error states and shows server-computed subtotal. Backend locks inventory and rechecks stock and currency on every add/update.
- Verification: inspected CartPage, CartService/Repository and product detail flow; existing cart tests cover inventory/quantity and mixed-currency guards. Full CI will rerun after 2B changes.


## Current execution update — 2026-11-01

Branch: work/eazy-launch-readiness
PR: #39 (draft, not merged)
Latest verified workflow at time of this update: run 41358004335 built the backend TypeScript successfully and passed iOS configuration preflight. Its backend test job had one unrelated stale test fixture failure: account_deletion_routes.test.ts expected deletion success but omitted the required recent auth_time claim. The fixture was corrected in commit 1a732cf; rerun is pending. Flutter jobs and clean-database migration job still require a successful run.

### C2 — Checkout (PARTIAL)
- Added delivery-address CRUD, per-seller pickup/delivery selection, seller-configured delivery fee, server-side order price/stock recheck, order creation idempotency, Paystack card initialization and a buyer checkout screen.
- New amounts introduced for delivery and seller payable accounting are stored as integer kobo. Product names are snapshotted on order items for durable receipts.
- Files: backend/migrations/031_marketplace_checkout_escrow.sql; backend/src/modules/orders/{repository,service,controller,routes,schemas}.ts; backend/src/modules/marketplace/{repository,service,routes}.ts; backend/src/modules/payments/repository.ts; lib/features/marketplace/checkout_page.dart; lib/features/marketplace/cart_page.dart; lib/app/router.dart.
- Verification: backend TypeScript build passed on run 41358004335 before the latest incremental changes. Checkout schema tests added. Clean PostgreSQL migration CI job added; no successful run yet. No device payment test.
- Blockers: apply migration only after clean-DB CI passes; run Paystack test-mode checkout with a test account and verify the payment webhook/return flow.

### C3 — Escrow (PARTIAL)
- Verified Paystack order settlement now creates a seller payable hold per seller fulfilment in integer kobo, inside the same DB transaction as transaction settlement. Repeated successful settlement is guarded by transaction status and unique ledger keys.
- Buyer receipt confirmation creates a matching release entry. Delivery sets a seven-day release deadline using ORDER_ESCROW_AUTO_RELEASE_DAYS. A scheduled job command, backend/src/jobs/release-due-escrow.ts, processes due releases in batches and writes events/notifications.
- Files: backend/migrations/031_marketplace_checkout_escrow.sql; backend/src/modules/payments/repository.ts; backend/src/modules/orders/{constants,repository,service}.ts; backend/src/jobs/release-due-escrow.ts; backend/package.json.
- Verification: tests added for verified-payment hold and auto-release SQL shape. No successful CI rerun or live test-mode end-to-end run yet.
- Blocker: Railway production cron is not configured. Configure a Railway scheduled service to run `npm run build && npm run escrow:release-due` from the backend directory at least hourly, only after the code is merged and deployed. Do not run the job manually against production as a substitute for the schedule.

### C4 — Buyer orders and disputes (PARTIAL)
- Added buyer orders list/detail, fulfilment status, event timeline, confirm-received and dispute creation. Disputes are seller-specific, freeze auto-release, store bounded reason/description and accept optional owner-scoped storage keys. Seller notifications are persisted.
- Seller order inbox supports accept, ship and deliver; delivery address is only returned after acceptance. Inventory reservation is consumed on delivery.
- Files: backend/src/modules/orders/*; backend/migrations/031_marketplace_checkout_escrow.sql; lib/features/marketplace/orders_page.dart; lib/features/marketplace/seller_orders_page.dart; lib/app/router.dart.
- Verification: schema/service tests added; no passing CI rerun, migration test or device workflow yet.
- Blockers: dispute-photo picker/upload UI is not connected. Seller rejection is intentionally disabled because the current payment provider abstraction has no verified refund operation; enabling rejection without a confirmed refund would strand buyer funds. Add and test a server-verified Paystack refund flow before enabling it.

### C5 — Reviews (PARTIAL)
- Added one review per completed order item, 1–5 rating and text validation, product/seller review lists and average/count aggregates in product projections. Buyer order detail offers review submission after completion; product detail shows reviews and seller rating.
- Files: backend/migrations/031_marketplace_checkout_escrow.sql; backend/src/modules/{orders,marketplace}/*; backend/test/commerce.test.ts; lib/features/marketplace/{orders_page,product_detail_page}.dart.
- Verification: tests added; no successful CI rerun or device verification yet.

### C6 — Message seller (PARTIAL)
- Product and order detail screens route to Chat with the seller username. Chat creates or reuses the direct conversation and opens it.
- Files: lib/features/chat/chat_page.dart; lib/features/home/home_shell.dart; lib/features/marketplace/{product_detail_page,orders_page}.dart; lib/app/router.dart.
- Verification: source path inspected; no device verification.

### L3-L4 — Seller operations (PARTIAL)
- L3: seller inbox lists paid orders and supports accept, ship and deliver with buyer notifications. Delivery address remains hidden until accept. Seller reject is disabled pending safe refunds.
- L4: seller payable ledger API and a simple held/released history screen are added. No withdrawal action exists.
- Files: backend/src/modules/orders/*; lib/features/marketplace/{seller_orders_page,seller_payables_page,seller_setup_page}.dart; lib/app/router.dart.
- Verification: tests and CI pending.

### S7 — Help and support (PARTIAL)
- Configured support email is read from SUPPORT_EMAIL. Authenticated report form persists reports and returns a reference; no hard-coded contact address.
- Files: backend/.env.example; backend/src/config/env.ts; backend/src/modules/support/*; backend/migrations/032_support_reports.sql; backend/test/support.test.ts; lib/features/support/support_page.dart; lib/features/settings/settings_page.dart; lib/app/router.dart.
- Verification: support unit tests passed in run 41358004335. The production Railway service did not expose SUPPORT_EMAIL in its configured variable names at last inspection.
- Blocker: owner must confirm the monitored support inbox and set SUPPORT_EMAIL in Railway. Until then the app truthfully shows that no contact email is configured, while report submission remains available.

### CI and release
- Added a clean PostgreSQL 16 migration job to CI. It applies all SQL migrations from scratch and is a dependency of the signed release job.
- Added commerce tests for checkout selection, disputes, reviews and auto-release, and a Paystack repository test for verified seller escrow holds.
- Latest successful backend build evidence: run 41358004335. Its test suite had one stale recent-auth fixture failure, now corrected. Latest full CI rerun is pending.
- No database migration has been applied to Railway production. No signed release APK/AAB has been generated or verified. Android signing still depends on GitHub Actions secrets ANDROID_KEYSTORE_BASE64, ANDROID_STORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD; the keystore currently held by Manus is not available to this GitHub workflow unless those secrets are configured.
- No merge to main and no production deployment.
