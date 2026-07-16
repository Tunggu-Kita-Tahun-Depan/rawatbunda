import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tunggukitatahundepan2026/app.dart';

void main() {
  testWidgets('Intake screen loads with Send Referral button', (WidgetTester tester) async {
    await tester.pumpWidget(const IbuRujukApp(useSupabase: false));

    expect(find.text('Bidan Intake'), findsOneWidget);
    expect(find.text('Send Referral'), findsOneWidget);
  });

  testWidgets('Safety flag banner appears for severe BP + symptom', (WidgetTester tester) async {
    await tester.pumpWidget(const IbuRujukApp(useSupabase: false));

    await tester.enterText(find.widgetWithText(TextField, 'Systolic BP'), '165');
    await tester.enterText(find.widgetWithText(TextField, 'Diastolic BP'), '115');
    await tester.tap(find.text('Severe headache'));
    await tester.pump();

    expect(
      find.text('Possible severe pre-eclampsia signs — decision support, not diagnosis'),
      findsOneWidget,
    );
  });
}
