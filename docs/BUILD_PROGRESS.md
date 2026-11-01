# Eazy Launch Readiness Build Progress

Updated: 2026-11-01
Branch: feature/launch-readiness
Base: main at 11cd49b8c35664eaf8bbaabc10cdb96656931cab

## Session rules
- Scope is restricted to the uploaded Eazy Master Build Prompt.
- Phase order: 0 orientation, 1 defects, 2 launch features, 3 Paystack wallet, 4 visual polish.
- No item is DONE without changed files and verification evidence.
- No production Paystack keys, fake financial data, debug signing, or client-authorized money movement.
- Legal copy, provider credentials, business classification and owner decisions remain explicit gates.

## Phase 0: Orientation

Status: DONE (repository map and initial code-to-item audit completed; runtime/build verification remains unavailable through the current GitHub-only workspace).

### Repository map
- Flutter app: `lib/`; declared Flutter SDK >=3.29.0 and Dart >=3.7.0 in `pubspec.yaml`.
- Dependencies show Flutter Material, go_router, Firebase Auth/Messaging, secure storage, image_picker, file_selector, local_auth, QR and mobile_scanner.
- Navigation: `lib/app/router.dart` (GoRouter) and `lib/features/home/home_shell.dart` (IndexedStack + NavigationBar).
- Theme: `lib/app/theme/eazy_theme.dart`, `lib/app/theme/theme_controller.dart`. Theme controller currently restores Light/Dark only and defaults to Light.
- API client: `lib/core/network/api_client.dart`; API errors: `lib/core/network/api_exception.dart`.
- Media client: `lib/core/media/media_service.dart`; backend media module: `backend/src/modules/media/service.ts`; Supabase signed upload/read URLs are used.
- Backend: TypeScript/Express modules under `backend/src/modules/`, PostgreSQL migrations under `backend/migrations/`, tests under `backend/test/`.
- Wallet/ledger: `backend/src/modules/wallet/`, `backend/src/modules/ledger/`, bank/DVA under `backend/src/modules/bank/`, payment provider integration under `backend/src/providers/`.
- Marketplace UI: `lib/features/marketplace/`; cart and seller setup screens already exist.
- Existing architecture matrix: `docs/IMPLEMENTATION_MATRIX.md`.
- `docs/BUILD_PROGRESS.md` did not exist on main when checked; this file establishes it on this branch.

### Phase 1 defect causes and responsible code (initial evidence; all remain TODO until fixed and tested)

| ID | Initial code finding / likely cause to verify fully | Responsible files | Status |
|---|---|---|---|
| D1 | Media upload returns a storage key and local path; backend signs private chat attachment reads. The chat bubble currently reaches an image-load error, so trace message serialization and authenticated signed-read URL resolution end-to-end. | `lib/core/media/media_service.dart`, `lib/features/chat/chat_page.dart`, `backend/src/modules/media/service.ts`, chat routes/repository | TODO |
| D2 | Backend wallet transfer service already checks ledger balance transactionally, but the review UI evidently permits progressing to PIN with insufficient balance; trace client amount/balance parsing and ensure server PIN authorization/result refresh. | `lib/features/wallet/wallet_page.dart`, `backend/src/modules/wallet/service.ts`, wallet routes/controller, payment PIN middleware | TODO |
| D3 | Feed fetch has loading/error handling and RefreshIndicator, but no confirmed retained cache; `SocialPage.load` sets loading based on empty posts. Repeated shimmer likely means empty/failed results or page recreation. | `lib/features/social/social_page.dart`, `lib/features/home/home_shell.dart` | TODO |
| D4 | Marketplace empty state unconditionally says “No products match your search” whenever products are empty; it does not distinguish active query/filter from an unfiltered catalogue. | `lib/features/marketplace/marketplace_page.dart`, `lib/features/marketplace/discover_categories.dart` | TODO |
| D5 | Conversation list refreshes on realtime events and sorts by latest-message activity, but recording shows stale preview after send/receive; inspect event payload and conversation projection/update behavior. | `lib/features/chat/chat_home_screen.dart`, `lib/features/chat/chat_page.dart`, `backend/src/modules/chat/service.ts`, repository/realtime | TODO |
| D6 | Assist client appends response objects in API-return order and does not apply a stable chronological sort; it has refresh but no explicit New chat action. | `lib/features/assist/assist_page.dart`, backend Assist session/message repository and context | TODO |
| D7 | Cart and Settings show loading states. Cart makes network calls and needs timeout/retry; Settings should render local preferences immediately. | `lib/features/marketplace/cart_page.dart`, `lib/features/settings/settings_page.dart`, API client | TODO |
| D8 | Home shell uses `extendBody: true`; safe-area handling is inconsistent across shell, modal, keyboard and screen layouts. | `lib/features/home/home_shell.dart`, affected screen scaffolds and Android window configuration | TODO |
| D9 | Eazy Assist FAB is positioned as a fixed overlay in the home shell on Home/Discover/Profile and has no collision/keyboard/scroll-aware placement. | `lib/features/home/home_shell.dart`, `lib/core/ui/eazy_assist_fab.dart` | TODO |
| D10 | Profile copy feedback uses a SnackBar through the page ScaffoldMessenger; no navigation-scoped dismissal or theme-aware duration/contrast was confirmed. | `lib/features/profile/profile_page.dart`, shared snackbar/theme components | TODO |
| D11 | Chat UI has an explicit failed-image widget; inspect message attachment sizing, timestamp colors and header foreground/background pairing. | `lib/features/chat/chat_page.dart` | TODO |
| D12 | Copy-profile-link action exists as an icon-only tooltip; recording indicates its visible label wraps. Inspect profile action layout/constraints. | `lib/features/profile/profile_page.dart` | TODO |
| D13 | NavigationBar is controlled by a single selected index in HomeShell; reported multiple active tabs may be animation/transition rendering or duplicated navigation surfaces. Reproduce on device before changing. | `lib/features/home/home_shell.dart` | TODO |
| D14 | Dialogs and sheets rely on shared Material theme defaults; low contrast was reported in light mode. Audit shared theme and all relevant dialog/sheet surfaces. | `lib/app/theme/eazy_theme.dart`, dialog/sheet call sites | TODO |
| D15 | Theme controller only persists Light/Dark and defaults to Light; Settings dropdown offers Light/Dark only. Language row is static explanatory text, not a selector. | `lib/app/theme/theme_controller.dart`, `lib/features/settings/settings_page.dart` | TODO |
| D16 | Currency formatting is repeated and some UI renders currency as NGN; single shared NGN formatter is absent from the inspected screens. Wallet recipient flow needs one-result bypass and helper-text review. | `lib/features/wallet/wallet_page.dart`, `lib/features/marketplace/cart_page.dart`, product/transaction widgets, shared formatting utility | TODO |

### Phase 2 existing partial implementation (must verify before extending)
- Settings: account settings, security, blocks, notification center and basic preference toggles exist. Payment PIN backend routes exist, but current API schemas use six digits, conflicting with this prompt's four-digit requirement.
- Cart/checkout: cart screen and backend cart/order/payment modules exist. Existing cart checkout creates an order then initializes Paystack card payment; delivery-address and per-seller delivery/pickup requirements need verification.
- Seller: seller setup and product creation exist. Seller agreement acceptance, payout account validation, seller order lifecycle and payable balance need verification.
- Search: marketplace product search/categories/sort exist; unified Products/Sellers tabs, filters and recent searches need verification.
- Seller profiles/product seller cards: profile/product detail screens exist; required seller-specific details and Message action need verification.
- Small improvements: unread badges, message status, in-chat translation, translation swap/detected language/share, notification payment filter, first-run checklist, home no-follow empty state, seller Shop tab and Assist order quick actions need verification.
- Account deletion and security routes exist in some form per current repository matrix; exact policy compliance and open-order/wallet-balance guards require code review.

### Phase 3 existing wallet foundation (not yet compliant with this prompt's activation flow)
- Wallet service and ledger exist; ledger balance and transactional transfer logic are present.
- Payment PIN service/routes exist, but currently the wallet route schema uses six-digit PINs, while this prompt requires four digits.
- Virtual-account service exists and assigns a DVA using the user's existing display name, email and phone after an active wallet exists.
- The inspected DVA service does not yet show the required `PAYSTACK_DVA_REQUIRE_VALIDATION` gate, BVN + linked bank-account validation flow, or explicit customer-identification success/failure state machine.
- Wallet UI currently fetches/creates a wallet automatically when the wallet endpoint returns none, which conflicts with the prompt's opt-in activation flow. Do not enable this behavior for new accounts.
- Webhook service handles DVA assignment and `charge.success`; verify signature/idempotency and event persistence before relying on it.
- Existing test coverage includes financial modules and account deletion; add the exact tests required by P11.

## Phase 2/3 external blockers to track
- S5: Owner-supplied lawyer-reviewed Terms of Service and Privacy Policy text required; screens may be wired to content files, but legal wording must remain BLOCKED until supplied.
- S7: Support email address must be supplied/configured.
- L1: Seller Agreement text required and must not be invented.
- P0/P2: Paystack business category confirmation determines whether BVN validation is required. Until confirmed, use the prompt's default-true server flag and keep real-money go-live blocked.
- P11: Paystack test keys and webhook URL/dashboard configuration required for live provider test execution. Never substitute live keys.
- P10: Seller cash-out/Paystack Transfers decision explicitly remains BLOCKED; no withdrawal control is to be built.
- Production credentials, provider approval/go-live and legal sign-off remain release gates.

## Assumptions
- Main is the only base for this isolated branch; no other feature branches are merged into this work.
- Existing app and backend architecture will be retained.
- Existing backend ledger is the source of truth; no client-side balance mutation.
- Items not in the uploaded master prompt are out of scope.

## Suggestions (not built)
- None recorded yet.

## Verification
- Repository metadata confirmed; default branch is `main`.
- Branch `feature/launch-readiness` confirmed isolated from `main`, based on `11cd49b8c35664eaf8bbaabc10cdb96656931cab`.
- Source files inspected through GitHub for the paths listed above, plus wallet UI/routes, chat message serialization, media signing, Assist context, DVA assignment and webhook routing.
- D1 deeper trace: Flutter stores the uploaded storage key in message attachments; backend returns `storageKey`/`contentType`/`byteSize`; chat renderer unconditionally renders an attachment chip and the composer shows `fileName` rather than `localPath` thumbnail. This explains the observed chip/filename UI, while the exact failed network read still needs device/provider reproduction. `lib/features/chat/chat_page.dart`, `lib/core/media/media_service.dart`, `backend/src/modules/chat/repository.ts`, `backend/src/modules/media/service.ts`, `backend/src/providers/supabase-storage.ts`.
- Shell and Node.js/npm are available, but there is no local repository checkout and outbound GitHub DNS/network access is unavailable from the shell. Flutter/Dart SDK, database, emulator and physical device are also unavailable. Therefore Flutter analyzer/tests, backend typecheck/tests, Android build, database migrations, device tests and provider end-to-end tests have NOT been run.
