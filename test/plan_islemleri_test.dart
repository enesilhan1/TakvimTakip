import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/main.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/ui/plan_islemleri.dart';
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

  Future<Plan> ekle(
    DateTime gun, {
    String baslik = 'Ders',
    bool sabit = false,
    PlanDurumu durum = PlanDurumu.isaretsiz,
  }) => depo.ekle(
    Plan(
      baslik: baslik,
      gun: gun,
      baslangicSaati: 10,
      sabit: sabit,
      durum: durum,
    ),
  );

  Future<void> ac(WidgetTester tester, {required DateTime bugun}) async {
    await tester.pumpWidget(
      TakvimTakipApp(depo: depo, bugunOverride: bugun, saatOverride: () => 9),
    );
    await bekle(tester);
  }

  Future<PlanDurumu> durum(Plan p) async =>
      (await depo.planGetir(p.id!))!.durum;

  testWidgets('durum ikonu yapıldı yapar ve geri alır', (tester) async {
    final p = await ekle(pzt);
    await ac(tester, bugun: pzt);

    await tester.tap(find.byTooltip('Yapıldı'));
    await bekle(tester);
    expect(await durum(p), PlanDurumu.yapildi);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byTooltip('İşareti kaldır'));
    await bekle(tester);
    expect(await durum(p), PlanDurumu.isaretsiz);
  });

  testWidgets('işlem panelinden iptal edilir', (tester) async {
    final p = await ekle(pzt);
    await ac(tester, bugun: pzt);

    await tester.tap(find.text('Ders'));
    await bekle(tester);
    await tester.tap(find.text('İptal et (kaymasın)'));
    await bekle(tester);

    expect(await durum(p), PlanDurumu.iptal);
    expect(find.text('10:00 · İptal'), findsOneWidget);
  });

  testWidgets('işlem panelinden düzenlenir', (tester) async {
    final p = await ekle(pzt);
    await ac(tester, bugun: pzt);

    await tester.tap(find.text('Ders'));
    await bekle(tester);
    await tester.tap(find.text('Düzenle'));
    await bekle(tester);
    expect(find.text('Planı düzenle'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('baslik')), 'Matematik');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);

    expect((await depo.planGetir(p.id!))!.baslik, 'Matematik');
    expect(find.text('Matematik'), findsOneWidget);
  });

  testWidgets('silme onay ister', (tester) async {
    final p = await ekle(pzt);
    await ac(tester, bugun: pzt);

    await tester.tap(find.text('Ders'));
    await bekle(tester);
    await tester.tap(find.text('Sil'));
    await bekle(tester);
    expect(find.text('Plan silinsin mi?'), findsOneWidget);

    await tester.tap(find.text('Vazgeç'));
    await bekle(tester);
    expect(await depo.planGetir(p.id!), isNotNull);

    await tester.tap(find.text('Ders'));
    await bekle(tester);
    await tester.tap(find.text('Sil'));
    await bekle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await bekle(tester);
    expect(await depo.planGetir(p.id!), isNull);
    expect(find.text('Ders'), findsNothing);
  });

  testWidgets('geçmiş günde düzenleme yok', (tester) async {
    await ekle(pzt, durum: PlanDurumu.yapildi);
    await ac(tester, bugun: sali);
    await tester.tap(find.byTooltip('Önceki gün'));
    await bekle(tester);

    await tester.tap(find.text('Ders'));
    await bekle(tester);
    expect(find.text('Düzenle'), findsNothing);
    expect(find.text('İşareti kaldır'), findsNothing);
    expect(find.text('İptal et (kaymasın)'), findsOneWidget);
  });

  test('işareti kaldırma kuralı', () {
    final yapildi = Plan(
      baslik: 'X',
      gun: pzt,
      baslangicSaati: 1,
      durum: PlanDurumu.yapildi,
    );
    expect(isaretKaldirilabilir(yapildi, gecmis: false), isTrue);
    expect(isaretKaldirilabilir(yapildi, gecmis: true), isFalse);
    expect(
      isaretKaldirilabilir(yapildi.copyWith(sabit: true), gecmis: true),
      isTrue,
    );
    expect(
      isaretKaldirilabilir(
        yapildi.copyWith(durum: PlanDurumu.isaretsiz),
        gecmis: false,
      ),
      isFalse,
    );
  });
}
