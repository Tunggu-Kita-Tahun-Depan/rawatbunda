import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tunggukitatahundepan2026/app.dart';
import 'package:tunggukitatahundepan2026/core/constants/clinical_rules.dart';

void main() {
  testWidgets('Intake screen loads with Kirim Rujukan button', (WidgetTester tester) async {
    await tester.pumpWidget(const RawatBundaApp(useSupabase: false));

    expect(find.text('Input Data Ibu'), findsOneWidget);
    expect(find.text('Kirim Rujukan'), findsOneWidget);
  });

  testWidgets('Safety flag banner appears for severe BP + symptom', (WidgetTester tester) async {
    await tester.pumpWidget(const RawatBundaApp(useSupabase: false));

    await tester.enterText(find.widgetWithText(TextField, 'TD sistolik'), '165');
    await tester.enterText(find.widgetWithText(TextField, 'TD diastolik'), '115');
    await tester.tap(find.text('Sakit kepala berat'));
    await tester.pump();

    expect(find.text(ClinicalRules.safetyFlagMessage), findsOneWidget);
  });
}
