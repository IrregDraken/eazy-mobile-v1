# Eazy V1 Backend

Node.js, TypeScript, Express, and PostgreSQL backend for the Eazy V1 monorepo. The implementation includes Firebase-backed authentication; profiles, social graph, and blocking; notifications; chat and realtime access; marketplace and orders; wallet and payment foundations; Assist provider abstractions; translation and location interfaces; and Settings & Security.

Firebase remains the sign-in and identity authority. The backend maps verified Firebase identities to internal Eazy users and applies owner-scoped Eazy sessions, settings, and privacy controls. See [Authentication](docs/authentication.md), [Settings & Security](docs/settings-security.md), and the endpoint-specific guides in `docs/` for exact behavior and provider requirements.

## Commands

```bash
npm ci
npm run lint
npm test
npm run build
npm start
```

The server exposes `GET /health` and the version root `GET /v1`. Database schema changes are managed by additive SQL migrations under `migrations/`. Copy `.env.example` to an untracked `.env` for local configuration. Keep Firebase, database, payment, email, and other provider credentials in a secret store and never commit them.

## Deployment boundary

Railway deployment and production provider configuration are documented in the repository's `docs/PRODUCTION_RELEASE.md`. Confirm the Railway `DATABASE_URL`, media bucket, and provider credentials against the intended environment before enabling production traffic. Do not assume a project used for integration testing is the production database or storage project.

The CI workflow validates Flutter analysis/tests, an Android build smoke path, and backend build/tests against disposable PostgreSQL. The optional real Supabase Storage integration job is not considered validated until it has run successfully against a dedicated, explicitly non-production project.
