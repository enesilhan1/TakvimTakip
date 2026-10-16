import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/main.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;

  final bugun = DateTime.utc(2026, 10, 20);
  final dun = gunEkle(bugun, -1);

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

  /// Yıllık sayfanın dış listesi (içindeki ızgara da kaydırılabilir sayılır).
  final liste = find.byType(Scrollable).first;

  Future<void> yiliAc(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TakvimTakipApp(depo: depo, bugunOverride: bugun, saatOverride: () => 9),
    );
    await bekle(tester);
    await tester.tap(find.text('Yıl'));
    await bekle(tester);
  }

  testWidgets('istatistikler ve en çok ertelenenler görünür', (tester) async {
    await depo.ekle(
      Plan(baslik: 'A', gun: dun, baslangicSaati: 9, durum: PlanDurumu.yapildi),
    );
    await depo.ekle(
      Plan(
        baslik: 'B',
        gun: dun,
        baslangicSaati: 10,
        durum: PlanDurumu.yapildi,
      ),
    );
    await depo.ekle(
      Plan(
        baslik: 'Kitap okuma',
        gun: bugun,
        baslangicSaati: 9,
        yapilmadiSayisi: 4,
      ),
    );
    await yiliAc(tester);

    expect(find.text('2026'), findsOneWidget);
    // 3 planın 2'si yapıldı (bugün dahil)
    expect(find.text('%67'), findsOneWidget);
    expect(find.text('tamamlandı\n(2/3 plan)'), findsOneWidget);
    expect(find.text('En çok ertelenenler'), findsOneWidget);
    expect(find.text('Kitap okuma'), findsOneWidget);
    expect(find.text('4 kez'), findsOneWidget);
    // Dün tamamen yapıldı, bugün henüz bitmedi → seri 1
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('12 ay ve tamamlanan gün koyu yeşil', (tester) async {
    await depo.ekle(
      Plan(baslik: 'A', gun: dun, baslangicSaati: 9, durum: PlanDurumu.yapildi),
    );
    await yiliAc(tester);
    await tester.scrollUntilVisible(
      find.text('Aralık'),
      300,
      scrollable: liste,
    );

    for (final ay in ayAdlari) {
      expect(find.text(ay), findsOneWidget);
    }
    final kutu = tester.widget<Container>(
      find.byKey(ValueKey('kutu-${gunAnahtari(dun)}')),
    );
    final renk = (kutu.decoration! as BoxDecoration).color!;
    expect(renk.a, 1.0);
  });

  testWidgets('güne dokununca gün görünümü, aya dokununca ay açılır', (
    tester,
  ) async {
    await yiliAc(tester);
    await tester.scrollUntilVisible(find.text('Ekim'), 300, scrollable: liste);

    await tester.tap(find.byKey(ValueKey('kutu-${gunAnahtari(dun)}')));
    await bekle(tester);
    expect(find.text('19 Ekim 2026'), findsOneWidget);

    await tester.tap(find.text('Yıl'));
    await bekle(tester);
    await tester.scrollUntilVisible(find.text('Mart'), 300, scrollable: liste);
    await tester.tap(find.text('Mart'));
    await bekle(tester);
    expect(find.text('Mart 2026'), findsOneWidget);
  });

  testWidgets('yıl değiştirme', (tester) async {
    await yiliAc(tester);

    await tester.tap(find.byTooltip('Önceki yıl'));
    await bekle(tester);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('–'), findsOneWidget); // planı olmayan yılın oranı

    await tester.tap(find.byTooltip('Bu yıla git'));
    await bekle(tester);
    expect(find.text('2026'), findsOneWidget);
  });
}
