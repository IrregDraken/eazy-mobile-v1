# Eazy V1 Build Contract

## First local bootstrap

1. Install Flutter 3.29 or newer.
2. Run flutter create . --platforms=android,ios.
3. Run flutter pub get.
4. Add the native Firebase configuration for project eazy-24e6.
5. Run flutter analyze.
6. Run flutter test.
7. Run flutter run on a physical device.

The Flutter project files are intentionally generated from the installed Flutter SDK rather than copied from either previous Eazy repository.

## Backend

Default API target:

https://eazy-mobile-v2-production.up.railway.app/v1

Override it with:

--dart-define=EAZY_API_URL=https://your-api.example/v1

## Visual asset rule

Do not copy assets, images, splash artwork, launcher artwork or preview screenshots from the legacy Eazy repositories into this project.

The initial V1 experience intentionally renders its identity from Flutter UI primitives only.
