import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/main.dart';
import 'package:takvim_takip/models/kayma_kaydi.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;

  final pzt = DateTime.utc(2026, 10, 19);
  final sali = gunEkle(pzt, 1);

  setUp(() async {
    // Widget testlerinin sahte zamanlayıcısıyla uyumlu olsun diye
    // izolatsız (aynı thread'de çalışan) SQLite.
    db = await Veritabani.acFactory(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    depo = PlanDeposu(db);
  });

  tearDown(() => db.close());

  Future<void> ac(WidgetTester tester, {required DateTime bugun}) async {
    await tester.pumpWidget(TakvimTakipApp(depo: depo, bugunOverride: bugun));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('başlıkta tarih ve "Bugün" görünür', (tester) async {
    await ac(tester, bugun: sali);

    expect(find.text('20 Ekim 2026'), findsOneWidget);
    expect(find.text('Bugün · Salı'), findsOneWidget);
  });

  testWidgets('planları saat aralığı ve sayaçla gösterir', (tester) async {
    await depo.ekle(
      Plan(baslik: 'Ders', gun: sali, baslangicSaati: 9, sure: 2),
    );
    await depo.ekle(
      Plan(
        baslik: 'Spor',
        gun: sali,
        baslangicSaati: 11,
        sabit: true,
        yapilmadiSayisi: 2,
      ),
    );
    await ac(tester, bugun: pzt);
    await tester.tap(find.byTooltip('Sonraki gün'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Ders'), findsOneWidget);
    expect(find.text('09:00–11:00'), findsOneWidget);
    expect(find.text('Spor'), findsOneWidget);
    expect(find.text('11:00 · 📌 Sabit · 2 kez yapılmadı'), findsOneWidget);
    // 2 saatlik plan 10:00 satırını kaplar
    expect(find.text('10:00'), findsNothing);
    expect(find.text('12:00'), findsOneWidget);
  });

  testWidgets('not başlığın altında görünür, büyük yazıda taşmaz', (
    tester,
  ) async {
    await depo.ekle(
      Plan(
        baslik: 'Kitap',
        not: '50 sayfa, 3. bölüm',
        gun: sali,
        baslangicSaati: 9,
      ),
    );
    await depo.ekle(
      Plan(
        baslik: 'Ders',
        not: 'Matematik: türev ve integral tekrarı, sonra deneme sınavı',
        gun: sali,
        baslangicSaati: 10,
        sure: 2,
      ),
    );
    await ac(tester, bugun: pzt);
    await tester.tap(find.byTooltip('Sonraki gün'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('50 sayfa, 3. bölüm'), findsOneWidget);
    expect(
      find.text('Matematik: türev ve integral tekrarı, sonra deneme sınavı'),
      findsOneWidget,
    );
    // Not başlığın altında
    final baslikY = tester.getTopLeft(find.text('Kitap')).dy;
    final notY = tester.getTopLeft(find.text('50 sayfa, 3. bölüm')).dy;
    expect(notY, greaterThan(baslikY));

    // Telefonda büyük yazı tipi seçiliyse kart taşmamalı (taşma testi
    // otomatik olarak başarısız eder).
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.text('Kitap'), findsOneWidget);
  });

  testWidgets('kayma izini ve geçmiş gündeki yapılmayanı gösterir', (
    tester,
  ) async {
    await depo.kaymaKaydiEkle(
      KaymaKaydi(
        planId: 1,
        baslik: 'Kitap',
        gun: pzt,
        baslangicSaati: 10,
        sure: 1,
        yeniGun: sali,
        yeniBaslangicSaati: 13,
      ),
    );
    await depo.ekle(
      Plan(baslik: 'Doktor', gun: pzt, baslangicSaati: 9, sabit: true),
    );
    await ac(tester, bugun: sali);
    await tester.tap(find.byTooltip('Önceki gün'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text("Kitap — yapılmadı → Salı 13:00'e kaydı"), findsOneWidget);
    expect(find.text('09:00 · 📌 Sabit · Yapılmadı'), findsOneWidget);
  });
}
