const contacts = {
  support: 'support@eazy.name.ng',
  privacy: 'privacy@eazy.name.ng',
  legal: 'legal@eazy.name.ng',
  security: 'security@eazy.name.ng'
};
const operator = 'Thony Dynamic Enterprises';
const registration = 'RC 2962026';
const address = '125/130 Nnamdi Azikiwe Street, Idumota, Lagos Island, Lagos State, Nigeria';
const updated = '11 October 2026';
const routes = {
  '/': { title: 'Eazy | Your world, made easier', render: home },
  '/privacy': { title: 'Privacy Policy | Eazy', render: privacy },
  '/terms': { title: 'Terms of Service | Eazy', render: terms },
  '/cookies': { title: 'Cookies and Similar Technologies | Eazy', render: cookies },
  '/support': { title: 'Support | Eazy', render: support },
  '/delete-account': { title: 'Delete Your Eazy Account', render: deletion },
  '/community-guidelines': { title: 'Community Guidelines | Eazy', render: community },
  '/payments-refunds': { title: 'Payments and Refunds | Eazy', render: payments },
  '/security': { title: 'Security | Eazy', render: security }
};
function page(eyebrow, heading, lede, body) {
  return `<section class="prose"><div class="eyebrow">${eyebrow}</div><h1>${heading}</h1><p class="lede">${lede}</p><p class="meta">Last updated: ${updated}</p>${body}</section>`;
}
function linkCards() {
  return `<div class="grid">
    <a class="card card-link" href="/support/"><h3>Help & support ↗</h3><p>Account, verification, orders, payments and safety.</p></a>
    <a class="card card-link" href="/privacy/"><h3>Privacy ↗</h3><p>Understand data handling and exercise your privacy rights.</p></a>
    <a class="card card-link" href="/delete-account/"><h3>Delete account ↗</h3><p>Find the in-app deletion path and request help if locked out.</p></a>
  </div>`;
}
function home() {
  return `<section class="hero"><div class="eyebrow">Eazy Mobile</div><h1>Your world,<br><span style="color:var(--green)">made easier.</span></h1><p class="lede">Eazy brings social connection, messaging, marketplace tools and helpful everyday services into one place.</p>${linkCards()}<h2>Helpful information</h2><div class="route-list">${Object.keys(routes).filter(x => x !== '/').map(x => `<a href="${x}/">${x.replace(/^\//,'').replaceAll('-',' ')}</a>`).join('')}</div><p class="meta">Operated by ${operator} (${registration}), Nigeria.</p></section>`;
}
function privacy() {
  return page('Privacy policy', 'Your data. Your choices.', 'This policy explains how Eazy handles personal information when you use the Eazy mobile application and related services.', `
    <h2>1. Who operates Eazy</h2><p>Eazy is operated by <strong>${operator}</strong> (${registration}), at ${address} (“Eazy”, “we”, “us” or “our”). For privacy requests, contact <a href="mailto:${contacts.privacy}">${contacts.privacy}</a>. For general support, contact <a href="mailto:${contacts.support}">${contacts.support}</a>.</p>
    <h2>2. Information we process</h2><p>Depending on which features you use and which services are enabled, we may process:</p><ul><li><strong>Account and profile:</strong> email address, authentication identifiers, username, display name, profile details, avatar and account preferences.</li><li><strong>Content and communications:</strong> posts, comments, reactions, messages, media you upload, reports, and information needed to deliver and moderate content.</li><li><strong>Marketplace and transactions:</strong> listings, cart and order details, transaction references, amounts, currency, status and payment-provider responses. Payment card or bank credentials should be entered only into the authorised provider flow, not sent to Eazy by email or chat.</li><li><strong>Device and service data:</strong> device tokens for notifications, app version, diagnostic events, request identifiers, IP address and security signals needed to protect accounts and operate the service.</li><li><strong>Optional feature data:</strong> location when you use a location-dependent feature; content submitted for translation or Eazy Assist when those features are enabled; and information you choose to include in support requests.</li></ul>
    <h2>3. How we use information</h2><p>We use information to create and secure accounts; provide social, chat, marketplace and other requested features; process and reconcile orders or payments where enabled; deliver notifications; respond to support and privacy requests; prevent fraud, spam, abuse and security incidents; troubleshoot and improve reliability; enforce our terms; and comply with legal obligations.</p>
    <h2>4. Legal grounds</h2><p>Where applicable data-protection law requires a legal basis, processing may be based on performing our agreement with you, our legitimate interests in operating and securing Eazy, your consent for optional processing, and compliance with legal obligations. We will request consent where required and you may withdraw consent without affecting processing that was lawful before withdrawal.</p>
    <h2>5. Sharing and service providers</h2><p>We do not sell personal information. We may share information with service providers that help us host and secure Eazy, authenticate users, store data and media, send email or notifications, process payments, provide location or translation functions, or power an AI feature you choose to use. Depending on feature availability and configuration, providers may include Firebase/Google, Railway, Supabase, Resend, Paystack, Apple, and other providers expressly used by the feature. We share only information reasonably needed for the relevant purpose, subject to applicable agreements and law. We may also disclose information when legally required or necessary to protect users, the service or others.</p>
    <h2>6. International processing</h2><p>Our service providers may process information in countries other than the country where you live. Where required, we will use appropriate safeguards for international transfers and provide further information on request.</p>
    <h2>7. Retention</h2><p>We retain information for as long as needed to provide the service, maintain account and transaction records, address disputes, protect security, enforce our terms and meet legal obligations. Retention varies by data type and purpose. When an account is deleted, we remove or de-identify associated information where feasible, subject to records that must be retained for legal, financial, security or fraud-prevention reasons and to backup systems completing their normal rotation. We do not promise immediate removal from every backup or independent provider system.</p>
    <h2>8. Your choices and rights</h2><p>Depending on your location and applicable law, you may request access to, correction of, deletion of, restriction of or objection to certain processing; request a portable copy; or withdraw consent. You can manage available account preferences in Eazy and request account deletion using <a href="/delete-account/">this page</a>. Contact <a href="mailto:${contacts.privacy}">${contacts.privacy}</a> for privacy requests. We may need to verify your identity before responding.</p>
    <h2>9. Children</h2><p>Eazy is not designed for children under 13, and users must meet the minimum age required by applicable law to use the service. If a parent or guardian believes a child has provided personal information contrary to this policy, contact our privacy team so we can assess and address the request.</p>
    <h2>10. Security</h2><p>We use technical and organisational measures intended to protect information, including access controls and secure transmission where supported. No service can guarantee absolute security. Report suspected vulnerabilities or account compromise through <a href="/security/">our security page</a>.</p>
    <h2>11. Changes and complaints</h2><p>We may update this policy as Eazy changes. The updated date above identifies the latest published version. If you have a concern, contact us first at <a href="mailto:${contacts.privacy}">${contacts.privacy}</a>. You may also contact the relevant data-protection authority, including the Nigeria Data Protection Commission where applicable.</p>
    <h2>12. Contact</h2><p><strong>${operator}</strong><br>${address}<br>Privacy: <a href="mailto:${contacts.privacy}">${contacts.privacy}</a><br>Legal: <a href="mailto:${contacts.legal}">${contacts.legal}</a></p>`);
}
function terms() {
  return page('Terms of service', 'The rules for using Eazy.', 'By accessing or using Eazy, you agree to these Terms. If you do not agree, do not use the service.', `
    <h2>1. Operator and eligibility</h2><p>Eazy is operated by ${operator} (${registration}), ${address}. You must be at least 13 years old and meet any higher minimum age required by local law. If you are not legally able to agree to these Terms, do not use Eazy.</p>
    <h2>2. Your account</h2><p>Provide accurate information, keep your sign-in credentials and verification codes private, and promptly secure an account you believe has been compromised. You are responsible for activity authorised through your account, except where applicable law provides otherwise. We may suspend or restrict access to protect users, investigate abuse or comply with law.</p>
    <h2>3. Your content and permission to operate</h2><p>You retain rights you hold in content you create or upload. You grant Eazy a non-exclusive, worldwide, royalty-free licence to host, store, reproduce, adapt for technical compatibility, display and distribute that content only as reasonably necessary to operate, secure and provide the features you choose, including showing posts to your selected audience. This licence ends when the content is removed from active service, except for temporary backup copies, content already shared by others where removal is not technically possible, or records retained for legal or security reasons.</p>
    <h2>4. Acceptable use</h2><p>You must follow our <a href="/community-guidelines/">Community Guidelines</a>. Do not use Eazy for unlawful activity, fraud, harassment, threats, impersonation, privacy invasion, malware, spam, exploitation, infringement, manipulation of payment flows or interference with service security. Do not attempt to access another person's account or data without permission.</p>
    <h2>5. Marketplace, payments and wallet-related features</h2><p>Features related to listings, orders, payments, transfers or balances may depend on eligibility, region and provider availability. Displayed statuses can change while a provider confirms an operation. Do not repeat a payment or transfer if its status is uncertain. The applicable provider may impose separate terms. Eazy does not promise that every feature is available in every location, and a wallet interface must not be treated as a bank account unless expressly stated in a separate approved agreement. See <a href="/payments-refunds/">Payments and Refunds</a>.</p>
    <h2>6. Safety, reports and moderation</h2><p>You can report content or users through available in-app controls. We may remove content, limit features, suspend or terminate accounts when reasonably necessary to enforce these Terms, protect users or comply with law. Where appropriate and feasible, we may provide a route to appeal a moderation decision.</p>
    <h2>7. Third-party services</h2><p>Some features rely on third-party services. Their availability and processing are subject to their own terms and privacy practices. We are not responsible for independent third-party services to the extent permitted by law, but this does not remove rights you have under mandatory law.</p>
    <h2>8. Availability and changes</h2><p>We may update, suspend or discontinue features for maintenance, security, legal or operational reasons. We will provide notice where required by law. We do not guarantee uninterrupted or error-free service.</p>
    <h2>9. Account deletion</h2><p>You can initiate account deletion in the app settings or follow the process at <a href="/delete-account/">Delete Account</a>. Deletion is subject to identity verification and lawful retention requirements. Outstanding balances, unsettled orders or legal obligations may need to be resolved before some records can be removed.</p>
    <h2>10. Disclaimers and liability</h2><p>To the extent permitted by applicable law, Eazy is provided on an “as available” basis. Nothing in these Terms excludes or limits liability or consumer rights that cannot lawfully be excluded or limited. Any liability limitation will apply only to the extent permitted by law.</p>
    <h2>11. Governing law and contact</h2><p>These Terms are governed by the laws of the Federal Republic of Nigeria, subject to mandatory consumer-protection rules that apply to you. Courts with competent jurisdiction in Nigeria may hear disputes, without depriving consumers of any mandatory rights. Questions: <a href="mailto:${contacts.legal}">${contacts.legal}</a>. Support: <a href="mailto:${contacts.support}">${contacts.support}</a>.</p>
    <p class="meta">Operator: ${operator}, ${registration}. ${address}</p>`);
}
function cookies() {
  return page('Cookies', 'Cookies and similar technologies.', 'This website is designed to provide policy and support information without advertising trackers.', `
    <h2>Website storage</h2><p>The public information pages do not intentionally set advertising or analytics cookies. The site may use essential technical mechanisms required by its hosting provider to deliver pages securely. Hosting and security infrastructure may process request metadata such as IP address, requested path, user agent and timestamps in server logs.</p>
    <h2>Mobile application</h2><p>The Eazy mobile application may use device storage, secure local storage, notification tokens and similar technologies to maintain sessions, protect credentials and provide features you enable. Mobile-platform permissions are handled by the operating system and app settings.</p>
    <h2>Third-party links</h2><p>Links to external providers open services governed by their own privacy and cookie policies. We do not control their storage technologies.</p>
    <h2>Questions</h2><p>Contact <a href="mailto:${contacts.privacy}">${contacts.privacy}</a> for questions about this notice.</p>`);
}
function support() {
  const faq = [
    ['I cannot sign in', 'Check that you entered the correct email address and use the password-reset or sign-in recovery option available in the app. Never share your password or verification code.'],
    ['My verification email did not arrive', 'Check your spam folder, confirm that your email address is correct, wait briefly and request a new message from the app. Never share one-time codes.'],
    ['A payment or transfer looks wrong', 'Do not repeat an operation whose status is unclear. Keep the Eazy transaction or order reference, amount, currency and approximate time. Never email a PIN, password, full card number or bank login.'],
    ['My order is missing', 'Keep the order reference and describe what happened and when. Include only information needed to investigate the order.'],
    ['I want to delete my account', 'When signed in, open Settings and choose Delete account. If you cannot sign in, contact privacy@eazy.name.ng for identity-verified assistance.']
  ];
  return page('Support', 'How can we help?', 'For account, marketplace, payment, privacy and safety questions, contact the appropriate Eazy team.', `
    <div class="contact-grid">
      <div class="card contact"><span class="contact-icon">✦</span><div><strong>General support</strong><br><a href="mailto:${contacts.support}">${contacts.support}</a></div></div>
      <div class="card contact"><span class="contact-icon">◌</span><div><strong>Privacy and account deletion</strong><br><a href="mailto:${contacts.privacy}">${contacts.privacy}</a></div></div>
      <div class="card contact"><span class="contact-icon">◇</span><div><strong>Legal enquiries</strong><br><a href="mailto:${contacts.legal}">${contacts.legal}</a></div></div>
      <div class="card contact"><span class="contact-icon">↗</span><div><strong>Security reports</strong><br><a href="mailto:${contacts.security}">${contacts.security}</a></div></div>
    </div>
    <h2>Frequently asked questions</h2>${faq.map(([q, a]) => `<details class="faq"><summary>${q}</summary><p>${a}</p></details>`).join('')}
    <div class="callout security"><strong>Keep your account safe.</strong> Eazy support will never need your password, one-time code, payment PIN, private key or bank login.</div>
    <p>If you contact us, include the account email or relevant order reference and a concise description. Do not include unnecessary identity documents or full payment credentials.</p>`);
}
function deletion() {
  return page('Account deletion', 'Delete your Eazy account.', 'You can request deletion even if you no longer have access to the app.', `
    <h2>Option 1: In the Eazy app</h2><ol><li>Sign in to the account you want to delete.</li><li>Open Settings and choose <strong>Delete account</strong>.</li><li>Read the confirmation and submit the request.</li><li>Keep the confirmation shown by the app for your records.</li></ol>
    <h2>Option 2: If you cannot sign in</h2><p>Email <a href="mailto:${contacts.privacy}?subject=Eazy%20account%20deletion%20request">${contacts.privacy}</a> from the email address associated with your Eazy account, if possible. Write “Account deletion request” in the subject and provide your username or other non-secret account identifier. Do not send passwords, verification codes, tokens, payment PINs or full card details.</p>
    <h2>Identity verification</h2><p>To protect your account, we may ask for proportionate information to verify that you control it. We will not ask for your password or one-time authentication code by email.</p>
    <h2>What is deleted</h2><p>After a valid request is verified, we delete or de-identify account information and associated content where feasible, revoke active sessions and remove related device registrations, subject to technical limitations and applicable law. Some records may be retained when required for legal, accounting, fraud-prevention, security or dispute purposes. Backup copies may persist until normal backup rotation. Some transactions, open orders or unresolved balances may need to be settled or reviewed before all associated records can be deleted.</p>
    <h2>Timing and confirmation</h2><p>We will assess a verified request and process it within the period required by applicable law. If additional time or information is needed, we will explain why and what happens next. Contact <a href="mailto:${contacts.privacy}">${contacts.privacy}</a> for questions or to follow up.</p>
    <p><strong>Operator:</strong> ${operator} (${registration}), ${address}.</p>`);
}
function community() {
  return page('Community guidelines', 'Help keep Eazy safe.', 'These guidelines apply to posts, comments, profiles, messages, marketplace activity and other user-generated content on Eazy.', `
    <h2>Prohibited behaviour</h2><ul><li>Threats, targeted harassment, bullying, stalking or incitement to violence.</li><li>Hate or dehumanising abuse targeting protected characteristics.</li><li>Sexual exploitation, child sexual abuse material, grooming or non-consensual intimate imagery.</li><li>Doxxing, impersonation, identity theft, scams, deceptive listings or payment manipulation.</li><li>Malware, phishing, spam, coordinated inauthentic activity or attempts to bypass security controls.</li><li>Content that unlawfully infringes another person's intellectual-property or privacy rights.</li><li>Illegal goods, services or activity, and attempts to use Eazy to facilitate harm.</li></ul>
    <h2>Respect and consent</h2><p>Share only content you have the right to share. Respect privacy, consent and other people's boundaries. Do not publish another person's personal information without a lawful basis or permission.</p>
    <h2>Marketplace integrity</h2><p>Listings and offers must be accurate and lawful. Do not misrepresent items, manipulate prices or orders, impersonate buyers or sellers, or request sensitive payment credentials outside an authorised provider flow.</p>
    <h2>Reporting and enforcement</h2><p>Use in-app reporting and blocking controls where available, or contact <a href="mailto:${contacts.support}">${contacts.support}</a>. We may remove content, restrict functionality or suspend accounts based on severity, evidence, repeated behaviour, safety risk and applicable law. Where feasible, users may request review of an enforcement decision.</p>
    <h2>Urgent danger</h2><p>If someone is in immediate danger, contact local emergency services. Do not rely on an app report as an emergency-response channel.</p>
    <h2>Contact</h2><p>Questions about these guidelines: <a href="mailto:${contacts.legal}">${contacts.legal}</a>.</p>`);
}
function payments() {
  return page('Payments and refunds', 'Understand a payment before you repeat it.', 'This page explains how to raise a payment or order issue. The exact options depend on the feature, provider, transaction status and applicable law.', `
    <h2>Before retrying</h2><p>If a payment, transfer or order is pending or unclear, do not immediately repeat it. Check the transaction status in Eazy and retain the order or transaction reference, amount, currency and time. A provider confirmation may take time to reconcile.</p>
    <h2>Report an issue</h2><p>Contact <a href="mailto:${contacts.support}">${contacts.support}</a> with the reference and a concise description. Never send your password, payment PIN, one-time code, full card number, bank login or private key.</p>
    <h2>Refunds and cancellations</h2><p>Eligibility and timing depend on the product or order, whether the payment was completed, the merchant or seller involved, the payment provider's process and applicable consumer law. If a refund is approved, the return path and timing may depend on the original payment method and provider. We will not represent a refund as completed until the relevant transaction state supports that status.</p>
    <h2>Errors, disputes and unauthorised activity</h2><p>Report suspected unauthorised activity promptly. We may ask for non-secret details needed to investigate and may coordinate with the relevant provider. You should also contact your bank or payment provider where appropriate. Do not send sensitive credentials by email.</p>
    <h2>Service availability</h2><p>Payment, wallet, transfer and marketplace features may not be available in all regions or at all times. A feature shown in the app does not guarantee that a provider has activated live processing for your account or location.</p>
    <h2>Contact</h2><p>Support: <a href="mailto:${contacts.support}">${contacts.support}</a><br>Legal: <a href="mailto:${contacts.legal}">${contacts.legal}</a></p>`);
}
function security() {
  return page('Security', 'Report a security concern.', 'We welcome responsible reports that help protect Eazy users and service integrity.', `
    <h2>Contact</h2><p>Email <a href="mailto:${contacts.security}?subject=Eazy%20security%20report">${contacts.security}</a> with a concise description, affected feature, safe reproduction steps and timestamps. Do not include passwords, one-time codes, private keys, payment credentials or unnecessary personal data.</p>
    <h2>Responsible testing</h2><p>Do not access another person's data, disrupt service, run destructive tests, use social engineering or perform testing beyond your authorisation. Stop if you encounter real user data and report what happened without copying more information than necessary.</p>
    <h2>Response</h2><p>We will assess reports based on severity, reproducibility, impact and available information. Please allow reasonable time for investigation and remediation before public disclosure. Do not use the security address for general support, account recovery or urgent emergencies.</p>
    <h2>Account compromise</h2><p>If you believe your account is compromised, secure your email account, use the available recovery flow and contact <a href="mailto:${contacts.support}">${contacts.support}</a>. Never share a password or verification code with anyone.</p>`);
}
function render() {
  const path = window.location.pathname.replace(/\/+$/, '') || '/';
  const route = routes[path] || { title: 'Page not found | Eazy', render: () => page('404', 'Page not found', 'The page you requested does not exist.', '<p><a class="button" href="/">Return home</a></p>') };
  document.title = route.title;
  document.querySelector('#app').innerHTML = route.render();
}
const menu = document.querySelector('.menu-toggle');
if (menu) menu.addEventListener('click', (event) => {
  const button = event.currentTarget;
  const nav = document.querySelector('#site-nav');
  const open = nav.classList.toggle('open');
  button.setAttribute('aria-expanded', String(open));
});
window.addEventListener('popstate', render);
render();
