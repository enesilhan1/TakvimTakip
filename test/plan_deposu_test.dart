import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/logic/yedek.dart';
import 'package:takvim_takip/models/kayma_kaydi.dart';
import 'package:takvim_takip/models/plan.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;

  final pzt = DateTime.utc(2026, 10, 19);
  final sali = DateTime.utc(2026, 10, 20);
  final crs = DateTime.utc(2026, 10, 21);

  setUp(() async {
    // Her test temiz, bellek içi bir veritabanıyla başlar.
    db = await Veritabani.acFactory(databaseFactoryFfi, inMemoryDatabasePath);
    depo = PlanDeposu(db);
  });

  tearDown(() => db.close());

  Plan plan(String baslik, DateTime gun, int saat, {int sure = 1}) =>
      Plan(baslik: baslik, gun: gun, baslangicSaati: saat, sure: sure);

  test('ekle kimlik atar, planGetir aynı planı döndürür', () async {
    final p = await depo.ekle(plan('Ders', pzt, 13, sure: 2));
    expect(p.id, isNotNull);
    expect(await depo.planGetir(p.id!), p);
  });

  test('gununPlanlari sadece o günü saat sırasıyla döndürür', () async {
    await depo.ekle(plan('Kitap', pzt, 15));
    await depo.ekle(plan('Ders', pzt, 13));
    await depo.ekle(plan('Spor', sali, 14));

    final liste = await depo.gununPlanlari(pzt);
    expect(liste.map((p) => p.baslik), ['Ders', 'Kitap']);
  });

  test('araliktakiPlanlar ve gundenItibarenPlanlar', () async {
    await depo.ekle(plan('A', pzt, 9));
    await depo.ekle(plan('B', sali, 9));
    await depo.ekle(plan('C', crs, 9));

    expect((await depo.araliktakiPlanlar(pzt, sali)).map((p) => p.baslik), [
      'A',
      'B',
    ]);
    expect((await depo.gundenItibarenPlanlar(sali)).map((p) => p.baslik), [
      'B',
      'C',
    ]);
  });

  test('çakışan plan eklenemez', () async {
    await depo.ekle(plan('Ders', pzt, 13, sure: 2));

    expect(
      () => depo.ekle(plan('Spor', pzt, 14)),
      throwsA(isA<PlanCakismaHatasi>()),
    );
    // Bitişik saat sorun değil, farklı gün sorun değil
    await depo.ekle(plan('Kitap', pzt, 15));
    await depo.ekle(plan('Spor', sali, 14));
  });

  test('guncelle: kendisiyle çakışmaz, başkasıyla çakışır', () async {
    final ders = await depo.ekle(plan('Ders', pzt, 13));
    await depo.ekle(plan('Spor', pzt, 15));

    // Kendi saatinde süreyi uzatmak serbest
    await depo.guncelle(ders.copyWith(sure: 2, baslik: 'Ders çalışma'));
    final guncel = await depo.planGetir(ders.id!);
    expect(guncel!.sure, 2);
    expect(guncel.baslik, 'Ders çalışma');

    // 15:00'teki Spor'a taşmak yasak
    expect(
      () => depo.guncelle(guncel.copyWith(sure: 3)),
      throwsA(isA<PlanCakismaHatasi>()),
    );
  });

  test('durumDegistir ve sil', () async {
    final p = await depo.ekle(plan('Ders', pzt, 13));

    await depo.durumDegistir(p.id!, PlanDurumu.yapildi);
    expect((await depo.planGetir(p.id!))!.durum, PlanDurumu.yapildi);

    await depo.sil(p.id!);
    expect(await depo.planGetir(p.id!), isNull);
  });

  test('kayma kaydı ekle ve günün kayıtlarını oku', () async {
    final k = await depo.kaymaKaydiEkle(
      KaymaKaydi(
        planId: 1,
        baslik: 'Kitap',
        gun: pzt,
        baslangicSaati: 15,
        sure: 1,
        yeniGun: sali,
        yeniBaslangicSaati: 13,
      ),
    );
    expect(k.id, isNotNull);
    expect(await depo.gununKaymaKayitlari(pzt), [k]);
    expect(await depo.gununKaymaKayitlari(sali), isEmpty);
  });

  test('ayar yaz, oku ve üzerine yaz', () async {
    expect(await depo.ayarOku('sabah_saati'), isNull);
    await depo.ayarYaz('sabah_saati', '9');
    await depo.ayarYaz('sabah_saati', '8');
    expect(await depo.ayarOku('sabah_saati'), '8');
  });

  test('yedek al ve başka bir veritabanına geri yükle', () async {
    final ders = await depo.ekle(plan('Ders', pzt, 13, sure: 2));
    await depo.ekle(plan('Spor', sali, 9));
    await depo.durumDegistir(ders.id!, PlanDurumu.yapildi);
    await depo.kaymaKaydiEkle(
      KaymaKaydi(
        planId: ders.id!,
        baslik: 'Ders',
        gun: pzt,
        baslangicSaati: 10,
        sure: 1,
        yeniGun: pzt,
        yeniBaslangicSaati: 13,
      ),
    );
    await depo.ayarYaz('sabah_saati', '8');

    final yedek = await depo.yedekAl(DateTime(2026, 10, 16, 14, 30));
    final metin = yedek.jsonMetni();

    // Yeni telefon: boş veritabanında başka bir plan var, yedek yüklenince
    // tamamen yerine geçer.
    final db2 = await Veritabani.acFactory(
      databaseFactoryFfi,
      inMemoryDatabasePath,
      tekOrnek: false,
    );
    final depo2 = PlanDeposu(db2);
    await depo2.ekle(plan('Eski', crs, 9));
    await depo2.yedektenYukle(Yedek.coz(metin));

    expect(
      await depo2.araliktakiPlanlar(pzt, crs),
      await depo.araliktakiPlanlar(pzt, crs),
    );
    expect(
      await depo2.gununKaymaKayitlari(pzt),
      await depo.gununKaymaKayitlari(pzt),
    );
    expect(await depo2.ayarOku('sabah_saati'), '8');

    // Geri yüklemeden sonra yeni eklenen plan eski kimliklerle çakışmaz.
    final yeni = await depo2.ekle(plan('Yeni', crs, 10));
    expect(yeni.id, isNot(anyOf(ders.id, ders.id! + 1)));
    await db2.close();
  });

  test('değişiklik akışı yazma işlemlerinde olay yayar', () async {
    var olay = 0;
    final abonelik = depo.degisiklikler.listen((_) => olay++);

    final p = await depo.ekle(plan('Ders', pzt, 13));
    await depo.guncelle(p.copyWith(baslik: 'Matematik'));
    await depo.durumDegistir(p.id!, PlanDurumu.yapildi);
    await depo.ayarYaz('sabah_saati', '7');
    await depo.sil(p.id!);
    await Future<void>.delayed(Duration.zero);

    expect(olay, 5);
    await abonelik.cancel();
  });

  test('veritabanı geçersiz saati kendisi de reddeder', () async {
    expect(
      () => db.insert('planlar', {
        'baslik': 'X',
        'gun': '2026-10-19',
        'baslangic_saati': 23,
        'sure': 2,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
