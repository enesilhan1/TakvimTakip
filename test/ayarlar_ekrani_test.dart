import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/claude/claude_ayarlari.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/logic/bildirim_plani.dart';
import 'package:takvim_takip/logic/kaydirma_servisi.dart';
import 'package:takvim_takip/logic/yedek.dart';
import 'package:takvim_takip/main.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/ui/ayarlar_ekrani.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;

  final bugun = DateTime.utc(2026, 10, 20);
  final simdi = DateTime(2026, 10, 20, 14, 30);

  setUp(() async {
    // Testte Android'in şifreli deposu yok; paketin sahte deposu.
    FlutterSecureStorage.setMockInitialValues({});
    db = await Veritabani.acFactory(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    depo = PlanDeposu(db);
    await depo.ayarYaz(
      KaydirmaServisi.sonIslenenGunAyari,
      gunAnahtari(gunEkle(bugun, -1)),
    );
  });

  tearDown(() => db.close());

  Future<void> bekle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  String? kaydedilenAd;
  String? kaydedilenMetin;
  String? secilecekMetin;
  late BellekAnahtarDeposu anahtarlar;

  Future<void> ac(WidgetTester tester) async {
    kaydedilenAd = null;
    kaydedilenMetin = null;
    anahtarlar = BellekAnahtarDeposu();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AyarlarEkrani(
          depo: depo,
          simdi: () => simdi,
          dosyaKaydet: (ad, Uint8List veri) async {
            kaydedilenAd = ad;
            kaydedilenMetin = utf8.decode(veri);
            return true;
          },
          dosyaSec: () async => secilecekMetin,
          anahtarDeposu: anahtarlar,
        ),
      ),
    );
    await bekle(tester);
  }

  testWidgets('sabah özeti saati değiştirilir ve saklanır', (tester) async {
    await ac(tester);
    expect(find.text('09:00'), findsOneWidget); // varsayılan

    await tester.tap(find.byKey(const Key('sabah_saati')));
    await bekle(tester);
    await tester.tap(find.text('07:00').last);
    await bekle(tester);

    expect(await depo.ayarOku(sabahSaatiAyari), '7');
    expect(find.text('07:00'), findsOneWidget);
  });

  testWidgets('dışa aktarma bütün planları dosyaya yazar', (tester) async {
    await depo.ekle(Plan(baslik: 'Ders', gun: bugun, baslangicSaati: 13));
    await depo.ekle(Plan(baslik: 'Spor', gun: bugun, baslangicSaati: 16));
    await ac(tester);

    await tester.tap(find.text('Yedeği dışa aktar'));
    await bekle(tester);

    expect(kaydedilenAd, 'takvim_takip_yedek_2026-10-20_1430.json');
    final yedek = Yedek.coz(kaydedilenMetin!);
    expect(yedek.planlar.map((p) => p.baslik), ['Ders', 'Spor']);
    expect(find.text('Yedek kaydedildi: 2 plan'), findsOneWidget);
  });

  testWidgets('geri yükleme onay ister ve verileri değiştirir', (tester) async {
    // Yedekte tek plan var
    secilecekMetin = Yedek(
      olusturma: DateTime(2026, 10, 18, 9, 5),
      planlar: [
        Plan(id: 1, baslik: 'Yedekteki', gun: bugun, baslangicSaati: 10),
      ],
      kaymaKayitlari: const [],
      ayarlar: {
        KaydirmaServisi.sonIslenenGunAyari: gunAnahtari(gunEkle(bugun, -1)),
        sabahSaatiAyari: '8',
      },
    ).jsonMetni();
    await depo.ekle(Plan(baslik: 'Telefondaki', gun: bugun, baslangicSaati: 9));
    await ac(tester);

    await tester.tap(find.text('Yedekten geri yükle'));
    await bekle(tester);
    expect(find.text('Yedek yüklensin mi?'), findsOneWidget);
    expect(find.textContaining('18 Ekim 2026 Pazar 09:05 · 1 plan'), findsOne);

    // Vazgeçince hiçbir şey değişmez
    await tester.tap(find.text('Vazgeç'));
    await bekle(tester);
    expect((await depo.gununPlanlari(bugun)).single.baslik, 'Telefondaki');

    await tester.tap(find.text('Yedekten geri yükle'));
    await bekle(tester);
    await tester.tap(find.text('Yükle'));
    await bekle(tester);

    expect((await depo.gununPlanlari(bugun)).single.baslik, 'Yedekteki');
    expect(find.text('Yedek yüklendi: 1 plan'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget); // ayarlar da geldi
  });

  testWidgets('hatalı dosya yüklenmez, mevcut veri korunur', (tester) async {
    secilecekMetin = '{"baska": "uygulama"}';
    await depo.ekle(Plan(baslik: 'Telefondaki', gun: bugun, baslangicSaati: 9));
    await ac(tester);

    await tester.tap(find.text('Yedekten geri yükle'));
    await bekle(tester);

    expect(find.text('Yedek yüklenemedi'), findsOneWidget);
    expect(
      find.text('Bu dosya bir Takvim Takip yedeği değil.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tamam'));
    await bekle(tester);
    expect(await depo.gununPlanlari(bugun), hasLength(1));
  });

  testWidgets('API anahtarı kaydedilir, maskeli gösterilir ve silinir', (
    tester,
  ) async {
    await ac(tester);
    await tester.ensureVisible(find.text('API anahtarı'));
    await bekle(tester);
    expect(find.textContaining('Girilmedi'), findsOneWidget);

    await tester.tap(find.text('API anahtarı'));
    await bekle(tester);
    await tester.enterText(find.byKey(const Key('api_anahtari')), 'yanlis');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);
    expect(find.textContaining('"sk-ant-" ile başlar'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('api_anahtari')),
      'sk-ant-api03-ABCDEFGHIJKLMNOP-wxyz',
    );
    await tester.tap(find.text('Kaydet'));
    await bekle(tester);
    expect(anahtarlar.deger, 'sk-ant-api03-ABCDEFGHIJKLMNOP-wxyz');
    expect(find.text('Kayıtlı: sk-ant-…wxyz'), findsOneWidget);
    // Anahtar veritabanına (ve yedeğe) girmez
    final yedek = await depo.yedekAl(simdi);
    expect(yedek.jsonMetni(), isNot(contains('sk-ant-')));

    await tester.tap(find.text('API anahtarı'));
    await bekle(tester);
    await tester.tap(find.text('Sil'));
    await bekle(tester);
    expect(anahtarlar.deger, isNull);
    expect(find.textContaining('Girilmedi'), findsOneWidget);
  });

  testWidgets('Claude modeli seçilir ve saklanır', (tester) async {
    await ac(tester);
    await tester.ensureVisible(find.byKey(const Key('claude_model')));
    await bekle(tester);
    expect(find.text('Opus 5.5'), findsOneWidget); // varsayılan

    await tester.tap(find.byKey(const Key('claude_model')));
    await bekle(tester);
    await tester.tap(find.text('Haiku 5.5').last);
    await bekle(tester);

    expect(await depo.ayarOku(claudeModelAyari), 'claude-haiku-5-5');
    expect(find.textContaining('En hızlı ve en ucuzu'), findsOneWidget);
  });

  testWidgets('görünümlerdeki ⚙ butonu ayarları açar', (tester) async {
    await tester.pumpWidget(
      TakvimTakipApp(depo: depo, bugunOverride: bugun, saatOverride: () => 9),
    );
    await bekle(tester);

    await tester.tap(find.byTooltip('Ayarlar'));
    await bekle(tester);
    expect(find.text('Sabah özeti saati'), findsOneWidget);

    // pageBack() İngilizce arayüzü varsayıyor; uygulama Türkçe.
    await tester.tap(find.byType(BackButton));
    await bekle(tester);
    expect(find.text('Bugün · Salı'), findsOneWidget);
  });
}
