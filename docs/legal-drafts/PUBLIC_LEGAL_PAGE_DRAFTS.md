# Eazy — Public Legal and Support Page Drafts

> **INTERNAL DRAFT — NOT APPROVED FOR PUBLICATION**
>
> These drafts are implementation materials, not legal advice or final policies. They must not be deployed to `eazy.name.ng`, linked from a store listing, or represented as approved until Anthony records approval of the exact versions and a qualified lawyer/data-protection professional reviews them where required. The confirmed business facts are recorded below; technical provider access, mailbox receipt and policy decisions remain open.

## Proposed public route manifest

The public website should expose these HTTPS routes on `eazy.name.ng`:

- `/privacy`
- `/terms`
- `/cookies`
- `/support`
- `/delete-account`
- `/community-guidelines`
- `/payments-refunds`
- `/security`

The public deletion page must be usable without signing in, must explain how to request deletion, and must not require a user to disclose more personal information than is needed to authenticate the request. The exact request channel is a product-owner decision; the draft uses `[PRIVACY CONTACT]` until approved.

## Confirmed facts and remaining publication fields

Confirmed business facts:

- Official business/operator and owner: **Thony Dynamic Enterprises**.
- Registration: **RC 2962026**.
- Official address: **125/130 Nnamdi Azikiwe Street, Idumota, Lagos Island, Lagos State, Nigeria**.
- Authorized policy approver: **Anthony, the business owner**.
- Initial privacy and account-deletion overseer: **Anthony**.
- Post-launch operator: **Thony Dynamic Enterprises**.

Still requiring an approved decision or evidence:

- Operating jurisdictions, governing law and effective/last-updated dates.
- Lawyer, DPO, DPCO or other qualified data-protection review; none has been designated.
- Final lawful-basis map, retention schedule, deletion exceptions and provider-transfer disclosures.
- Verified inbound routing and access for `support@eazy.name.ng`, `privacy@eazy.name.ng`, `legal@eazy.name.ng`, `security@eazy.name.ng` and `noreply@eazy.name.ng`. Domain and email setup is already in progress; proposed addresses are not proof of receipt.
- Payment/refund terms, age policy, UGC moderation SLA and cookie/analytics inventory.

Business ownership does not prove administrative access to Firebase, Supabase, Railway, Resend, Paystack, Apple, Google, hosting or DNS accounts. The policy drafts must not claim that such access has been verified.

## `/privacy` — Privacy Notice draft

**Effective date:** `[EFFECTIVE DATE — ANTHONY TO APPROVE]`
**Controller:** **Thony Dynamic Enterprises**, RC **2962026**, 125/130 Nnamdi Azikiwe Street, Idumota, Lagos Island, Lagos State, Nigeria
**Privacy oversight:** Anthony initially; no DPO/DPCO has been designated.
**Contact:** `privacy@eazy.name.ng` is proposed; inbound receipt and access remain unverified.

### What this notice covers

This notice explains how `[OFFICIAL BUSINESS NAME]` processes personal data when a person uses Eazy, visits the Eazy website, contacts support, or requests account or data deletion.

### Data categories identified from the current implementation

Eazy may process account identity and authentication data, including email address, phone number, Firebase/provider identity identifiers, verification challenges, sessions, and sign-in/security events. It may process profile data including name fields, username, date of birth, biography, avatar and profile settings.

Eazy may process user-generated content and social activity, including posts, uploaded media, likes, comments, saves, follows, blocks, reports, notifications, direct messages, message reactions, read state and message attachments. It may process marketplace data including products, seller information, cart items, orders, inventory, payment intents and delivery/order status.

Eazy may process financial data required for wallet, ledger, QR, payment and bank-transfer features. The exact categories, payment-provider responsibilities, reconciliation records, transaction identifiers, and retention exceptions require owner and counsel approval before publication. Eazy must not claim that it stores or does not store bank credentials until this has been verified against the enabled provider configuration.

Eazy may process location queries or coordinates when a user requests location tools. It may process translation requests and Eazy Assist conversation/session content when those features are used. It may process device push tokens and notification preferences. It may process IP address, user-agent, request ID, security logs, rate-limit records, error metadata and audit/security events.

### Purposes and lawful bases

The final notice must map each purpose to an approved lawful basis under the operating jurisdictions. Candidate purposes include account creation and service delivery, authentication and security, user-requested social and messaging features, marketplace and payment execution, fraud and abuse prevention, customer support, service reliability, legal obligations, and optional features such as location, translation, notifications and Assist.

The owner and qualified adviser must approve whether each purpose uses consent, contract necessity, legal obligation, vital interests, public-interest authority, legitimate interests, or another applicable basis. Consent must not be implied by silence, and the app must explain how consent can be withdrawn where consent is the basis.

### Recipients and processors

Potential processors identified from source include Firebase Authentication, Resend, Supabase PostgreSQL/Storage, Railway hosting, Paystack if enabled, Firebase Cloud Messaging if enabled, HERE if location is enabled, a translation provider if enabled, and an AI provider if Assist is enabled. The final list, roles, regions, transfer safeguards, contracts and enabled/disabled status must be verified from provider accounts before publication.

### User rights and requests

Subject to applicable law and legitimate exceptions, a user may have rights to notice, access, correction, deletion, restriction, objection, portability, withdrawal of consent, and complaint. Eazy will provide the final request process at `[PRIVACY EMAIL]` and/or `[PUBLIC REQUEST URL]` after the owner approves the identity-verification and response procedure.

### Retention and deletion

The final notice must link to the approved data-retention schedule. Eazy’s implemented account-deletion path removes or anonymises many account-linked records, revokes/deletes sessions and push-device records, removes selected social and media-linked data, and preserves a deleted-user tombstone plus certain financial/security records where the current service requires it. The exact exceptions, provider propagation, backup expiry and legal hold process require a real-database/provider review and legal approval.

### Complaints and regulator

Users may contact `[PRIVACY EMAIL]` first. The final notice must explain the applicable complaint route for each operating jurisdiction. For Nigeria, the Nigeria Data Protection Act 2023 provides for complaints to the Nigeria Data Protection Commission; Eazy should link to the current official NDPC complaint channel only after counsel confirms the applicable controller/processor status.

## `/terms` — Terms of Use draft

**Operator:** **Thony Dynamic Enterprises** (RC 2962026)
**Governing law and venue:** `[JURISDICTION — COUNSEL TO APPROVE]`
**Effective date:** `[EFFECTIVE DATE — ANTHONY TO APPROVE]`

These terms should cover eligibility and age rules, account security, acceptable use, user content licence and ownership, moderation, reporting and blocking, marketplace conduct, financial-feature limitations, third-party providers, availability, suspension and termination, account deletion, disclaimers, liability limits, dispute handling, changes, and contact details.

Do not publish this document until the operator identity, jurisdiction, financial terms, user-content licence, dispute mechanism, age threshold and refund/cancellation interactions have been approved.

## `/cookies` — Cookies and similar technologies draft

The final page must state whether the public website uses strictly necessary cookies, analytics, advertising, session, fraud-prevention or embedded third-party technologies. The current Flutter/mobile repository does not prove the cookie set for `eazy.name.ng`. Website instrumentation must be inventoried separately. Do not state “we use no cookies” until the deployed website, CDN, analytics, support widget and consent tooling have been checked.

## `/support` — Customer support draft

Support channel: `[SUPPORT EMAIL]`
Privacy/deletion channel: `[PRIVACY EMAIL]`
Security vulnerability channel: `[SECURITY EMAIL]`
Expected first response: `[OWNER-APPROVED SLA]`
Supported languages: `[OWNER DECISION]`

Support intake should capture the minimum information needed to identify the account or transaction. It must not ask users to send passwords, Firebase tokens, payment PINs, full card data, private keys or one-time verification codes. Payment disputes should use the approved transaction/reference workflow, not email-only assertions. Privacy and deletion requests need identity verification, a request log, ownership assignment, response deadline and exception/retention record.

## `/delete-account` — Public deletion request draft

Eazy users can initiate deletion inside the app from **Settings → Delete account**. The current mobile action sends a confirmed authenticated request to `POST /v1/auth/delete-account` and clears the local session after a successful response.

A person who cannot sign in may request deletion through `[PRIVACY EMAIL]` or `[PUBLIC REQUEST FORM URL]`. The final flow must verify account ownership, state what will be deleted or anonymised, identify lawful retention exceptions, explain expected timing, and provide a confirmation or status channel. It must not promise immediate deletion from backups, payment-provider records, security logs or legally required financial records unless that has been verified and approved.

## `/community-guidelines` — UGC and moderation draft

Eazy prohibits illegal content, child sexual abuse or exploitation, threats, harassment, bullying, doxxing, impersonation, hate or targeted abuse, fraud, manipulation of financial features, non-consensual intimate imagery, spam, malware, copyright infringement, and content that creates an unsafe environment. The final policy must be reviewed against applicable law, product scope and age rating.

Eazy should require acceptance of the Terms and Community Guidelines before a user creates or uploads user-generated content. The app already contains report and block paths in relevant areas; the final release must verify report submission, moderation intake, timely response, block enforcement, content removal, repeat-abuse handling, appeal handling, evidence preservation and published contact information.

Incidental mature content, if allowed at all, requires a product-owner and counsel decision, age controls, filtering defaults and store-policy review. The safest V1 launch decision may be to prohibit it.

## `/payments-refunds` — Payments and refunds draft

This page must describe only the payment, wallet, marketplace, bank-transfer and refund products actually enabled in the relevant country and provider mode. It must identify the contracting merchant/operator, supported currencies, charges/fees, authorization flow, pending/failed/reversed transactions, refund eligibility, dispute process, support contact, and provider responsibilities.

The current source contains Paystack integration boundaries and server-side financial safeguards, but that is not proof that Paystack is enabled, that any bank or payment feature is live, or that a refund promise is approved. The final page is blocked on merchant identity, provider activation, product scope, fee/refund decisions and counsel review.

## `/security` — Security contact and practices draft

Security contact: `[SECURITY EMAIL]`
Security reporting process: `[OWNER-APPROVED PROCESS]`
Last updated: `[LAST UPDATED DATE]`

The final page may describe supported reporting channels, responsible disclosure expectations, secret-handling boundaries, session revocation, access control, encryption in transit, provider responsibilities, incident notifications, and the limits of the public description. It must not disclose secrets, internal endpoints, security-sensitive architecture details, or unverified claims about encryption at rest, penetration testing, certification or breach response time.

## Approval gate

Before any of these pages are published, Anthony must approve the exact version, jurisdiction, lawful-basis and retention decisions, support/security channels, payment/refund terms, age/UGC policy and publication date. A qualified lawyer or data-protection professional must review the relevant documents; none has reviewed them yet. The implementation team may then convert approved text into public pages and link them from the app and store listings. Domain and email setup remains in progress and must be verified separately.

## Sources used for this draft

[1]: https://cert.gov.ng/ngcert/resources/Nigeria_Data_Protection_Act_2023.pdf "Nigeria Data Protection Act, 2023 — official government-hosted text"
[2]: https://ndpc.gov.ng/resources/ "Nigeria Data Protection Commission resources"
[3]: https://support.google.com/googleplay/android-developer/answer/13327111?hl=en "Google Play account deletion requirements"
[4]: https://support.google.com/googleplay/android-developer/answer/9876937?hl=en "Google Play User Generated Content policy"
[5]: https://developer.apple.com/app-store/review/guidelines/ "Apple App Store Review Guidelines"
[6]: https://support.google.com/googleplay/android-developer/answer/11926878?hl=en "Google Play target API level requirements"

[7]: https://ndpc.gov.ng/faqs/ "Nigeria Data Protection Commission frequently asked questions"
[8]: https://ndpc.gov.ng/dpco-registration-requirements/ "Nigeria Data Protection Commission DPCO registration and requirements"
