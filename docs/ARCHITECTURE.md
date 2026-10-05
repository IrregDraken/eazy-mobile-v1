# Eazy Mobile V1 Architecture

Eazy V1 is a new Flutter application. It does not import or reuse visual assets from the legacy Flutter repository.

The implementation combines proven product workflows and feature scope from the original Eazy Flutter app with the stronger product direction and backend contracts established during Eazy V2.

## Boundaries

- Flutter is the only mobile UI stack.
- The V2 Railway backend is the initial API target.
- Firebase is the native identity layer.
- Secure storage holds Eazy access credentials.
- Feature modules own UI and feature orchestration.
- core owns networking, auth, persistence, permissions and provider boundaries.
- No production screen may depend on fake/demo records.

## Planned modules

Auth, onboarding, social feed, profiles, follows, marketplace, cart, orders, wallet, payments, utilities, chat, notifications, search, QR, location, translation, Eazy Assist, settings and support.

## Visual rule

There is deliberately no assets dependency in the initial app. Visual identity is rendered from Flutter primitives, typography, iconography, gradients and custom-painted geometry. New image assets may be introduced later only if they are created specifically for Eazy V1.
