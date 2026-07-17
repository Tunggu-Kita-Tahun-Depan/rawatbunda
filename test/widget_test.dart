import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tunggukitatahundepan2026/app.dart';
import 'package:tunggukitatahundepan2026/models/app_profile.dart';

void main() {
  Future<void> pumpDemoApp(
    WidgetTester tester, {
    AppRole role = AppRole.bidan,
  }) async {
    await tester.pumpWidget(RawatBundaApp(useSupabase: false, demoRole: role));
    await tester.pumpAndSettle();
  }

  Future<void> openPatientTab(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Pasien'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('App opens on Beranda with three primary destinations', (
    tester,
  ) async {
    await pumpDemoApp(tester);

    expect(find.text('Selamat datang'), findsOneWidget);
    expect(find.text('Buka Pasien'), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Pasien'),
      ),
      findsOneWidget,
    );
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Rujukan'), findsNothing);
  });

  testWidgets('Pasien destination opens the patient directory', (tester) async {
    await pumpDemoApp(tester);
    await openPatientTab(tester);

    expect(
      find.text('Cari dan pilih pasien untuk memulai kunjungan'),
      findsOneWidget,
    );
    expect(find.text('Tambah pasien'), findsOneWidget);
  });

  testWidgets('Patient overview exposes encounter input before referral', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await openPatientTab(tester);

    await tester.enterText(find.byType(TextField).first, 'ayu');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayu Andira'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Input/update data'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Input/update data'), findsOneWidget);
    expect(find.text('Mulai rujukan'), findsOneWidget);

    await tester.tap(find.text('Input/update data'));
    await tester.pumpAndSettle();

    expect(find.text('Input/update data'), findsWidgets);
    expect(find.text('Gunakan AI Speech to Text'), findsOneWidget);
    expect(find.text('age_years'), findsOneWidget);
  });

  testWidgets('Mulai rujukan opens facility matching with Material shell', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await openPatientTab(tester);

    await tester.enterText(find.byType(TextField).first, 'ayu');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayu Andira'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Mulai rujukan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mulai rujukan'));
    await tester.pumpAndSettle();

    expect(find.text('Pilih Fasilitas'), findsOneWidget);
    expect(find.text('Ayu Andira'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('facility selection proceeds past Menyiapkan state', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await openPatientTab(tester);

    await tester.enterText(find.byType(TextField).first, 'ayu');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayu Andira'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Mulai rujukan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mulai rujukan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Puskesmas Sukamaju'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih & Catat Respons Faskes'));
    await tester.pumpAndSettle();

    expect(find.text('Catat Respons Faskes'), findsOneWidget);
    expect(find.text('Menyiapkan…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted response completes referral back to home', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await openPatientTab(tester);

    await tester.enterText(find.byType(TextField).first, 'ayu');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayu Andira'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Mulai rujukan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mulai rujukan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Puskesmas Sukamaju'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih & Catat Respons Faskes'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Simpan Respons'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Simpan Respons'));
    await tester.pumpAndSettle();

    expect(find.text('Linimasa Rujukan'), findsOneWidget);
    expect(find.text('RUJUKAN AKTIF'), findsOneWidget);
    expect(tester.takeException(), isNull);

    GoRouter.of(
      tester.element(find.text('Linimasa Rujukan')),
    ).go('/bidan/referral/response');
    await tester.pumpAndSettle();

    expect(find.text('Linimasa Rujukan'), findsOneWidget);
    expect(find.text('Catat Respons Faskes'), findsNothing);
    expect(find.text('Simpan Respons'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Simulasikan Tiba'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Simulasikan Tiba'));
    await tester.pumpAndSettle();

    expect(find.text('Selamat datang'), findsOneWidget);
    expect(find.text('Rujukan saat ini'), findsNothing);
    expect(find.text('Selesai'), findsNothing);
    expect(find.text('Catat Respons Faskes'), findsNothing);

    GoRouter.of(
      tester.element(find.text('Selamat datang')),
    ).go('/bidan/referral/response');
    await tester.pumpAndSettle();

    expect(find.text('Selamat datang'), findsOneWidget);
    expect(find.text('Catat Respons Faskes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Switching tabs preserves patient search context by route', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await openPatientTab(tester);

    await tester.enterText(find.byType(TextField).first, 'siti');
    await tester.tap(find.text('Beranda'));
    await tester.pumpAndSettle();
    await openPatientTab(tester);

    expect(
      find.text('Cari dan pilih pasien untuk memulai kunjungan'),
      findsOneWidget,
    );
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

  testWidgets('Pasien role is view-only and cannot open Bidan routes', (
    tester,
  ) async {
    await pumpDemoApp(tester, role: AppRole.pasien);

    expect(find.text('TAMPILAN BACA-SAJA'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Rujukan'), findsNothing);

    final context = tester.element(find.text('TAMPILAN BACA-SAJA'));
    GoRouter.of(context).go('/bidan/home');
    await tester.pumpAndSettle();

    expect(find.text('TAMPILAN BACA-SAJA'), findsOneWidget);
    expect(find.text('Buat Rujukan Baru'), findsNothing);
  });

  testWidgets('Admin role sees facilities but no clinical actions', (
    tester,
  ) async {
    await pumpDemoApp(tester, role: AppRole.admin);

    expect(find.text('Master Fasilitas'), findsOneWidget);
    expect(find.text('Rujukan'), findsNothing);
    expect(find.text('Buat Rujukan Baru'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
