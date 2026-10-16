import 'package:flutter_test/flutter_test.dart';
import 'package:takvim_takip/models/kayma_kaydi.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  final pzt = DateTime.utc(2026, 10, 19); // Pazartesi
  final sali = DateTime.utc(2026, 10, 20);

  group('tarih yardımcıları', () {
    test('gün anahtarı gidiş-dönüş', () {
      expect(gunAnahtari(pzt), '2026-10-19');
      expect(gunAnahtarindan('2026-10-19'), pzt);
    });

    test('gün ekleme ay ve yıl sınırını geçer', () {
      expect(gunEkle(DateTime.utc(2026, 12, 31), 1), DateTime.utc(2027, 1, 1));
      expect(gunEkle(DateTime.utc(2026, 3, 1), -1), DateTime.utc(2026, 2, 28));
    });

    test('gunOf saat bilgisini atar', () {
      expect(gunOf(DateTime(2026, 10, 19, 23, 59)), pzt);
    });

    test('Türkçe gün adı', () {
      expect(gunAdi(pzt), 'Pazartesi');
      expect(gunAdi(sali), 'Salı');
    });

    test('saat yönelme eki okunuşa uyar', () {
      expect(saatYonelmeEki(13), "'e");
      expect(saatYonelmeEki(10), "'a");
      expect(saatYonelmeEki(9), "'a");
      expect(saatYonelmeEki(6), "'ya");
      expect(saatYonelmeEki(2), "'ye");
      expect(saatYonelmeEki(20), "'ye");
      expect(saatYonelmeEki(0), "'a");
    });
  });

  group('Plan', () {
    test('varsayılanlar ve bitiş saati', () {
      final p = Plan(baslik: 'Ders', gun: pzt, baslangicSaati: 13, sure: 2);
      expect(p.bitisSaati, 15);
      expect(p.durum, PlanDurumu.isaretsiz);
      expect(p.sabit, isFalse);
      expect(p.yapilmadiSayisi, 0);
      expect(p.saatAraligi, '13:00–15:00');
      expect(
        Plan(baslik: 'Spor', gun: pzt, baslangicSaati: 14).saatAraligi,
        '14:00',
      );
    });

    test('gün saatsiz tutulur', () {
      final p = Plan(
        baslik: 'X',
        gun: DateTime(2026, 10, 19, 15, 30),
        baslangicSaati: 1,
      );
      expect(p.gun, pzt);
    });

    test('geçersiz değerler reddedilir', () {
      expect(
        () => Plan(baslik: ' ', gun: pzt, baslangicSaati: 1),
        throwsArgumentError,
      );
      expect(
        () => Plan(baslik: 'X', gun: pzt, baslangicSaati: 24),
        throwsArgumentError,
      );
      expect(
        () => Plan(baslik: 'X', gun: pzt, baslangicSaati: 1, sure: 0),
        throwsArgumentError,
      );
      // 23:00 + 2 saat gece yarısını geçer
      expect(
        () => Plan(baslik: 'X', gun: pzt, baslangicSaati: 23, sure: 2),
        throwsArgumentError,
      );
      // 23:00–24:00 geçerli
      expect(Plan(baslik: 'X', gun: pzt, baslangicSaati: 23).bitisSaati, 24);
    });

    test('kayabilir: sadece sabit olmayan ve işaretsiz', () {
      final p = Plan(baslik: 'X', gun: pzt, baslangicSaati: 1);
      expect(p.kayabilir, isTrue);
      expect(p.copyWith(sabit: true).kayabilir, isFalse);
      expect(p.copyWith(durum: PlanDurumu.yapildi).kayabilir, isFalse);
      expect(p.copyWith(durum: PlanDurumu.iptal).kayabilir, isFalse);
    });

    test('çakışma kontrolü', () {
      final ders = Plan(baslik: 'Ders', gun: pzt, baslangicSaati: 13, sure: 2);
      Plan p(int saat, [int sure = 1, DateTime? gun]) =>
          Plan(baslik: 'P', gun: gun ?? pzt, baslangicSaati: saat, sure: sure);

      expect(ders.cakisir(p(13)), isTrue);
      expect(ders.cakisir(p(14)), isTrue);
      expect(ders.cakisir(p(12, 2)), isTrue);
      expect(ders.cakisir(p(15)), isFalse, reason: 'bitiş saati dahil değil');
      expect(ders.cakisir(p(12)), isFalse);
      expect(ders.cakisir(p(13, 1, sali)), isFalse, reason: 'farklı gün');
    });

    test('toMap / fromMap gidiş-dönüş', () {
      final p = Plan(
        id: 7,
        baslik: 'Kitap okuma',
        not: '50 sayfa',
        gun: pzt,
        baslangicSaati: 15,
        sure: 2,
        sabit: true,
        durum: PlanDurumu.iptal,
        yapilmadiSayisi: 3,
      );
      expect(Plan.fromMap(p.toMap()), p);
    });
  });

  group('KaymaKaydi', () {
    test('açıklama metni', () {
      final k = KaymaKaydi(
        planId: 1,
        baslik: 'Kitap okuma',
        gun: pzt,
        baslangicSaati: 15,
        sure: 1,
        yeniGun: sali,
        yeniBaslangicSaati: 13,
      );
      expect(k.aciklama, "yapılmadı → Salı 13:00'e kaydı");
      expect(KaymaKaydi.fromMap(k.toMap()), k);
    });
  });
}
