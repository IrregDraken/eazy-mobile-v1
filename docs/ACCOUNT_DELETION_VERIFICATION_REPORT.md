# Eazy — Account-Deletion Verification Report

> **Internal verification report.** No real account was deleted and no production data was modified. The real-database test remains skipped until an isolated authorized PostgreSQL test database is available.

## Scope and implementation inspected

The inspected route is authenticated `POST /v1/auth/delete-account`, protected by the existing authentication middleware and an account-deletion rate limit. A preflight route reports blockers. The mobile Settings flow shows a destructive confirmation, calls the authenticated route and clears local Firebase/Eazy state after a successful response.

`backend/src/modules/auth/account-deletion.ts` now uses a two-phase deletion workflow. The PostgreSQL transaction performs the database/tombstone work and records a durable cleanup job; external Storage and Firebase operations run only after commit. This avoids assuming external provider operations can roll back with PostgreSQL.

The database phase performs the following inside a transaction:

- Locks the user row and treats an already-deleted account as an idempotent no-op.
- Blocks deletion when the wallet balance is non-zero, payments remain pending, active buyer orders remain, or active seller sales remain.
- Deletes likes, saves, authored comments, authored posts, follows, blocks, authored message attachments, reactions, read markers, notifications, push devices, Assist sessions, translation requests, settings, verification codes and email-verification challenges.
- Removes the user from active conversation membership and scrubs authored message bodies while retaining the other participant’s thread.
- Archives the user’s marketplace products, removes the buyer cart and cancels pending buyer orders.
- Revokes QR codes, suspends virtual accounts and closes wallets.
- Revokes sessions and anonymises the profile to a deleted-user tombstone; the user row becomes `status = 'deleted'` with email, phone and verification state cleared.
- Records an `account_deleted` security event.
- Captures exact user-owned media keys before rows are deleted and stores them in `account_deletion_media` under `account_deletion_jobs`.
- Commits the deleted-user tombstone and revokes database sessions before external cleanup begins.
- Terminates application sessions after the database commit.

The external phase then:

- Claims one durable cleanup job under a row lock, preventing concurrent cleanup attempts from claiming the same job.
- Deletes only the captured exact object keys through the server-side Storage adapter, in batches of 100 with three bounded attempts and idempotent provider semantics.
- Deletes the Firebase identity only after required media cleanup succeeds.
- Marks the job `complete` only after both media and identity work succeeds. A timeout, unavailable provider or Firebase failure marks the job `failed`, returns `cleanupPending: true`, and leaves the account tombstone in place so the account cannot regain normal access.
- Allows a later authenticated deletion request or operational `retryCleanup(userId)` call to retry failed work without reopening the account. Repeated completed requests are harmless.
- Prevents Firebase provisioning from updating email, phone or verification fields on a deleted tombstone; the active-only upsert returns `FORBIDDEN` without mutating the row.

## Verification performed

### Unit and mocked-provider tests executed

The backend suite includes unit coverage for:

1. Repeated deletion as a harmless no-op.
2. Wallet-balance blocking without mutation.
3. Post-commit Firebase failure leaves a deleted tombstone and a retryable pending job.
4. Exact media-key capture from avatar, post, product and authored-message attachment ownership joins.
5. Successful media cleanup followed by Firebase identity deletion.
6. Storage failure followed by a successful retry.
7. Storage cleanup batching, transient retry, invalid-path rejection and service-key non-disclosure.

The command previously executed was:

```sh
cd backend
npm run build
npm run lint
npm test
```

Result after the implementation: **190 tests, 189 passed, 0 failed, 1 skipped**. The skipped test is the real-database deletion test because `TEST_DATABASE_URL` is not configured. The Storage and Firebase-boundary tests use local mocked provider boundaries; they are not Supabase or Firebase integration tests.

### Real-database test prepared but not executed

The opt-in integration test creates throwaway users and exercises posts, likes, comments, follows, blocks, conversations, messages, products, push devices, settings, wallets and ledger entries. It verifies wallet blocking, successful deletion after the balance is neutralised, tombstone values, removal of selected user-linked records, message scrubbing, product archiving, financial-record retention, security-event creation and idempotent repeat deletion.

It must be run only against a fresh isolated database with all migrations applied. It must not use the production database because the test intentionally leaves a deleted-user tombstone and immutable financial records.

## Data and provider gaps

### Supabase Storage

The source now has an explicit `deleteObjects()` contract and migration `021_account_deletion_cleanup.sql`. Ownership is established before destructive database deletes by joining:

- `profiles.avatar_url` where the value is an exact user-prefixed path.
- `post_media` → `posts.author_id`.
- `product_media` → `products.seller_id`.
- `message_attachments` → `messages.sender_id`.

Only keys matching the authenticated user’s generated `${userId}/...` path prefix and passing traversal/path checks are queued. Attachments in messages authored by another user, other users’ media, external avatar URLs, shared content without a proven owner, financial records and legal-retention material are not speculatively deleted. The current upload generator establishes the prefix as `userId/kind/date/random-id.extension`.

Deletion is exact-key based; it does not list a bucket or delete a broad prefix. Missing objects are expected to be idempotent at the provider boundary. Large key sets are chunked into batches of 100. The adapter retries transient provider failures up to three attempts with bounded backoff. The local tests verify these contracts, but Supabase’s actual endpoint response and absent-object behavior remain provider-unverified.

### Firebase

Firebase identity deletion now occurs after the database commit and after required media cleanup. A Firebase failure leaves the tombstone and durable failed job in place; it does not roll back the already-committed database phase. The real Firebase provider, retry behavior and operator visibility remain unverified.

### Push tokens and sessions

Database push-device rows are deleted and sessions are revoked. FCM/APNs provider-side delivery history or token propagation was not independently tested. The service does not claim deletion from provider logs or backups.

### Financial and order records

Financial records and ledger entries remain. Wallets are closed, virtual accounts suspended and active operational blockers prevent unsafe deletion. The final retention exception and customer-facing explanation require Anthony’s decision and professional review.

### Backups and logs

No backup-restore drill or backup-expiry evidence was available. Security events intentionally retain a deletion event. Provider logs, application logs, database backups and storage backups were not proven to expire or delete on the application deletion path.

### Unauthenticated requests

The public page can direct a person who cannot sign in to the privacy channel, but the repository does not yet implement a public request intake or identity-verification workflow. Anthony must approve the safe verification process before publication.

## Risk assessment

- **Partial-failure risk:** database changes commit independently of external providers. Durable media rows and job state record pending/failed cleanup; the account remains a tombstone and cannot be re-provisioned.
- **Retry risk:** exact media cleanup is idempotent and retried from durable rows. A concurrent cleanup claim is rejected while a job is running. Stale-running recovery/worker scheduling is still an operational requirement.
- **Orphaned data risk:** source-level media references now have a cleanup path, but provider outages, unknown historical paths, provider logs, backups and third-party copies remain unverified.
- **Financial integrity risk:** the service preserves immutable ledger data and blocks non-zero/pending/active operational states. The isolated integration test remains necessary to validate the deployed schema and RLS.
- **Authorization risk:** the route is authenticated and rate-limited; direct client access is constrained by restrictive RLS. Device and production authorization tests remain open.

## Safe closure actions

1. Anthony and a qualified reviewer approve the deletion scope, retention exceptions and unauthenticated verification method.
2. Add an isolated test database and execute the prepared integration test.
3. Apply migration 021 and verify idempotent Supabase Storage cleanup in a dedicated non-production bucket, including avatars, post media, product media and authored message attachments. Decide how shared or legally retained objects are handled.
4. Verify Firebase identity deletion and retry behavior in a non-production provider project or authorized test tenant.
5. Document backup, log and provider-copy propagation based on actual provider settings and contracts.
6. Update `/privacy` and `/delete-account` only after the above facts and the approved response timeframe are available.

## Current status

**Implemented with mocked-provider verification, awaiting isolated integration verification.** The authenticated database phase, durable cleanup ledger, exact ownership capture, bounded Storage adapter and retryable Firebase/Storage orchestration are source-implemented. Real PostgreSQL, Supabase Storage, Firebase, backup/provider propagation and unauthenticated request-flow verification remain blocked by external access/configuration. No production account, media or data was touched.
