# Assumptions

- The repository integration branch is `main`, identified from `origin/HEAD -> origin/main` and the current checkout.
- All implementation work for this brief will remain on `feature/eazy-wallet-and-app-overhaul`; `main` will not be modified or merged.
- Wallet money values will remain integer kobo values at backend boundaries unless the existing repository contract proves otherwise; any conflict will be documented before implementation.
- Paystack changes will use test-mode configuration only and will not run against production databases or live keys.
- Missing provider credentials or ambiguous business rules will be implemented behind configuration and recorded here rather than guessed.
