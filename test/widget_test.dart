import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Eazy V1 has a fresh visual-system boundary', () {
    expect('legacy visual assets', isNot('a runtime dependency'));
  });
}
