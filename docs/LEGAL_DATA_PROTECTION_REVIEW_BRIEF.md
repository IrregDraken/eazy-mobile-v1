# Eazy — Legal and Data-Protection Review Brief for Anthony

> **Decision brief — not legal advice and not a compliance certification.** Prepared for Anthony, owner and authorized policy approver for Thony Dynamic Enterprises. No lawyer, DPO, DPCO or other data-protection professional has been designated as of this review.

## Confirmed business facts

- **Operator/business owner:** Thony Dynamic Enterprises.
- **Registration:** RC 2962026, verified by the business owner’s supplied information.
- **Address:** 125/130 Nnamdi Azikiwe Street, Idumota, Lagos Island, Lagos State, Nigeria.
- **Policy approver:** Anthony, the business owner.
- **Privacy and deletion oversight:** Anthony is the confirmed initial overseer.
- **Post-launch responsibility:** Thony Dynamic Enterprises.
- **Domain/email:** setup is already in progress; mailbox receipt and provider administration have not been independently verified.

## What the implementation actually processes

The source shows a Nigerian-facing account service with Firebase-backed identity, a PostgreSQL/Supabase-backed application database, private Supabase media storage, email verification through Resend when configured, push-device records, social posts and reports, direct chat and attachments, marketplace records, wallet/ledger/payment records, location and translation provider boundaries, and an optional Assist/AI boundary. Paystack, location, translation, AI, FCM/APNs and inbound mail are capability/configuration dependent; source adapters are not evidence that those provider accounts are activated or that a feature is live.

The database uses restrictive RLS policies that deny direct `anon` and `authenticated` table access, while the backend uses its authorized database path. Financial ledger rows are immutable by trigger. The account-deletion service blocks deletion for non-zero wallet balance, pending payments, active orders and active sales. It removes or anonymises many account-linked records, retains financial records and a deleted-user tombstone, revokes sessions and push devices, and records a durable cleanup job before committing. Exact user-owned media cleanup and Firebase identity removal run after commit; failures remain retryable and must not be described as complete deletion until the job is complete.

The current deletion service now queues exact user-owned Supabase Storage object keys associated with avatars, authored posts, seller products and authored message attachments, then deletes them through a bounded, retryable server-side adapter. The repository still has no recorded real-provider, backup-expiry or provider-deletion propagation evidence. These are material facts for the final privacy notice and deletion page.

## Relevant Nigerian questions for professional advice

The Nigeria Data Protection Act 2023 applies to organisations operating in Nigeria and regulates processing of personal data. The Act requires a controller notice to explain controller identity and contact, lawful basis and purposes, recipients, data-subject rights, retention period, complaint rights and certain automated decision-making information; the notice should be clear, concise, transparent and accessible.[1] The NDPC’s official resources also link controller/processor registration, DPCO registration and privacy-breach reporting services.[2]

A reviewer should determine, based on Eazy’s actual scale, users, financial/social features and processing, whether Thony Dynamic Enterprises is a data controller of major importance, whether registration or a filing is required, whether a DPO or licensed DPCO involvement is required, and whether a data protection impact assessment is appropriate. The Act expressly addresses high-risk processing and DPIAs, and requires a DPO for a controller of major importance.[1]

The reviewer should also assess child/teen processing and age controls, location and profile data, direct-message and UGC moderation, financial and fraud records, international transfers to Firebase/Supabase/Railway/Resend/Paystack or optional providers, contracts and subprocessor terms, breach response, records of processing, lawful bases, consent withdrawal, retention exceptions and deletion from storage/backups/provider copies. No conclusion that Eazy is compliant should be drawn from the existence of drafts or source controls alone.

## Questions Anthony must decide

1. Which countries and user groups will V1 serve, and what minimum age will apply?
2. Which provider-backed features are enabled at launch: Paystack/bank features, location, translation, Assist/AI, notifications and analytics?
3. Which mailbox owner and backup administrator will receive support, privacy, legal and security requests? Has each route been tested inbound?
4. What response targets and business hours apply to support, privacy/deletion, payment disputes and security reports?
5. What are the approved retention and deletion rules for active accounts, content, messages, moderation evidence, financial records, support records, logs, backups and provider copies?
6. What is the approved identity-verification method for an unauthenticated deletion request?
7. Will Eazy prohibit explicit/sexual content at V1, and what moderation, appeal and response process will be staffed?
8. Which payment products, territories, currencies, fees, cancellations, refunds, chargebacks and merchant disclosures are approved?
9. Which hosting, DNS, Firebase, Supabase, Railway, Resend, Paystack, Apple and Google accounts are controlled by the business, and who is the recovery administrator?
10. Who is the named technical maintenance, deployment, backup/restore, security incident and post-launch monitoring owner?

## Reviewer packet

A lawyer or qualified Nigerian data-protection professional should receive:

- This brief and the policy approval register.
- `docs/legal-drafts/PUBLIC_LEGAL_PAGE_DRAFTS.md`.
- `docs/legal-drafts/DATA_INVENTORY_RETENTION_AND_OWNER_DECISIONS.md`.
- `docs/ACCOUNT_DELETION_VERIFICATION_REPORT.md`.
- Current schema migrations, RLS policies and account-deletion tests.
- Provider/configuration inventory showing enabled versus merely available integrations, without secret values.
- Proposed mailbox, support, incident and privacy-request procedures.
- Store declaration drafts and the final public URL plan.

Retain the reviewer’s written scope, advice, version reviewed, assumptions, requested changes, approval or rejection, and date. Retain evidence of Anthony’s final decision separately from professional advice.

## Current status

**Awaiting professional review.** Anthony’s identity and role are confirmed, but no policy approval has been recorded. Domain/email setup remains in progress. No legal page has been published, no live payment has been performed and no production data has been changed.

## References

[1]: https://cert.gov.ng/ngcert/resources/Nigeria_Data_Protection_Act_2023.pdf "Nigeria Data Protection Act, 2023 — official government-hosted text"
[2]: https://ndpc.gov.ng/resources/ "Nigeria Data Protection Commission resources and registration/breach services"
[3]: https://ndpc.gov.ng/dpco-registration-requirements/ "Nigeria Data Protection Commission DPCO registration and requirements"
[4]: https://ndpc.gov.ng/faqs/ "Nigeria Data Protection Commission frequently asked questions"
