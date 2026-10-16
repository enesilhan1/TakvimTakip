import 'package:flutter/material.dart';
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

  /// Bugün Salı 20 Ekim; aylık sekmeyi açar.
  Future<void> ayiAc(WidgetTester tester) async {
    // Telefon boyutunda ekran (ızgara rahat sığsın)
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TakvimTakipApp(depo: depo, bugunOverride: sali, saatOverride: () => 9),
    );
    await bekle(tester);
    await tester.tap(find.text('Ay'));
    await bekle(tester);
  }

  testWidgets('ay başlığı, gün adları ve günler', (tester) async {
    await ayiAc(tester);

    expect(find.text('Ekim 2026'), findsOneWidget);
    expect(find.text('Pzt'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    // Ekim 2026 perşembe başlar: ızgara 28 Eylül pazartesiden başlar
    expect(find.text('28'), findsNWidgets(2)); // 28 Eylül ve 28 Ekim
  });

  testWidgets('günlerde yapılan/toplam ve kayan sayısı görünür', (
    tester,
  ) async {
    await depo.ekle(
      Plan(baslik: 'A', gun: pzt, baslangicSaati: 9, durum: PlanDurumu.yapildi),
    );
    await depo.ekle(
      Plan(
        baslik: 'B',
        gun: pzt,
        baslangicSaati: 10,
        durum: PlanDurumu.yapildi,
      ),
    );
    await depo.kaymaKaydiEkle(
      KaymaKaydi(
        planId: 99,
        baslik: 'K',
        gun: pzt,
        baslangicSaati: 15,
        sure: 1,
        yeniGun: sali,
        yeniBaslangicSaati: 13,
      ),
    );
    await depo.ekle(Plan(baslik: 'K', gun: sali, baslangicSaati: 13));
    await ayiAc(tester);

    expect(find.text('2/3 ↷1'), findsOneWidget); // Pazartesi
    expect(find.text('0/1'), findsOneWidget); // Salı
  });

  testWidgets('ay değiştirme ve bu aya dönme', (tester) async {
    await ayiAc(tester);

    await tester.tap(find.byTooltip('Sonraki ay'));
    await bekle(tester);
    expect(find.text('Kasım 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Önceki ay'));
    await tester.tap(find.byTooltip('Önceki ay'));
    await bekle(tester);
    expect(find.text('Eylül 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Bu aya git'));
    await bekle(tester);
    expect(find.text('Ekim 2026'), findsOneWidget);
  });

  testWidgets('güne dokununca gün görünümü açılır', (tester) async {
    await ayiAc(tester);

    await tester.tap(find.text('22'));
    await bekle(tester);

    expect(find.text('22 Ekim 2026'), findsOneWidget);
    expect(find.text('Perşembe'), findsOneWidget);
  });
}
