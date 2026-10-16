import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/logic/kaydirma_servisi.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;
  late KaydirmaServisi servis;

  final pzr = DateTime.utc(2026, 10, 18);
  final pzt = gunEkle(pzr, 1);
  final sali = gunEkle(pzr, 2);
  final crs = gunEkle(pzr, 3);
  final prs = gunEkle(pzr, 4);

  /// Yerel saatle `gun` günü, saat `saat`.
  DateTime an(DateTime gun, int saat) =>
      DateTime(gun.year, gun.month, gun.day, saat);

  setUp(() async {
    db = await Veritabani.acFactory(databaseFactoryFfi, inMemoryDatabasePath);
    depo = PlanDeposu(db);
    servis = KaydirmaServisi(depo);
  });

  tearDown(() => db.close());

  Future<Plan> ekle(
    String baslik,
    DateTime gun,
    int saat, {
    bool sabit = false,
    PlanDurumu durum = PlanDurumu.isaretsiz,
  }) => depo.ekle(
    Plan(
      baslik: baslik,
      gun: gun,
      baslangicSaati: saat,
      sabit: sabit,
      durum: durum,
    ),
  );

  Future<void> sonIslenen(DateTime gun) =>
      depo.ayarYaz(KaydirmaServisi.sonIslenenGunAyari, gunAnahtari(gun));

  Future<List<String>> takvim() async => [
    for (final p in await depo.gundenItibarenPlanlar(pzr))
      '${gunAdi(p.gun)} ${p.saatAraligi} ${p.baslik}',
  ];

  test('ilk çalıştırma geçmişi işlemez, takibi dünden başlatır', () async {
    await ekle('Eski', pzt, 9);

    final sonuc = await servis.bekleyenGunleriIsle(an(sali, 10));

    expect(sonuc, isEmpty);
    expect(
      await depo.ayarOku(KaydirmaServisi.sonIslenenGunAyari),
      gunAnahtari(pzt),
    );
    expect(await takvim(), ['Pazartesi 09:00 Eski']);
  });

  test('dünü kapatır ve veritabanına yazar (SPEC Örnek 1)', () async {
    await sonIslenen(pzr);
    await ekle('Ders', pzt, 13, durum: PlanDurumu.yapildi);
    await ekle('Spor', pzt, 14, durum: PlanDurumu.yapildi);
    final kitap = await ekle('Kitap', pzt, 15);
    await ekle('Ders2', sali, 13);
    await ekle('📌Spor', sali, 14, sabit: true);
    await ekle('Kitap2', sali, 15);

    final sonuc = await servis.bekleyenGunleriIsle(an(sali, 8));

    expect(sonuc, hasLength(1));
    expect(sonuc.single.yapilmayanSayisi, 1);
    expect(sonuc.single.kayanSayisi, 3);
    expect(await takvim(), [
      'Pazartesi 13:00 Ders',
      'Pazartesi 14:00 Spor',
      'Salı 13:00 Kitap',
      'Salı 14:00 📌Spor',
      'Salı 15:00 Ders2',
      'Çarşamba 15:00 Kitap2',
    ]);
    expect((await depo.planGetir(kitap.id!))!.yapilmadiSayisi, 1);

    final iz = await depo.gununKaymaKayitlari(pzt);
    expect(iz.single.planId, kitap.id);
    expect(iz.single.aciklama, "yapılmadı → Salı 13:00'e kaydı");
    expect(
      await depo.ayarOku(KaydirmaServisi.sonIslenenGunAyari),
      gunAnahtari(pzt),
    );
  });

  test('kaçırılan günleri sırayla işler', () async {
    await sonIslenen(pzr);
    final a = await ekle('A', pzt, 9);

    // Uygulama Pazartesi'den Perşembe'ye kadar hiç açılmadı.
    final sonuc = await servis.bekleyenGunleriIsle(an(prs, 7));

    expect(sonuc.map((s) => s.kapananGun), [pzt, sali, crs]);
    expect(await takvim(), ['Perşembe 09:00 A']);
    expect((await depo.planGetir(a.id!))!.yapilmadiSayisi, 3);
    expect(await depo.gununKaymaKayitlari(pzt), hasLength(1));
    expect(await depo.gununKaymaKayitlari(sali), hasLength(1));
    expect(await depo.gununKaymaKayitlari(crs), hasLength(1));
  });

  test('aynı gün ikinci kez çalışınca hiçbir şey yapmaz', () async {
    await sonIslenen(pzr);
    await ekle('A', pzt, 9);

    await servis.bekleyenGunleriIsle(an(sali, 8));
    final ikinci = await servis.bekleyenGunleriIsle(an(sali, 22));

    expect(ikinci, isEmpty);
    expect(await takvim(), ['Salı 09:00 A']);
  });

  test('kapanış özeti sabah bildirimi için saklanır', () async {
    await sonIslenen(pzr);
    await ekle('A', pzt, 9);
    await ekle('B', pzt, 10, durum: PlanDurumu.yapildi);
    await ekle('X', sali, 9);

    await servis.bekleyenGunleriIsle(an(sali, 8));

    final ozet = await depo.kapanisOzeti(pzt);
    expect(ozet?.yapilmayan, 1);
    expect(ozet?.kayan, 2); // A kendisi + itilen X
    expect(await depo.kapanisOzeti(sali), isNull);
  });

  test('aynı anda iki görev çalışsa da gün bir kez kaydırılır', () async {
    // Gece yarısı arka plan görevi ile uygulamanın açılışı çakışırsa.
    await sonIslenen(pzr);
    final a = await ekle('A', pzt, 9);

    final sonuclar = await Future.wait([
      servis.bekleyenGunleriIsle(an(sali, 0)),
      KaydirmaServisi(depo).bekleyenGunleriIsle(an(sali, 0)),
    ]);

    expect(sonuclar.expand((s) => s), hasLength(1));
    expect(await takvim(), ['Salı 09:00 A']);
    expect((await depo.planGetir(a.id!))!.yapilmadiSayisi, 1);
    expect(await depo.gununKaymaKayitlari(pzt), hasLength(1));
  });

  test('bugünün planlarına dokunmaz (gün henüz bitmedi)', () async {
    await sonIslenen(pzr);
    await ekle('Bugun', pzt, 9);

    final sonuc = await servis.bekleyenGunleriIsle(an(pzt, 23));

    expect(sonuc, isEmpty);
    expect(await takvim(), ['Pazartesi 09:00 Bugun']);
  });
}
