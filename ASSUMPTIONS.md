# Assumptions

- The repository integration branch is `main`, identified from `origin/HEAD -> origin/main` and the current checkout.
- All implementation work for this brief will remain on `feature/eazy-wallet-and-app-overhaul`; `main` will not be modified or merged.
- The current backend contract stores and returns wallet amounts as decimal NGN strings and uses numeric database columns; the brief requires integer kobo end-to-end. This is a confirmed migration risk and will be handled additively, with compatibility reviewed before changing existing financial tables.
- The current backend payment PIN contract is six digits with scrypt and a 15-minute lock; the brief requires four digits and a 30-minute lock. Existing users and migration compatibility must be preserved while moving to the requested contract.
- Paystack changes will use test-mode configuration only and will not run against production databases or live keys.
- Missing provider credentials or ambiguous business rules will be implemented behind configuration and recorded here rather than guessed.
- The cloned repository does not include an installed Flutter SDK in this sandbox, so Flutter validation is blocked until a compatible SDK is supplied; no claim of Flutter test/build success will be made meanwhile.
- The backend `package.json` and `package-lock.json` are currently out of sync, so Node dependency installation and backend validation are blocked until the lockfile is regenerated and reviewed.
