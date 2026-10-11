import 'package:flutter_test/flutter_test.dart';
import 'package:eazy_mobile_v1/core/support/support_faq.dart';

void main() {
  test('payment questions route to safe payment guidance', () {
    final answer = supportReplyFor('I was charged twice for a payment');
    expect(answer, contains('Do not repeat an ambiguous payment'));
    expect(answer, isNot(contains('balance')));
  });

  test('privacy questions route to deletion guidance', () {
    expect(supportReplyFor('delete my data'), contains('Settings → Delete account'));
  });

  test('unknown questions escalate without claiming a ticket was created', () {
    final answer = supportReplyFor('Can someone do something unusual?');
    expect(answer, contains('Escalate it to support'));
    expect(answer, isNot(contains('ticket has been created')));
  });
}
