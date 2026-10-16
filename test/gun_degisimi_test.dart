import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/logic/kaydirma_servisi.dart';
import 'package:takvim_takip/main.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

/// Uygulama açıkken gün değişimi (gece yarısı ve arka plandan dönüş).
void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;

  final pzt = DateTime.utc(2026, 10, 19);
  final sali = gunEkle(pzt, 1);

  setUp(() async {
    db = await Veritabani.acFactory(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    depo = PlanDeposu(db);
    await depo.ayarYaz(
      KaydirmaServisi.sonIslenenGunAyari,
      gunAnahtari(gunEkle(pzt, -1)),
    );
  });

  tearDown(() => db.close());

  Future<void> bekle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('arka plandan dönünce yeni güne geçer ve dünü kaydırır', (
    tester,
  ) async {
    await depo.ekle(Plan(baslik: 'Kitap', gun: pzt, baslangicSaati: 9));
    var simdi = DateTime(2026, 10, 19, 22);

    await tester.pumpWidget(
      TakvimTakipApp(depo: depo, simdiOverride: () => simdi),
    );
    await bekle(tester);
    expect(find.text('Bugün · Pazartesi'), findsOneWidget);

    // Telefon gece kilitlendi, sabah açıldı.
    simdi = DateTime(2026, 10, 20, 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await bekle(tester);

    expect(find.text('Bugün · Salı'), findsOneWidget);
    expect(find.text('Kitap'), findsOneWidget);
    expect((await depo.gununPlanlari(sali)).single.yapilmadiSayisi, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('açıkken gece yarısı geçince yeni güne geçer', (tester) async {
    await depo.ekle(Plan(baslik: 'Kitap', gun: pzt, baslangicSaati: 9));
    var simdi = DateTime(2026, 10, 19, 23, 59);

    await tester.pumpWidget(
      TakvimTakipApp(depo: depo, simdiOverride: () => simdi),
    );
    await bekle(tester);
    expect(find.text('Bugün · Pazartesi'), findsOneWidget);

    simdi = DateTime(2026, 10, 20, 0, 0, 2);
    await tester.pump(const Duration(minutes: 1, seconds: 2));
    await bekle(tester);

    expect(find.text('Bugün · Salı'), findsOneWidget);
    expect(await depo.gununPlanlari(sali), hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });
}
