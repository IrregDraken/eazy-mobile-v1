const DRAFT = '<div class="draft-banner" role="note"><strong>Internal working draft — not approved for publication.</strong> Business identity is confirmed as Thony Dynamic Enterprises (RC 2962026), but Anthony\'s approval, professional review, mailbox receipt, hosting/DNS and technical provider verification remain outstanding.</div>';
const contacts = {
  support: 'support@eazy.name.ng',
  privacy: 'privacy@eazy.name.ng',
  legal: 'legal@eazy.name.ng',
  security: 'security@eazy.name.ng'
};
const routes = {
  '/': { title: 'Eazy — Your world, made easier.', render: home },
  '/privacy': { title: 'Privacy notice — Eazy', render: privacy },
  '/terms': { title: 'Terms of use — Eazy', render: terms },
  '/cookies': { title: 'Cookies — Eazy', render: cookies },
  '/support': { title: 'Support — Eazy', render: support },
  '/delete-account': { title: 'Delete your account — Eazy', render: deletion },
  '/community-guidelines': { title: 'Community guidelines — Eazy', render: community },
  '/payments-refunds': { title: 'Payments and refunds — Eazy', render: payments },
  '/security': { title: 'Security — Eazy', render: security }
};

function page(eyebrow, heading, lede, body) {
  return `<section class="prose"><div class="eyebrow">${eyebrow}</div><h1>${heading}</h1><p class="lede">${lede}</p>${DRAFT}${body}</section>`;
}
function linkCards() {
  return `<div class="grid">
    <a class="card card-link" href="/support"><h3>Help & support ↗</h3><p>Safe guidance for accounts, verification, payments, orders and privacy.</p></a>
    <a class="card card-link" href="/privacy"><h3>Privacy ↗</h3><p>What Eazy may process, why it is needed and how to make a request.</p></a>
    <a class="card card-link" href="/delete-account"><h3>Delete account ↗</h3><p>Understand the authenticated in-app path and the unauthenticated request process.</p></a>
  </div>`;
}
function home() {
  return `<section class="hero"><div class="eyebrow">Eazy Mobile V1</div><h1>Your world,<br><span style="color:var(--green)">made easier.</span></h1><p class="lede">Public support, privacy and account information for Eazy. This local preparation site mirrors the routes intended for <strong>eazy.name.ng</strong>.</p>${DRAFT}${linkCards()}<div class="callout warning"><strong>Publication gate.</strong> The operator identity, approved policy text, mailbox routing and public hosting/DNS configuration are still awaiting owner action. Nothing here is represented as legally approved or publicly live.</div><h2>All information routes</h2><div class="route-list">${Object.keys(routes).filter(x => x !== '/').map(x => `<a href="${x}">${x}</a>`).join('')}</div></section>`;
}
function privacy() {
  return page('Privacy', 'A clear view of your data.', 'This working draft explains the categories of personal data Eazy may process and the choices and requests that must be available to users.', `
    <h2>Controller and contact</h2><p><strong>Controller:</strong> Thony Dynamic Enterprises, RC 2962026, 125/130 Nnamdi Azikiwe Street, Idumota, Lagos Island, Lagos State, Nigeria.<br><strong>Initial privacy oversight:</strong> Anthony; no DPO/DPCO has been designated.<br><strong>Privacy contact:</strong> <a href="mailto:${contacts.privacy}">${contacts.privacy}</a> (proposed; inbound receipt unverified).</p>
    <h2>Data Eazy may process</h2><p>Depending on the features you use, Eazy may process account and authentication data, profile data such as name, username, date of birth, biography and avatar, social content and activity, messages and attachments, marketplace and order data, wallet and payment records, notifications and device tokens, location queries, translation requests, Assist sessions, and security/support metadata such as IP address, user-agent, request IDs and rate-limit events.</p>
    <p>The final notice must identify the exact enabled providers and data flows. Possible providers identified from the current source include Firebase Authentication, Resend, Supabase PostgreSQL and Storage, Railway, Paystack if enabled, FCM/APNs if enabled, HERE if enabled, a translation provider if enabled and an AI provider if enabled.</p>
    <h2>Purposes and lawful bases</h2><p>Candidate purposes include providing the requested service, authentication and security, social and messaging features, marketplace and payment execution, abuse prevention, support, reliability and legal obligations. [LEGAL REVIEW REQUIRED: map each purpose to the approved lawful basis for each operating jurisdiction.]</p>
    <h2>Your requests</h2><p>Subject to applicable law and legitimate exceptions, you may request access, correction, deletion, restriction, objection, portability or withdrawal of consent. Contact <a href="mailto:${contacts.privacy}">${contacts.privacy}</a> only after inbound mailbox routing has been configured and verified by the operator.</p>
    <h2>Retention and deletion</h2><p>Eazy’s implemented deletion service removes or anonymises many account-linked records, revokes sessions and push-device records, removes selected content and preserves a deleted-user tombstone plus certain financial or security records where the current service requires it. Exact retention periods, backup expiry, provider propagation and legal-hold exceptions remain [OWNER/COUNSEL REQUIRED].</p>
    <div class="callout warning"><strong>Complaint route pending approval.</strong> For Nigeria, the final policy should explain the applicable Nigeria Data Protection Commission complaint route after the operator/controller status and legal notice are approved.</div>`);
}
function terms() {
  return page('Terms', 'Terms of use for Eazy.', 'These working terms define the sections that must be approved before Eazy is offered to the public.', `
    <p><strong>Operator:</strong> Thony Dynamic Enterprises (RC 2962026).<br><strong>Governing law and venue:</strong> [JURISDICTION — COUNSEL TO APPROVE].<br><strong>Effective date:</strong> [EFFECTIVE DATE].</p>
    <h2>Account and acceptable use</h2><p>Users must provide accurate information, protect account credentials and use Eazy lawfully. The final version must define eligibility, age requirements, account security, suspension, termination and account deletion.</p>
    <h2>Content and community</h2><p>Users retain rights they have in their content but must give Eazy the limited permissions needed to host and display it. Users must follow the <a href="/community-guidelines">Community Guidelines</a>. The final licence, moderation, appeals and dispute language requires approval.</p>
    <h2>Marketplace and financial features</h2><p>Marketplace, wallet, payment, transfer and bank features are subject to availability, provider terms and approved financial disclosures. Eazy must not promise a refund, balance, transfer or order outcome beyond the server and provider records.</p>
    <h2>Availability and responsibility</h2><p>The service may change or be unavailable. The final document must include approved disclaimers, liability limits, dispute handling, third-party-provider terms and contact details.</p>
    <div class="callout warning"><strong>Not approved.</strong> Do not publish these terms until the operator identity, jurisdiction, age threshold, user-content licence, financial terms and refund/cancellation interactions are approved.</div>`);
}
function cookies() {
  return page('Cookies', 'Cookies and similar technologies.', 'This working draft records what must be checked before Eazy makes a public cookie or tracking statement.', `
    <h2>What must be inventoried</h2><p>The final page must identify strictly necessary cookies, analytics, advertising, session, fraud-prevention tools, embedded support widgets, CDN behavior and any third-party scripts used by the deployed website.</p>
    <p>The current Flutter/mobile repository does not prove the cookie set for <strong>eazy.name.ng</strong>. This draft therefore does not claim that Eazy uses cookies or that it uses none.</p>
    <h2>Your choices</h2><p>[OWNER/COUNSEL REQUIRED: confirm consent tooling, withdrawal method, retention and jurisdiction-specific rules before publication.]</p>`);
}
function support() {
  const faq = [
    ['I cannot sign in', 'Check your email and use password reset. If the account is disabled, contact support with the account email. Never send a password, code or session token.'],
    ['My verification code did not arrive', 'Check spam, confirm the address and request a new code through the app. Codes expire and are rate-limited. Do not share them.'],
    ['A payment or transfer is wrong', 'Do not repeat an ambiguous operation. Contact support with the Eazy transaction or order reference, time and currency. Never send a PIN, password, full card number, bank login or code.'],
    ['My marketplace order is missing or incorrect', 'Keep the order reference and contact support with the issue and relevant time. Do not send unrelated personal documents or full payment credentials.'],
    ['I want my data deleted', 'Use Settings → Delete account when signed in. If you cannot sign in, use the privacy channel after the operator has configured and verified inbound routing.']
  ];
  return page('Support', 'Help without the guesswork.', 'Start with the safe answers below. Escalate only the information needed to identify the account, order or transaction.', `
    <div class="card"><h3>Live Chat Coming Soon</h3><p>Live agent chat is not available yet. This page does not create a ticket or claim that a support request has been received.</p></div>
    <h2>Frequently asked questions</h2>${faq.map(([q, a]) => `<details class="faq"><summary>${q}</summary><p>${a}</p></details>`).join('')}
    <h2>Escalation channels</h2><p>These are proposed routing addresses only. The operator must configure and test inbound mailboxes or forwarding before publication.</p>
    <div class="contact-grid">
      <div class="card contact"><span class="contact-icon">✦</span><div><strong>General support</strong><br><a href="mailto:${contacts.support}">${contacts.support}</a></div></div>
      <div class="card contact"><span class="contact-icon">↗</span><div><strong>Payment or transfer dispute</strong><br><a href="mailto:${contacts.support}">${contacts.support}</a></div></div>
      <div class="card contact"><span class="contact-icon">◌</span><div><strong>Privacy or deletion</strong><br><a href="mailto:${contacts.privacy}">${contacts.privacy}</a></div></div>
      <div class="card contact"><span class="contact-icon">◇</span><div><strong>Security report</strong><br><a href="mailto:${contacts.security}">${contacts.security}</a></div></div>
    </div>
    <div class="callout security"><strong>Never send:</strong> passwords, Firebase tokens, one-time codes, payment PINs, private keys, bank logins or full card data.</div>`);
}
function deletion() {
  return page('Account deletion', 'Delete your Eazy account.', 'Eazy provides an authenticated in-app deletion path and a separate privacy request route for people who cannot sign in.', `
    <div class="callout"><strong>In the app:</strong> Open <strong>Settings → Delete account</strong>, review the confirmation, and confirm. The app sends the authenticated request to the existing account-deletion service and clears the local session after success.</div>
    <h2>If you cannot sign in</h2><p>Email <a href="mailto:${contacts.privacy}?subject=Eazy%20privacy%20or%20deletion%20request">${contacts.privacy}</a> with a short request. This address is proposed and must not be described as receiving mail until the operator configures and tests the mailbox or forwarding route.</p>
    <h2>Identity verification</h2><p>The privacy owner must verify that the requester controls the account before acting. Do not send passwords, verification codes, Firebase tokens, payment PINs or full payment credentials by email.</p>
    <h2>What happens</h2><p>The current service removes or anonymises many account-linked relationships and content, deletes push-device and selected service records, anonymises the profile as a deleted-user tombstone, marks the user deleted, records a security event and attempts to remove the Firebase identity. It can block deletion when a wallet balance requires resolution.</p>
    <h2>Processing time and exceptions</h2><p>[OWNER/COUNSEL REQUIRED: approve the response timeframe, backup propagation statement, provider deletion process and retention exceptions.] Some financial, security, fraud-investigation, legal-hold or backup records may need to be retained where required.</p>
    <div class="callout warning"><strong>No email-only deletion claim:</strong> this page does not collect an email and pretend to delete an account. Unauthenticated requests require an approved identity-verification process and an assigned privacy owner.</div>`);
}
function community() {
  return page('Community', 'Make Eazy safer for everyone.', 'These working guidelines define prohibited content and the moderation controls that must be operational before UGC launch.', `
    <h2>Not allowed</h2><p>Eazy prohibits illegal content, child sexual abuse or exploitation, threats, harassment, bullying, doxxing, impersonation, targeted hate, fraud, manipulation of financial features, non-consensual intimate imagery, spam, malware, copyright infringement and content that creates an unsafe environment.</p>
    <h2>Moderation and reporting</h2><p>Users must accept the Terms and Community Guidelines before creating or uploading content. The final release must provide filtering, in-app reporting, user blocking, timely moderation response, removal, repeat-abuse handling, appeals and evidence preservation.</p>
    <h2>Age and mature content</h2><p>[OWNER/COUNSEL REQUIRED: approve minimum age, rating, mature-content policy and filtering defaults. The safest V1 launch decision may be to prohibit sexual or explicit content.]</p>
    <h2>Contact</h2><p>Report safety issues through <a href="/support">Support</a>. Published contact information and response SLA must be configured before store submission.</p>`);
}
function payments() {
  return page('Payments', 'Payments, transfers and refunds.', 'This working page describes the information that must be approved for each enabled financial product; it does not claim that live payments are enabled.', `
    <div class="callout warning"><strong>Provider status:</strong> the source contains Paystack integration boundaries and server-side safeguards, but source code is not proof that a provider account is activated or that live money features are enabled.</div>
    <h2>Before a payment dispute</h2><p>Do not repeat an ambiguous charge or transfer. Keep the Eazy order or transaction reference, exact currency, amount and time. Contact <a href="mailto:${contacts.support}">${contacts.support}</a> after inbound routing is configured. Never send a PIN, password, full card number or bank login.</p>
    <h2>Required final disclosures</h2><p>The approved page must state the contracting merchant/operator, enabled countries and currencies, product scope, charges and fees, authorization flow, pending/failed/reversed states, refund eligibility, cancellation, chargebacks, dispute timing and provider responsibilities.</p>
    <h2>Reconciliation and exceptions</h2><p>The server must remain authoritative for order totals and ledger state. Pending or ambiguous provider outcomes must not be presented as successful from a client assertion. [FINANCE/COUNSEL REQUIRED: approve refund and dispute policy.]</p>`);
}
function security() {
  return page('Security', 'Report a security concern responsibly.', 'Use the proposed security route for vulnerabilities or account-safety concerns, without sending secrets or live credentials.', `
    <h2>Security contact</h2><p><a href="mailto:${contacts.security}">${contacts.security}</a></p><p>This address is proposed only. The operator must configure and test inbound routing before publication.</p>
    <h2>What to include</h2><p>Provide a concise description, affected feature, safe reproduction steps, timestamps and non-sensitive evidence. Do not include passwords, tokens, private keys, payment credentials or personal data that is not necessary.</p>
    <h2>What happens next</h2><p>[OWNER-APPROVED PROCESS REQUIRED: assign security owner, acknowledgement target, severity handling, evidence retention, coordinated disclosure and incident-notification procedure.]</p>
    <div class="callout security"><strong>Do not probe production destructively.</strong> Testing must be authorized, bounded and non-destructive.</div>`);
}

function render() {
  const path = window.location.pathname.replace(/\/+$/, '') || '/';
  const route = routes[path] || { title: 'Page not found — Eazy', render: () => page('404', 'That route is not ready.', 'Use the navigation below to return to a prepared Eazy route.', '<p><a class="button" href="/">Return home</a></p>') };
  document.title = route.title;
  document.querySelector('#app').innerHTML = route.render();
  document.querySelector('#app').focus();
}
document.querySelector('.menu-toggle').addEventListener('click', (event) => {
  const button = event.currentTarget;
  const nav = document.querySelector('#site-nav');
  const open = nav.classList.toggle('open');
  button.setAttribute('aria-expanded', String(open));
});
window.addEventListener('popstate', render);
render();
