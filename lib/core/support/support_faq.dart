class SupportFaq {
  const SupportFaq({required this.question, required this.answer});
  final String question;
  final String answer;
}

const supportFaqs = <SupportFaq>[
  SupportFaq(
    question: 'I cannot sign in',
    answer: 'Check that your email is correct, then use the password-reset option. If the account is disabled, contact support and include the email address used for Eazy. Never send a password, verification code or session token.',
  ),
  SupportFaq(
    question: 'My verification code did not arrive',
    answer: 'Check spam and confirm the email address. Request a new code only after the current request has expired or you have reached the resend option. Codes expire and are rate-limited; do not share one with anyone.',
  ),
  SupportFaq(
    question: 'A payment or transfer is wrong',
    answer: 'Do not repeat an ambiguous payment or transfer. Contact support with the Eazy transaction or order reference and the time and currency. Never send a PIN, password, full card number, bank login or verification code. A payment dispute is escalated to the payments owner through the support channel.',
  ),
  SupportFaq(
    question: 'My marketplace order is missing or incorrect',
    answer: 'Open the order details and keep the order reference. Contact support with the order reference, the issue and the relevant time. Do not send full payment credentials or unrelated personal documents.',
  ),
  SupportFaq(
    question: 'I want my personal data deleted',
    answer: 'Use Settings → Delete account when you can sign in. For a privacy request or an account you cannot access, contact the privacy channel. Eazy may need to verify ownership and may retain limited records where required for finance, security or legal obligations.',
  ),
];

String supportReplyFor(String question) {
  final value = question.trim().toLowerCase();
  if (value.isEmpty) return 'Choose a topic above or describe your question in a few words.';
  if (value.contains('payment') || value.contains('transfer') || value.contains('charged') || value.contains('refund')) {
    return supportFaqs[2].answer;
  }
  if (value.contains('order') || value.contains('marketplace') || value.contains('seller') || value.contains('delivery')) {
    return supportFaqs[3].answer;
  }
  if (value.contains('verify') || value.contains('code') || value.contains('otp') || value.contains('email')) {
    return supportFaqs[1].answer;
  }
  if (value.contains('delete') || value.contains('privacy') || value.contains('data')) {
    return supportFaqs[4].answer;
  }
  if (value.contains('sign') || value.contains('login') || value.contains('password') || value.contains('account')) {
    return supportFaqs[0].answer;
  }
  return 'I could not match that to a safe automated answer. Escalate it to support with a short description and a relevant Eazy reference, without sending passwords, codes, tokens or full payment credentials.';
}
