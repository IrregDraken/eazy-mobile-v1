# Assumptions

- The repository integration branch is `main`, identified from `origin/HEAD -> origin/main` and the current checkout.
- All implementation work for this brief will remain on `feature/eazy-wallet-and-app-overhaul`; `main` will not be modified or merged.
- The current backend contract stores and returns wallet amounts as decimal NGN strings and uses numeric database columns; the brief requires integer kobo end-to-end. This is a confirmed migration risk and will be handled additively, with compatibility reviewed before changing existing financial tables.
- The current backend payment PIN contract was six digits with scrypt and a 15-minute lock; this branch moves the request contract to four digits and a 30-minute lock while retaining the same salted scrypt storage format.
- Paystack changes will use test-mode configuration only and will not run against production databases or live keys.
- Missing provider credentials or ambiguous business rules will be implemented behind configuration and recorded here rather than guessed.
- Flutter analysis and tests pass in the restored SDK. The local sandbox is ARM64; Flutter's Android AOT and AAPT2 artifacts are x86_64, so the local release APK build remains host-blocked and should run on the repository's x86_64 GitHub Actions runner.
- The backend lockfile was synchronized in the branch baseline and backend build/tests now pass.
