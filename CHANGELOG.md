# Changelog

## Unreleased — wallet and app overhaul

- Created isolated feature branch `feature/eazy-wallet-and-app-overhaul` from `main`.
- Recorded initial repository assumptions and follow-up findings.
- No production data, provider configuration, or live payment settings changed.
- Added Paystack DVA assignment through `/dedicated_account/assign`, required NG activation fields, provider-email webhook reconciliation, and the additive `provider_email` migration.
- Added a wallet activation form with filterable bank selection and server-gated money actions until DVA activation is confirmed.
- Changed payment PIN creation, authorization, and lockout messaging to four digits and a 30-minute lockout.
- Flutter tests pass; backend TypeScript build and all runnable tests pass. Local release APK packaging is delegated to x86_64 CI because this host is ARM64.
