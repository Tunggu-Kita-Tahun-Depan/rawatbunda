import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tunggukitatahundepan2026/app.dart';
import 'package:tunggukitatahundepan2026/core/constants/clinical_rules.dart';

void main() {
  Future<void> pumpDemoApp(WidgetTester tester) async {
    await tester.pumpWidget(const RawatBundaApp(useSupabase: false));
    await tester.pumpAndSettle();
  }

  Future<void> openReferralTab(WidgetTester tester) async {
    await tester.tap(find.text('Rujukan'));
    await tester.pumpAndSettle();
  }

  testWidgets('App opens on Beranda with three primary destinations', (
    tester,
  ) async {
    await pumpDemoApp(tester);

    expect(find.text('Selamat datang'), findsOneWidget);
    expect(find.text('Buat Rujukan Baru'), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Rujukan'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('Rujukan destination opens the intake screen', (tester) async {
    await pumpDemoApp(tester);
    await openReferralTab(tester);

    expect(find.text('Input Data Ibu'), findsOneWidget);
    expect(find.text('Kirim Rujukan'), findsOneWidget);
  });

  testWidgets('Safety flag appears for severe BP plus danger symptom', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await openReferralTab(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'TD sistolik'),
      '165',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'TD diastolik'),
      '115',
    );
    await tester.ensureVisible(find.text('Sakit kepala berat'));
    await tester.tap(find.text('Sakit kepala berat'));
    await tester.pump();

    expect(find.text(ClinicalRules.safetyFlagMessage), findsOneWidget);
    expect(find.text('Tanda bahaya terdeteksi'), findsOneWidget);
  });

  testWidgets('Switching tabs preserves a partially entered referral', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await openReferralTab(tester);

    final nameField = find.widgetWithText(TextField, 'Nama pasien (sintetis)');
    await tester.enterText(nameField, 'Ibu Demo');
    await tester.tap(find.text('Beranda'));
    await tester.pumpAndSettle();
    await openReferralTab(tester);

    final textField = tester.widget<TextField>(nameField);
    expect(textField.controller?.text, 'Ibu Demo');
  });

  testWidgets('Profile explains local demo mode without a logout action', (
    tester,
  ) async {
    await pumpDemoApp(tester);

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();

    expect(find.text('Mode demo lokal'), findsOneWidget);
    expect(find.text('Keluar dari akun'), findsNothing);
  });

  testWidgets('Home fits a typical mobile browser viewport without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpDemoApp(tester);

    expect(find.text('Selamat datang'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
