# Eazy V1 — Operations Runbooks

> **Controlled operational draft.** These procedures require the named owner’s authorization and appropriate provider access. Do not execute destructive database, credential, payment, or production actions from this document without explicit authorization.

## 1. Ownership and escalation placeholders

- Incident commander: `[TECHNICAL OWNER — ANTHONY TO ASSIGN]`
- Engineering lead: `[TECHNICAL OWNER — ANTHONY TO ASSIGN]`
- Privacy/data-deletion owner: Anthony initially (confirmed); backup owner `[OWNER DECISION]`
- Security owner: `[OWNER DECISION — ANTHONY TO ASSIGN]`
- Payments/finance owner: `[OWNER DECISION — ANTHONY TO ASSIGN]`
- Support owner: `[OWNER DECISION — ANTHONY TO ASSIGN]`
- Hosting/provider owner: `[OWNER DECISION — ANTHONY TO ASSIGN]`
- Primary support: `support@eazy.name.ng` (proposed; inbound receipt unverified)
- Privacy: `privacy@eazy.name.ng` (proposed; inbound receipt unverified)
- Security: `security@eazy.name.ng` (proposed; inbound receipt unverified)
- Legal: `legal@eazy.name.ng` (proposed; inbound receipt unverified)

## 2. Deployment traceability

For each release, record the Git commit, repository/branch, build command and Dart defines used without recording secrets, Flutter/Dart/Android/Xcode versions, artifact checksum, signing certificate fingerprint, migration version, Railway deployment ID, health/readiness result, provider mode, rollback decision and approver.

Closure evidence:

- `/health` and `/ready` return expected responses.
- The deployed commit matches the approved source commit.
- Migrations complete in the authorized target database.
- The release artifact is signed with the release certificate, never the debug certificate.
- A smoke test covers authentication, profile editing, deletion request entry point, feed, chat, marketplace, wallet read-only views and provider-unavailable states.

## 3. Backup and restoration

1. Obtain authorization and select an isolated restoration target. Never test restoration by overwriting production.
2. Record the backup identifier, database/storage scope, creation time, encryption/access controls and expected recovery point.
3. Restore into the isolated target using the provider’s documented process.
4. Apply only the approved migration state; do not run an unreviewed destructive migration.
5. Verify schema version, user/profile ownership, RLS denial behaviour, private media access, financial ledger balance/invariants, deletion tombstone behaviour and service health.
6. Rotate or invalidate any credentials that were exposed to the restoration environment.
7. Record recovery time, data-loss point, failed checks and corrective action.

Closure requires a dated restoration record and owner sign-off. The current repository has migration and deletion tests but no recorded restoration drill.

## 4. Security incident

1. Open an incident record and assign an incident commander.
2. Preserve relevant request IDs, timestamps, deployment commit, provider event IDs and security logs without copying secrets or unnecessary personal data.
3. Contain safely: disable only the affected feature/provider mode, revoke affected sessions or credentials, and preserve evidence. Do not delete logs or alter financial records to hide an incident.
4. Assess affected data, users, providers, jurisdictions and whether a payment or account-deletion control was affected.
5. Notify the privacy/legal owner and counsel. Determine regulator and user notification duties before sending any public statement.
6. Patch, test and deploy through the traceability procedure. Verify health and affected paths.
7. Close with root cause, timeline, impact, notification decisions, remediation and follow-up owner.

## 5. Privacy complaint or deletion request

1. Log receipt time, channel, request type, requester contact and a minimal request reference.
2. Do not request passwords, tokens, payment PINs or one-time codes.
3. Verify identity using the approved process. Escalate ambiguous or high-risk requests to the privacy owner.
4. For deletion, use the authenticated in-app path where possible. For web/email requests, run the approved ownership check before action.
5. Check financial, legal hold, security and fraud-retention exceptions. Record only the minimum necessary exception reason.
6. Execute deletion through the existing service or the approved manual process; verify provider/storage/session effects in an isolated or controlled procedure.
7. Send the approved response and record completion/exception timing.

Anthony is the confirmed initial privacy/deletion overseer. The response SLA, backup owner, retention exceptions and professional escalation remain owner/counsel decisions.

### Account-deletion cleanup procedure

The deletion service uses migration `021_account_deletion_cleanup.sql` to persist one job per deleted user and exact media rows captured before database records are removed. Ownership is proven by the profile, authored-post, seller-product and authored-message joins plus the generated `${userId}/...` path prefix. Do not manually broaden a key list or delete a bucket prefix.

1. Confirm the request is authenticated and the service preflight has no wallet, pending-payment, active-order or active-sale blocker.
2. Allow the service to commit the database tombstone and financial/legal retention behavior before external provider work. Do not put Storage or Firebase calls inside a PostgreSQL transaction.
3. Inspect the cleanup job using authorized server/database access only. Never expose service-role keys, Firebase credentials or media keys to the client.
4. The service sends exact pending keys to the private Storage adapter in batches of 100, with bounded retries. Missing objects are expected to be idempotent only after the provider response behavior is confirmed in the dedicated non-production bucket.
5. Firebase identity deletion runs only after media cleanup succeeds. A failed job must remain `failed`/pending and the account must remain a deleted tombstone.
6. Retry with the service’s durable retry path after the provider outage is resolved. Repeated completed requests must be harmless; concurrent claims must not be run manually in parallel.
7. Escalate permanently failed jobs to the technical owner and Anthony. Record job/user reference, provider response class, attempt count and remediation without recording credentials or unnecessary personal data.
8. Do not report complete deletion until the job is `complete`, media rows are deleted, Firebase identity deletion is confirmed and approved backup/provider retention limitations are documented.

The current source and mocked-provider tests cover exact-key ownership, batching, transient retry, invalid paths, post-commit Firebase failure and successful retry. Real PostgreSQL, Supabase Storage, Firebase, backup expiry and provider-copy behavior remain integration gates; no production cleanup is authorized by this draft.

## 6. Provider outage

Affected providers may include Firebase, Resend, Supabase, Railway, FCM/APNs, Paystack, HERE, translation vendors and the Assist provider.

1. Confirm the issue with health/capability endpoints, bounded logs and provider status pages.
2. Do not fabricate success. The client must show the existing unavailable/error state.
3. For payment or bank operations, preserve idempotency keys and pending state. Do not retry an ambiguous charge blindly.
4. Disable only the affected optional capability if safe and authorized. Preserve read-only access where possible.
5. Publish an approved status/support message without revealing provider secrets or personal data.
6. Reconcile pending operations after recovery using provider event/reference IDs.
7. Record incident time, provider response, customer impact and reconciliation outcome.

## 7. Credential rotation

1. Obtain authorization from the account owner and identify every consumer of the credential.
2. Create the replacement in the provider console without printing it or committing it.
3. Update the secret manager/Railway variable, redeploy through traceability, and verify health/provider capability.
4. Revoke the old credential only after the replacement is confirmed; use an overlap window only if the provider supports it.
5. Search logs and Git history for accidental exposure. If exposed, treat as an incident and revoke immediately.
6. Record owner, date, provider, scope and verification result without storing the secret value.

## 8. Payment discrepancy

1. Freeze manual settlement decisions and assign the payments owner.
2. Capture internal transaction/order/ledger IDs, provider reference, idempotency key, currency, exact decimal amount, status and timestamps.
3. Compare the server-authoritative ledger/order with provider events and webhook signature/processing records.
4. Preserve pending status for ambiguous provider outcomes; never mark success from a client assertion.
5. Reconcile only through an authorized, auditable correction path. Do not edit immutable ledger rows directly.
6. Notify support, finance and legal where required. Record refund/chargeback decisions separately.
7. Close only when internal and provider balances reconcile and the owner signs off.

No live-money operation was performed during this execution.

## 9. Support escalation

Support must route account access, privacy/deletion, security, content moderation, marketplace/order, and payment issues to separate owners. The support system must avoid collecting passwords, tokens, full payment credentials or verification codes. Each ticket should retain a minimal reference, category, priority, owner, response status and resolution.

The product owner must set the response SLA, business hours, supported languages, escalation contacts, refund authority and complaint process before launch.
