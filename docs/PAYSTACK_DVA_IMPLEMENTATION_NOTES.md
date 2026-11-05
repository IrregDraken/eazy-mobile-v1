# Paystack DVA implementation notes

Paystack’s current documentation confirms that the single-step Nigerian Dedicated Virtual Account flow uses `POST /dedicated_account/assign`. The request may include `email`, `first_name`, `middle_name`, `last_name`, `phone`, `preferred_bank`, `country`, and, for required-compliance business categories, `account_number`, `bvn`, and `bank_code`. Paystack documents `test-bank` as the test-mode preferred bank. The assignment is asynchronous, so the initial response is an in-progress acknowledgement and the account must be completed from webhook events.

The relevant lifecycle events are `customeridentification.success`, `customeridentification.failed`, `dedicatedaccount.assign.success`, and `dedicatedaccount.assign.failed`. Incoming bank deposits are confirmed with `charge.success`; the server must credit the ledger only after validating the mapped account, amount, currency, and an idempotency key derived from the provider reference.

Paystack webhook authenticity is verified from the raw request body with HMAC-SHA512 using the secret key and the `x-paystack-signature` header. The current repository already preserves a raw body and verifies the signature before dispatching the bank webhook handler.

The outgoing transfer API uses integer kobo for NGN and accepts `source: balance`, a recipient code, amount, currency, reference, and optional reason. Provider transfer status can be `pending`, `success`, `failed`, or `reversed`; the wallet reservation must remain pending until provider confirmation and must be reversed exactly once on failure or reversal.

Sources: [1] [2] [3] [4]

## References

[1]: https://paystack.com/docs/payments/dedicated-virtual-accounts/ "Paystack Dedicated Virtual Accounts"
[2]: https://paystack.com/docs/api/dedicated-virtual-account/ "Paystack Dedicated Virtual Account API"
[3]: https://paystack.com/docs/payments/webhooks/ "Paystack Webhooks"
[4]: https://paystack.com/docs/api/transfer/ "Paystack Transfers API"
