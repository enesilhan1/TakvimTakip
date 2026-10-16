import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/asistan/asistan_ayarlari.dart';
import 'package:takvim_takip/asistan/yz.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/ui/sohbet_ekrani.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;
  final cuma = DateTime.utc(2026, 10, 16);

  setUp(() async {
    db = await Veritabani.acFactory(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    depo = PlanDeposu(db);
  });

  tearDown(() => db.close());

  Future<void> bekle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pumpAndSettle();
    }
  }

  http.Response yanit(List<Map<String, Object?>> icerik, String stop) =>
      http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'content': icerik,
            'stop_reason': stop,
            'usage': {'input_tokens': 2000, 'output_tokens': 200},
          }),
        ),
        200,
      );

  Future<void> ac(
    WidgetTester tester, {
    String? anahtar = 'sk-ant-test-anahtari-1234',
    List<http.Response> yanitlar = const [],
  }) async {
    var i = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: SohbetEkrani(
          depo: depo,
          anahtarDeposu: BellekAnahtarDeposu({Saglayici.anthropic: ?anahtar}),
          simdi: () => DateTime(2026, 10, 16, 15, 42),
          httpIstemcisi: MockClient((_) async => yanitlar[i++]),
        ),
      ),
    );
    await bekle(tester);
  }

  testWidgets('anahtar yoksa ayarlara yönlendirir', (tester) async {
    await ac(tester, anahtar: null);
    expect(find.textContaining('API anahtarını'), findsOneWidget);
    expect(find.text('Ayarlara git'), findsOneWidget);
    expect(find.byKey(const Key('sohbet_girdisi')), findsNothing);
  });

  testWidgets('boş sohbette öneri çipleri ve model adı', (tester) async {
    await ac(tester);
    expect(find.text('Claude Opus 5.5'), findsOneWidget);
    expect(find.text('Bugün neler var?'), findsOneWidget);
  });

  testWidgets('mesaj gönderilir, yanıt balonda görünür, maliyet yazar', (
    tester,
  ) async {
    await ac(
      tester,
      yanitlar: [
        yanit([
          {'type': 'text', 'text': 'Bugün 15:00\'te Ders var.'},
        ], 'end_turn'),
      ],
    );
    await tester.tap(find.text('Bugün neler var?'));
    await bekle(tester);

    expect(find.text('Bugün neler var?'), findsOneWidget); // kullanıcı balonu
    expect(find.text('Bugün 15:00\'te Ders var.'), findsOneWidget);
    expect(find.textContaining('Bu sohbet ≈ \$'), findsOneWidget);
  });

  testWidgets('öneri kartı: onaylanınca plan değişir', (tester) async {
    final ders = await depo.ekle(
      Plan(baslik: 'Ders', gun: cuma, baslangicSaati: 15),
    );
    await ac(
      tester,
      yanitlar: [
        yanit([
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'degisiklik_oner',
            'input': {
              'aciklama': 'Dersi 18:00\'e al',
              'islemler': [
                {'tur': 'guncelle', 'plan_id': ders.id, 'baslangic_saati': 18},
              ],
            },
          },
        ], 'tool_use'),
        yanit([
          {'type': 'text', 'text': 'Tamam, ders 18:00\'de.'},
        ], 'end_turn'),
      ],
    );

    await tester.enterText(
      find.byKey(const Key('sohbet_girdisi')),
      'Dersi akşama al',
    );
    await tester.tap(find.byTooltip('Gönder'));
    await bekle(tester);

    expect(find.text('Dersi 18:00\'e al'), findsOneWidget);
    expect(
      find.text('✏️ Ders: Cuma 15:00 → Cuma 16 Ekim 18:00'),
      findsOneWidget,
    );
    // Onay beklerken yazma kapalı
    final girdi = tester.widget<TextField>(
      find.byKey(const Key('sohbet_girdisi')),
    );
    expect(girdi.enabled, isFalse);
    expect((await depo.planGetir(ders.id!))!.baslangicSaati, 15);

    await tester.tap(find.text('Onayla'));
    await bekle(tester);

    expect(find.text('✅ Uygulandı'), findsOneWidget);
    expect(find.text('Tamam, ders 18:00\'de.'), findsOneWidget);
    expect((await depo.planGetir(ders.id!))!.baslangicSaati, 18);
  });

  testWidgets('öneri reddedilince plan değişmez', (tester) async {
    final ders = await depo.ekle(
      Plan(baslik: 'Ders', gun: cuma, baslangicSaati: 15),
    );
    await ac(
      tester,
      yanitlar: [
        yanit([
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'degisiklik_oner',
            'input': {
              'aciklama': 'Dersi sil',
              'islemler': [
                {'tur': 'sil', 'plan_id': ders.id},
              ],
            },
          },
        ], 'tool_use'),
        yanit([
          {'type': 'text', 'text': 'Peki.'},
        ], 'end_turn'),
      ],
    );
    await tester.enterText(find.byKey(const Key('sohbet_girdisi')), 'sil');
    await tester.tap(find.byTooltip('Gönder'));
    await bekle(tester);
    await tester.tap(find.text('Reddet'));
    await bekle(tester);

    expect(find.text('Reddedildi, hiçbir şey değişmedi'), findsOneWidget);
    expect(await depo.planGetir(ders.id!), isNotNull);
  });
}
