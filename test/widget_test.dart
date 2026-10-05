import 'package:flutter_test/flutter_test.dart';
import 'package:eazy_mobile_v1/features/assist/assist_page.dart';
import 'package:eazy_mobile_v1/features/location/location_page.dart';
import 'package:eazy_mobile_v1/features/translation/translation_page.dart';
import 'package:eazy_mobile_v1/features/notifications/notifications_page.dart';
import 'package:eazy_mobile_v1/features/settings/settings_page.dart';
import 'package:eazy_mobile_v1/features/security/security_page.dart';

void main(){
 testWidgets('production utility surfaces build', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: AssistPage()));
  expect(find.text('Eazy Assist'), findsOneWidget);
  await tester.pumpWidget(const MaterialApp(home: TranslationPage()));
  expect(find.text('Translation'), findsOneWidget);
  await tester.pumpWidget(const MaterialApp(home: LocationPage()));
  expect(find.text('Location'), findsOneWidget);
  await tester.pumpWidget(const MaterialApp(home: NotificationsPage()));
  await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
  await tester.pumpWidget(const MaterialApp(home: SecurityPage()));
 });
}
