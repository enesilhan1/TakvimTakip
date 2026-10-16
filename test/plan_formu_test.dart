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

  /// Bugünü Pazartesi kabul edip Salı'yı açar (görünüm 08:00'den başlar).
  Future<void> saliyiAc(WidgetTester tester) async {
    await tester.pumpWidget(TakvimTakipApp(depo: depo, bugunOverride: pzt));
    await bekle(tester);
    await tester.tap(find.byTooltip('Sonraki gün'));
    await bekle(tester);
  }

  testWidgets('boş saate dokunup plan eklenir', (tester) async {
    await saliyiAc(tester);

    await tester.tap(find.text('10:00'));
    await bekle(tester);
    expect(find.text('Yeni plan'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('baslik')), 'Ders çalışma');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);

    expect(find.text('Yeni plan'), findsNothing);
    expect(find.text('Ders çalışma'), findsOneWidget);
    final kayitli = (await depo.gununPlanlari(sali)).single;
    expect(kayitli.baslangicSaati, 10);
    expect(kayitli.sure, 1);
  });

  testWidgets('süre ve sabit seçilerek eklenir', (tester) async {
    await saliyiAc(tester);

    await tester.tap(find.text('13:00'));
    await bekle(tester);
    await tester.enterText(find.byKey(const Key('baslik')), 'Ders');
    await tester.tap(find.text('1 saat'));
    await bekle(tester);
    await tester.tap(find.text('2 saat').last);
    await bekle(tester);
    await tester.tap(find.text('📌 Sabit plan'));
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);

    final p = (await depo.gununPlanlari(sali)).single;
    expect(p.sure, 2);
    expect(p.sabit, isTrue);
  });

  testWidgets('boş başlık ve çakışma hata gösterir', (tester) async {
    await depo.ekle(
      Plan(baslik: 'Spor', gun: sali, baslangicSaati: 11, sure: 1),
    );
    await saliyiAc(tester);

    await tester.tap(find.text('10:00'));
    await bekle(tester);
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);
    expect(find.text('Başlık boş olamaz.'), findsOneWidget);

    // 10:00–12:00, 11:00'deki Spor ile çakışır
    await tester.enterText(find.byKey(const Key('baslik')), 'Ders');
    await tester.tap(find.text('1 saat'));
    await bekle(tester);
    await tester.tap(find.text('2 saat').last);
    await bekle(tester);
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);

    expect(
      find.text('Bu saat aralığında zaten bir plan var: 11:00 Spor'),
      findsOneWidget,
    );
    expect(await depo.gununPlanlari(sali), hasLength(1));
  });

  testWidgets('geçmiş günde ekleme kapalı', (tester) async {
    await tester.pumpWidget(TakvimTakipApp(depo: depo, bugunOverride: sali));
    await bekle(tester);
    expect(find.byTooltip('Plan ekle'), findsOneWidget);

    await tester.tap(find.byTooltip('Önceki gün'));
    await bekle(tester);
    expect(find.byTooltip('Plan ekle'), findsNothing);

    await tester.tap(find.text('10:00'));
    await bekle(tester);
    expect(find.text('Yeni plan'), findsNothing);
  });
}
