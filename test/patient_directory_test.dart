import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunggukitatahundepan2026/app.dart';

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const RawatBundaApp(useSupabase: false));
  await tester.pumpAndSettle();
}

Future<void> openDirectory(WidgetTester tester) async {
  await pumpApp(tester);
  await tester.tap(find.text('Pasien'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Pasien tab shows a searchable patient directory',
      (tester) async {
    await openDirectory(tester);

    expect(find.text('Cari dan pilih pasien untuk memulai kunjungan'),
        findsOneWidget);
    expect(find.text('Tambah pasien'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'siti');
    await tester.pumpAndSettle();
    expect(find.text('Siti Rahayu'), findsOneWidget);
    expect(find.text('Dewi Lestari'), findsNothing);
  });

  testWidgets('patient overview shows band, reasons, and visit history',
      (tester) async {
    await openDirectory(tester);

    await tester.enterText(find.byType(TextField).first, 'siti');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siti Rahayu'));
    await tester.pumpAndSettle();

    // Darurat pill appears (list card may also show one, so at least one).
    expect(find.text('Darurat'), findsWidgets);
    // The rule is explainable: trigger data + decision-support boundary.
    await tester.scrollUntilVisible(
      find.text('Mengapa prioritas ini'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('164/112'), findsWidgets);
    expect(find.textContaining('bukan diagnosis'), findsOneWidget);
    // The visit history section is present further down.
    await tester.scrollUntilVisible(
      find.text('Riwayat kunjungan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Riwayat kunjungan'), findsOneWidget);
  });

  testWidgets('Tambah pasien saves a new record and opens its overview',
      (tester) async {
    await openDirectory(tester);

    await tester.tap(find.text('Tambah pasien'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama lengkap'), 'Pasien Baru');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Usia (tahun)'), '25');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Usia kehamilan (mgg)'), '16');
    await tester.tap(find.text('Simpan pasien'));
    await tester.pumpAndSettle();

    // Landed on the new patient's overview.
    expect(find.text('Pasien Baru'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Belum ada kunjungan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Belum ada kunjungan'), findsOneWidget);
  });

  testWidgets('a duplicate name warns before saving', (tester) async {
    await openDirectory(tester);

    await tester.tap(find.text('Tambah pasien'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama lengkap'), 'Siti Rahayu');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Usia (tahun)'), '30');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Usia kehamilan (mgg)'), '20');
    await tester.tap(find.text('Simpan pasien'));
    await tester.pumpAndSettle();

    // Warned, not saved: still on the form.
    expect(find.text('Nama sudah terdaftar'), findsOneWidget);
    expect(find.text('Simpan pasien'), findsOneWidget);
  });
}
