# Follow-ups

These items were observed during the initial audit but are not being silently fixed outside the uploaded brief’s scope:

- The current database schema uses decimal numeric monetary columns across wallets, ledger, transactions, products and orders; a full end-to-end integer-kobo migration needs a dedicated compatibility and data-migration review.
- The current payment PIN implementation is six digits with scrypt and a 15-minute lock, while the new brief requests four digits and a 30-minute lock. Existing-user migration and recovery behavior need explicit testing.
- The reset sandbox does not contain a Flutter SDK, so Flutter tests, analyzer, Android builds and iOS project validation cannot yet run here.
- The backend package manifest and lockfile are inconsistent; dependency regeneration is tracked as a separate maintenance workstream.
- Store/legal materials, live provider credentials, cloud iOS signing, and authenticated end-to-end device testing remain external release gates.
