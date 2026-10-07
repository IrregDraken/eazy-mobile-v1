# Eazy Mobile V1 Implementation Matrix

This matrix records the local audit against `Eazy_Manus_UI_Context_Engineering.txt` and the current repository architecture. The supplied logo and welcome/auth artwork already exist under `assets/images/`, so no additional reference-image upload is required for this implementation pass.

| Area | Current implementation | Backend/provider support | Remaining production configuration |
| --- | --- | --- | --- |
| Visual system | Dark forest/emerald theme, reusable cards, controls, navigation, logo mark and supplied welcome artwork | N/A | Final device-level visual review on Android and iOS |
| Splash / Welcome | Implemented; Welcome uses `eazy_welcome_hero.png`; logo uses `eazy_logo_mark.png` | N/A | Confirm final artwork ownership and app-store icon exports |
| Email auth | Firebase email/password plus Railway API session sync | Firebase Auth + Railway `/v1` auth | Firebase native config and production sender/provider credentials |
| Phone auth | Firebase phone verification flow | Firebase Auth | Android/iOS provider setup and SMS quotas |
| Google auth | Firebase credential exchange through `google_sign_in` | Firebase Auth / Google provider | OAuth client IDs and native plist/json configuration |
| Apple auth | Firebase credential exchange through `sign_in_with_apple` | Firebase Auth / Apple provider | Apple Service ID, Team ID, key, redirect and iOS capability |
| Verification | Server-backed challenge request/verify with rate-limit/error states | Railway auth + email verification tables | Resend sender/API key in deployment |
| Profile setup | Required first name, username availability, date of birth, optional names/bio, real PATCH/complete calls | Profiles module | Avatar upload UI can be expanded with native media affordance |
| Discovery | Added post-profile real people search, follow action, and live marketplace listing discovery; skip/continue state | Discover, Social, Marketplace modules | Contacts permission/invite integration is still native-provider work |
| Social feed | Real feed, post creation, media upload boundary, like/comment/save, empty/error/loading states | Posts, engagement, media modules | Push/deep-link polish and full moderation UX |
| Marketplace | Real product/category search, sorting, detail, cart and checkout routes | Marketplace, Cart, Orders, Payments | Merchant/payment provider credentials and webhooks |
| Wallet | Full send/receive surface: Eazy-user username transfers, external-bank account resolution and initiation, Eazy-user QR generation, QR scanning and payment, external-bank virtual-account receiving, transactions, checkout verification, idempotency and honest provider-unavailable states | Wallet, Ledger, Bank, QR, Payments modules | Provider enablement, bank-account/transfer credentials, production webhook verification, and camera permission review |
| Chat | Real conversation list, messages, realtime WebSocket, reactions, replies, edit/delete/report, message translation | Chat, Realtime, Translation modules | Provider credentials for translation and push delivery |
| Eazy Assist | Added real session/history/message UI with explicit provider-unavailable state | Assist sessions/messages, AI provider adapter | `AI_PROVIDER_*` credentials/model in deployment |
| Translation | Real translation request boundary with honest unavailable/error state | Translation provider adapter | DeepL/Google credentials in deployment |
| Notifications | Real in-app notifications, read/read-all, device token registration | Notifications + Firebase Messaging | Firebase Admin credentials and native push capabilities |
| Profile/settings/security | Real profile stats/settings, session revocation, blocks, sign-out | Profiles, Settings, Security, Blocks | Final native privacy/permission copy |
| Native permissions | Location/media/push boundaries present in feature modules | Platform APIs and backend provider boundaries | Android/iOS manifest, Info.plist, entitlements, runtime permission review |
| Backend | Existing Railway TypeScript backend with migrations, validation, RLS/security, provider adapters and tests | Supabase PostgreSQL project `Eazy V2` is active and schema-aligned | Verify Railway deployment points to the intended active Supabase project |
| Validation | Existing backend test suite passes baseline; Flutter tests pass; analysis has informational lint findings plus missing asset directory warning | CI scripts and build docs | Resolve lints, add widget/integration coverage, run Android release build with native credentials |

## Required sequence

`Splash -> Welcome -> Get Started -> Email/Phone -> Verification Code -> Profile Setup + Password -> Discovery -> Home`

Sign in remains `Email + Password -> Remember Me / Forgot Password -> Sign In`, with Google and Apple provider actions below.

## Provider honesty rule

A missing provider configuration must render a useful unavailable/error state and preserve the integration boundary. The client must not fabricate AI answers, translations, payment success, inventory, social relationships, or verification.
