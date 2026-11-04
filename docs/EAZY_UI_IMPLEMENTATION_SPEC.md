# Eazy UI Reference Implementation Specification

Status: approved implementation scope
Repository: `IrregDraken/eazy-mobile-v1`
Implementation branch: `codex/eazy-production-batch-1-8`

This specification records the selected elements from the owner's Notion image library. The images are a visual reference library, not a mandate to copy entire screens. Preserve Eazy's existing product identity, navigation, green brand system, light-first theme, dark-mode support, and working functionality unless a requirement below explicitly changes it.

## Chat
- Header shows the other participant's display name, username, and avatar.
- If no avatar exists, show the first letter of the username.
- Header includes conversation search and a three-line options menu.
- Message bubbles size to their content and wrap naturally.
- Preserve the selected reference bubble appearance and visual consistency.
- Support replies and a visible typing indicator.
- Do not regress existing attachment, reaction, edit, delete, wallpaper, or realtime behavior.

## First-time Eazy Wallet activation
- On first Wallet access, show the activation experience when no active virtual account exists.
- Intro copy explains activation and the ability to send/receive money and obtain a dedicated virtual account.
- Show the stages: Personal Details, Verification, Virtual Wallet, Activate Wallet.
- Persist activation state through the backend account status. Do not rely on a local-only flag.
- Pending state communicates that provider confirmation is in progress.
- Active state confirms the wallet is ready.
- Failed state explains that activation could not be completed and exposes a real retry.
- Do not invent KYC fields, provider success, or a successful account assignment. Use verified profile data and the existing provider contract; surface missing requirements clearly.

## Profile
- Add a cover/banner image behind the profile identity.
- Show profile image, display name, username, bio, location, post/follower/following counts.
- Keep Settings at the top-right for the owner's profile.
- Show Follow and Message actions on another user's profile.
- Remove the three-dot profile action.
- Use one Posts tab only. Do not expose Videos, Saved, or Liked tabs.
- Preserve profile editing, avatar upload, following, messaging, seller features, and pagination.

## Eazy Assist
- Keep the message composer and refresh action at the top of the interaction.
- Show a clear generation/typing state after send.
- Provide cancellation only when the request can actually be cancelled; do not fake cancellation by merely hiding the spinner.
- Preserve chronological message order across bootstrap, send, refresh, and reopen.
- Provide a retry action for recoverable failures.
- Use the approved user-facing states: "I'm having trouble right now" with Retry, and "Eazy Assist temporarily unavailable" for provider/backend outage.

## Wallet dashboard
- Keep the existing wallet features, but reduce oversized spacing and visual scale.
- Show balance with show/hide control, verified-account status, financial notifications, and recent transactions.
- Keep financial notifications inside Wallet, separate from general notifications.
- Preserve working send/receive, pending-deposit recovery, payment PIN, and virtual-account behavior.
- Do not include the unclear reference phrase "a bright and Nigeria together" unless the owner clarifies its intended wording.

## Discover
- Preserve the current Discover page and the existing five generated category assets.
- Do not replace the existing category visuals with those depicted in the reference images.
- Add "Featured for You" and "Just for You" only when supported by real product data.
- Cart icon displays the real cart item count.

## Home
- Keep the current Home feed and stories structure.
- Add a compact search bar and a hamburger/menu entry.
- Add a Create Post action at the top-right.
- Make the "Five people to follow" and "Create a post" prompts dismissible when those prompts are present.
- Reduce the height of the top search field.

## Acceptance gates
- Every new control must perform a real action.
- Loading, empty, error, pending, success, and retry states must be handled.
- No mock data, fake provider status, local-only wallet activation, or placeholder success.
- Run formatter, analyzer, tests, backend checks, and CI where available.
- Record device/provider checks that cannot be performed from the repository environment as blocked, not done.
- Do not merge to `main` or deploy production as part of this implementation pass.

## Implementation notes and verification boundaries

Implemented on the isolated branch so far:
- Chat header search and hamburger menu, username-initial avatar fallback, and server-authorized realtime typing presence.
- Eazy Assist retry UI plus a cancellation endpoint that aborts the active provider request and records a cancellation marker.
- Wallet activation preflight, four progress stages, pending/failed retry messaging, and a more compact balance card.
- Profile cover upload and display, public location field/editing, owner-only actions, and Posts-only content navigation.
- Discover cart count, rating-backed Featured for You products, and a separate fresh-listings Just for You section.
- Home people search, menu, Create action, dismissible empty-feed prompt, and server-backed follow suggestions.

Important boundaries:
- Assist generation cancellation currently uses an in-process controller map. It is real cancellation on the instance handling the generation, but multi-instance deployments need shared cancellation coordination before horizontal scaling.
- Chat search searches the 50 messages already loaded in the conversation, not the entire server-side history.
- Home search currently searches people, not every content type.
- "Featured for You" is ranked from actual product ratings/review counts. "Just for You" currently uses fresh listings; it is not yet behaviour-personalized.
- People suggestions are based on active accounts and follower counts, with already-followed and blocked accounts excluded. They are not yet a behavioural recommendation model.
- New database migrations 035, 036 and 037 are committed to this branch only. They have not been applied to production.
- Provider-backed activation, two-account chat typing, cover upload on a physical device, and the final Android release still require environment/device verification.

Do not mark the implementation ready until formatting, Flutter analysis/tests, backend build/tests, clean-database migration tests, CI, and physical-device smoke tests have been checked. No merge to main or production deployment is authorized by this specification.
