# Eazy public website

This is the public-facing Eazy support and policy site, built as a dependency-free static website.

## Pages

- `/` — Eazy information hub
- `/privacy/` — Privacy Policy
- `/terms/` — Terms of Service
- `/cookies/` — Cookies and Similar Technologies
- `/support/` — Support contacts and common questions
- `/delete-account/` — Account deletion instructions
- `/community-guidelines/` — User content and safety rules
- `/payments-refunds/` — Payment, transfer, order and refund information
- `/security/` — Security reporting guidance

## Business and contacts

Operator: **Thony Dynamic Enterprises**, RC 2962026, Lagos State, Nigeria.

- Support: support@eazy.name.ng
- Privacy and deletion: privacy@eazy.name.ng
- Legal: legal@eazy.name.ng
- Security: security@eazy.name.ng

## Hosting

The GitHub Actions workflow `.github/workflows/publish-site.yml` validates the content and deploys `public-site/` to GitHub Pages on updates to the validation branch. `public-site/CNAME` configures the intended custom domain `eazy.name.ng`.

For the custom domain to resolve, the repository must permit GitHub Pages deployments and the DNS zone managed at the current DNS provider must contain GitHub's currently documented apex A/AAAA records (or a supported ALIAS/ANAME) and any desired `www` record. Keep the existing MX, SPF, DKIM and DMARC records intact. DNS changes are not made by this repository workflow. Confirm HTTPS issuance and test all paths externally after DNS propagation.

## Publication notes

These pages are prepared as operational policy text from the current Eazy V1 feature set and known service boundaries. They are not a substitute for jurisdiction-specific legal advice. The operator should review the legal basis, age/eligibility rules, payment scope, retention practices and third-party provider list against actual production configuration. Do not state a provider or feature is active merely because source code contains an integration boundary.

## Local preview

Run `python3 public-site/server.py` from the repository root if the local preview server is available. Alternatively serve this directory with a static web server that supports directory index files.
