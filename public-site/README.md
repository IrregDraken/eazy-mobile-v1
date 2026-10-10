# Eazy public website preparation

This directory is a standalone, dependency-free static website prepared from the internal legal drafts and the in-app Help & Support experience. It is **not approved for publication** and has not been deployed.

## Local preview

From the repository root:

```sh
python3 public-site/server.py
```

The included `site.js` renders the route selected by `window.location.pathname`. For local path testing, use the supplied `server.py` fallback server or a static host configured to rewrite page routes to `/index.html` while serving `/site.css`, `/site.js` and `/manus-routes.json` directly.

## Routes

- `/`
- `/privacy`
- `/terms`
- `/cookies`
- `/support`
- `/delete-account`
- `/community-guidelines`
- `/payments-refunds`
- `/security`

`/manus-routes.json` is the source-of-truth route manifest for preview tooling.

## Hosting decision still required

The repository currently deploys the Node/Express backend to Railway and contains a Flutter web shell, but no public static-site host configuration. The website can be hosted by a static host or served by a separately configured web service. The owner must choose the host and authorize deployment before any production change.

The host must provide:

1. HTTPS for `eazy.name.ng` and `www.eazy.name.ng` if `www` is used.
2. SPA/static fallback from each requested page route to `index.html`.
3. Direct asset serving for `site.css`, `site.js` and `manus-routes.json`.
4. A redirect or canonical policy for HTTP and `www`.
5. Access logs and a rollback path.
6. No analytics, cookies, support widget or third-party script unless inventoried and added to the cookie/privacy review.

## DNS investigation and recommended record shape

Public Cloudflare and Google DNS-over-HTTPS checks returned an SOA authority for `eazy.name.ng` but no A answer. The authoritative nameserver shown in the SOA is `ns8.cloudoon.com` with `hostmaster.cloudoon.com`; this was observed, not changed.

An A record is not automatically the correct answer. The final record depends on the selected host:

- If the selected host supplies a fixed IPv4 address, add the host-recommended apex `A` record and its exact TTL.
- If the selected host supplies an IPv6 address, add the host-recommended apex `AAAA` record as well.
- If the selected host supplies a canonical hostname, use the host-recommended `CNAME` for a supported subdomain such as `www`; apex CNAME/ALIAS/ANAME behavior depends on the DNS provider and must follow that provider’s instructions.
- If the host supports apex aliasing, use the host’s documented `ALIAS`, `ANAME` or flattening record rather than inventing an A record.
- Add the host-recommended `www` record and redirect/canonical behavior only after the host is selected.

Public DNS currently returns an MX record for `eazy.name.ng` pointing to `10 inbound-smtp.eu-west-1.amazonaws.com.`; its ownership and relationship to the configured email provider must be confirmed before any change. Public checks returned `_dmarc.eazy.name.ng TXT "v=DMARC1; p=none;"` and `resend._domainkey.eazy.name.ng` as a TXT public key. No apex TXT record was returned. Before applying changes, export or record the existing zone and inspect all current records, especially MX, SPF, DKIM and DMARC records. Do not replace the zone or nameservers. A website record must not remove or overwrite the existing MX, DMARC or Resend DKIM records. Any proposed DNS diff must be reviewed against the current Resend account before authorization.

## Publication gates

Before publication, replace the unresolved facts in the internal legal drafts and obtain owner/counsel approval for:

- Official business/operator name, registered name/RC number if applicable, address and jurisdictions.
- Legal approver and privacy/DPO/DPCO owner.
- Privacy, support, legal and security mailbox ownership, inbound routing and response SLAs.
- Effective and last-updated dates.
- Lawful-basis map, provider/subprocessor regions and enabled feature list.
- Retention schedule, deletion exceptions, backup/provider propagation and legal hold.
- Age threshold, content policy and UGC moderation/appeal process.
- Payment products, currencies, fees, cancellation, refunds, chargebacks and merchant identity.
- Cookie/analytics/support-widget inventory.

After approval, publish the approved text, test every route without authentication over HTTPS, verify app/store links, and only then update the production domain and store metadata.
