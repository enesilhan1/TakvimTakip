import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/main.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/ui/hafta_gorunumu.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;

  final pzt = DateTime.utc(2026, 10, 19);
  final crs = gunEkle(pzt, 2);

  setUp(() async {
    db = await Veritabani.acFactory(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    depo = PlanDeposu(db);
  });

  tearDown(() => db.close());

  Future<void> bekle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Bugün Salı; haftalık sekmeyi açar (tablo 08:00'den başlar).
  Future<void> haftayiAc(WidgetTester tester) async {
    await tester.pumpWidget(
      TakvimTakipApp(
        depo: depo,
        bugunOverride: gunEkle(pzt, 1),
        saatOverride: () => 9,
      ),
    );
    await bekle(tester);
    await tester.tap(find.text('Hafta'));
    await bekle(tester);
  }

  testWidgets('başlık, gün adları ve planlar görünür', (tester) async {
    await depo.ekle(Plan(baslik: 'Ders', gun: crs, baslangicSaati: 9, sure: 2));
    await depo.ekle(
      Plan(
        baslik: 'Spor',
        gun: pzt,
        baslangicSaati: 10,
        durum: PlanDurumu.yapildi,
      ),
    );
    await haftayiAc(tester);

    expect(find.text('19–25 Ekim 2026'), findsOneWidget);
    for (final ad in ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']) {
      expect(find.text(ad), findsOneWidget);
    }
    expect(find.text('Ders'), findsOneWidget);
    expect(find.text('✓ Spor'), findsOneWidget);

    // 2 saatlik plan iki satır yüksekliğinde
    final blok = tester.getSize(
      find.ancestor(
        of: find.text('Ders'),
        matching: find.byType(HaftaPlanBlogu),
      ),
    );
    expect(blok.height, closeTo(2 * 48 - 2, 0.1));
  });

  testWidgets('hafta değiştirme', (tester) async {
    await haftayiAc(tester);

    await tester.tap(find.byTooltip('Sonraki hafta'));
    await bekle(tester);
    expect(find.text('26 Eki – 1 Kas 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Bu haftaya git'));
    await bekle(tester);
    expect(find.text('19–25 Ekim 2026'), findsOneWidget);
  });

  testWidgets('gün başlığına dokununca gün görünümü o güne açılır', (
    tester,
  ) async {
    await haftayiAc(tester);

    // Perşembe 22 Ekim (ilk "22" başlıktaki tarih, ikincisi 22:00 etiketi)
    await tester.tap(find.text('22').first);
    await bekle(tester);

    expect(find.text('22 Ekim 2026'), findsOneWidget);
    expect(find.text('Perşembe'), findsOneWidget);
  });

  testWidgets('boş hücreye dokununca o gün ve saate plan eklenir', (
    tester,
  ) async {
    await haftayiAc(tester);

    // Çarşamba sütunu, 10:00 satırı
    final crsBaslik = tester.getCenter(find.text('Çar'));
    final onSaat = tester.getTopLeft(find.text('10'));
    await tester.tapAt(Offset(crsBaslik.dx, onSaat.dy + 20));
    await bekle(tester);
    expect(find.text('Yeni plan'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('baslik')), 'Kitap');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);

    final p = (await depo.gununPlanlari(crs)).single;
    expect(p.baslangicSaati, 10);
    expect(find.text('Kitap'), findsOneWidget);
  });

  testWidgets('plana dokununca işlem paneli açılır', (tester) async {
    await depo.ekle(Plan(baslik: 'Ders', gun: crs, baslangicSaati: 9));
    await haftayiAc(tester);

    await tester.tap(find.text('Ders'));
    await bekle(tester);
    await tester.tap(find.text('Yapıldı'));
    await bekle(tester);

    expect(find.text('✓ Ders'), findsOneWidget);
  });
}
