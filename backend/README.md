# Eazy V2 Backend

Node.js, TypeScript, Express, and PostgreSQL backend for Eazy V2. The current implementation includes Firebase-backed authentication; profiles, social graph, and blocking; notifications; chat and realtime access; marketplace and orders; wallet and payment foundations; Assist provider abstractions; translation and location interfaces; and Settings & Security.

Firebase remains the sign-in and identity authority. The backend maps verified Firebase identities to internal Eazy users and applies owner-scoped Eazy sessions, settings, and privacy controls. See [Authentication](docs/authentication.md), [Settings & Security](docs/settings-security.md), and the endpoint-specific guides in `docs/` for exact behavior and deferred functionality.

## Commands

```bash
npm install
npm run lint
npm test
npm run build
npm start
```

The server exposes `GET /health` and the version root `GET /v1`. Database schema changes are additive SQL migrations under `migrations/`. Copy `.env.example` to an untracked `.env` for local configuration; keep Firebase and database credentials in a secret store and never commit them.

**Current implementation boundary:** Checkpoint 20 is complete. Checkpoint 21 has not started.

---

**Author:** Manus AI

**Last updated:** 2026-09-25

**Version:** 2.0

**Change note:** Updated the overview for the implemented Checkpoint 20 backend scope.

**Provenance:** Project documentation based on the current repository.
