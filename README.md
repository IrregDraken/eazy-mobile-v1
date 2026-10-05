# Eazy

Production Eazy monorepo.

This repository contains the complete product source:

- **Flutter mobile app** in the repository root.
- **Production Node/TypeScript API** in `backend/`.
- **Database migrations** in `backend/migrations/`.
- **Backend integration tests** in `backend/test/`.
- **Shared production documentation** in `docs/`.

## Architecture

```
eazy-mobile-v1/
├── lib/                 # Flutter application
├── test/                # Flutter tests
├── docs/                # Product and release documentation
├── backend/             # Production API
│   ├── src/             # Express/TypeScript backend
│   ├── migrations/      # PostgreSQL migrations
│   ├── test/            # Backend tests
│   ├── package.json
│   └── tsconfig.json
├── railway.json         # Railway deployment for backend/
├── pubspec.yaml         # Flutter dependencies
└── .github/workflows/   # Full mobile + backend CI
```

## Production deployment

Railway deploys the backend from this same repository. The root `railway.json` builds and starts the application with the `backend/` workspace.

The Flutter app is not deployed to Railway. Android/iOS builds use the Flutter release pipeline.

## Backend

Local backend commands:

```bash
cd backend
npm ci
npm run build
npm test
npm run dev
```

Required production secrets belong in Railway/Firebase/Supabase/Paystack/Resend provider configuration, never in Git.

## Mobile

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

The mobile app uses the backend API configured through `EAZY_API_URL`.

## Asset rule

The V1 rebuild does **not** reuse visual assets from the old Eazy repositories.
