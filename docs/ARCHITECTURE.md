# Eazy Mobile V1 Architecture

Eazy V1 is a Flutter application with its own visual system and app-specific assets. It does not import or reuse visual assets from the legacy Flutter repository.

The app uses the established Eazy product workflows and backend contracts while keeping V1's mobile client, deployment configuration, and release process explicit.

## Boundaries

- Flutter is the only mobile UI stack.
- The app calls the Eazy V1 Railway API by default; `EAZY_API_URL` can override the base URL at build time.
- Firebase is the native identity layer.
- Secure storage holds Eazy access credentials.
- Feature modules own UI and feature orchestration.
- Core owns networking, auth, persistence, permissions, and provider boundaries.
- Production screens must not depend on fake or demo records.
- Provider-dependent features must show honest unavailable/error states when credentials or providers are not configured.

## Modules

Auth, onboarding, social feed, profiles, follows, marketplace, cart, orders, wallet, payments, utilities, chat, notifications, search, QR, location, translation, Eazy Assist, settings, and support.

## Visual assets

The V1 app includes purpose-built assets under `assets/images/`, declared in `pubspec.yaml`. These include the logo mark, app icon, auth hero, and onboarding hero. Keep these assets versioned with the app and export store-specific icon sizes as part of release preparation.
