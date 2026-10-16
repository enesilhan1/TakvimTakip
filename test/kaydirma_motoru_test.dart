import 'package:flutter_test/flutter_test.dart';
import 'package:takvim_takip/logic/kaydirma_motoru.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

/// docs/SPEC.md §4'teki örnekler ve sınır durumları.
void main() {
  final pzt = DateTime.utc(2026, 10, 19);
  final sali = gunEkle(pzt, 1);
  final crs = gunEkle(pzt, 2);
  final prs = gunEkle(pzt, 3);
  final cuma = gunEkle(pzt, 4);
  final cmt = gunEkle(pzt, 5);

  var sonId = 0;
  setUp(() => sonId = 0);

  Plan p(
    String baslik,
    DateTime gun,
    int saat, {
    int sure = 1,
    bool sabit = false,
    PlanDurumu durum = PlanDurumu.isaretsiz,
    int sayac = 0,
  }) => Plan(
    id: ++sonId,
    baslik: baslik,
    gun: gun,
    baslangicSaati: saat,
    sure: sure,
    sabit: sabit,
    durum: durum,
    yapilmadiSayisi: sayac,
  );

  /// Sonucu planlara uygular ve takvimi okunur satırlar halinde döndürür:
  /// `Salı 13:00–15:00 Ders`.
  List<String> uygula(List<Plan> planlar, KaydirmaSonucu sonuc) {
    final yeni = {for (final x in planlar) x.id: x};
    for (final d in sonuc.degisenPlanlar) {
      yeni[d.id] = d;
    }
    final liste = yeni.values.toList()
      ..sort((a, b) {
        final g = a.gun.compareTo(b.gun);
        return g != 0 ? g : a.baslangicSaati.compareTo(b.baslangicSaati);
      });
    return [
      for (final x in liste) '${gunAdi(x.gun)} ${x.saatAraligi} ${x.baslik}',
    ];
  }

  Plan bul(KaydirmaSonucu s, String baslik) =>
      s.degisenPlanlar.firstWhere((x) => x.baslik == baslik);

  test('Örnek 1: temel senaryo (sabit atlanır, zincir devam eder)', () {
    final planlar = [
      p('Ders', pzt, 13, durum: PlanDurumu.yapildi),
      p('Spor', pzt, 14, durum: PlanDurumu.yapildi),
      p('Kitap', pzt, 15),
      p('Ders2', sali, 13),
      p('📌Spor', sali, 14, sabit: true),
      p('Kitap2', sali, 15),
    ];
    final s = gunuKapat(pzt, planlar);

    expect(uygula(planlar, s), [
      'Pazartesi 13:00 Ders',
      'Pazartesi 14:00 Spor',
      'Salı 13:00 Kitap',
      'Salı 14:00 📌Spor',
      'Salı 15:00 Ders2',
      'Çarşamba 15:00 Kitap2',
    ]);
    expect(s.yapilmayanSayisi, 1);
    expect(s.kayanSayisi, 3);
    expect(bul(s, 'Kitap').yapilmadiSayisi, 1);
    expect(bul(s, 'Ders2').yapilmadiSayisi, 0, reason: 'sadece itildi');
    expect(s.kaymaKayitlari.single.aciklama, "yapılmadı → Salı 13:00'e kaydı");
    expect(s.kaymaKayitlari.single.gun, pzt);
    expect(s.kaymaKayitlari.single.baslangicSaati, 15);
  });

  test('Örnek 2: boş saatlere dokunulmaz', () {
    final planlar = [
      p('K', pzt, 15),
      p('Sabah', sali, 9),
      p('Akşam', sali, 20),
    ];
    expect(uygula(planlar, gunuKapat(pzt, planlar)), [
      'Salı 09:00 K',
      'Salı 20:00 Sabah',
      'Çarşamba 20:00 Akşam',
    ]);
  });

  test('Örnek 3: birden fazla yapılmayan sırasını korur, bant iki kayar', () {
    final planlar = [
      p('A', pzt, 13),
      p('B', pzt, 15),
      p('X', sali, 10),
      p('Y', sali, 11),
      p('Z', sali, 12),
    ];
    final s = gunuKapat(pzt, planlar);
    expect(uygula(planlar, s), [
      'Salı 10:00 A',
      'Salı 11:00 B',
      'Salı 12:00 X',
      'Çarşamba 11:00 Y',
      'Çarşamba 12:00 Z',
    ]);
    expect(s.yapilmayanSayisi, 2);
    expect(s.kayanSayisi, 5);
  });

  test('Örnek 4: zincirin sonu ertesi günün aynı saatine gider', () {
    final planlar = [p('K', pzt, 9), p('X', sali, 13)];
    expect(uygula(planlar, gunuKapat(pzt, planlar)), [
      'Salı 13:00 K',
      'Çarşamba 13:00 X',
    ]);
  });

  test('Örnek 4b: hedef saat doluysa bir gün daha ileri gider', () {
    final planlar = [
      p('K', pzt, 9),
      p('X', sali, 13),
      p('📌Sabit', crs, 13, sabit: true),
      p('Bitti', prs, 12, sure: 2, durum: PlanDurumu.yapildi),
    ];
    expect(uygula(planlar, gunuKapat(pzt, planlar)), [
      'Salı 13:00 K',
      'Çarşamba 13:00 📌Sabit',
      'Perşembe 12:00–14:00 Bitti',
      'Cuma 13:00 X',
    ]);
  });

  test('Örnek 4c: gelecekte hiç plan yoksa ertesi günün aynı saatine', () {
    final planlar = [p('A', pzt, 13), p('B', pzt, 15, sure: 2)];
    expect(uygula(planlar, gunuKapat(pzt, planlar)), [
      'Salı 13:00 A',
      'Salı 15:00–17:00 B',
    ]);
  });

  test('Örnek 5: içerik girdiği slotun süresini alır', () {
    final planlar = [
      p('Kitap', pzt, 15),
      p('Ders', sali, 13, sure: 2),
      p('Spor', sali, 18),
    ];
    final s = gunuKapat(pzt, planlar);
    expect(uygula(planlar, s), [
      'Salı 13:00–15:00 Kitap',
      'Salı 18:00 Ders',
      'Çarşamba 18:00 Spor',
    ]);
    expect(bul(s, 'Kitap').sure, 2);
    expect(bul(s, 'Ders').sure, 1);
  });

  test('Örnek 6: iptal, yapıldı ve sabit planlar kapanan günde kalır', () {
    final planlar = [
      p('Kahve', pzt, 15, durum: PlanDurumu.iptal),
      p('Ders', pzt, 13, durum: PlanDurumu.yapildi),
      p('📌Doktor', pzt, 10, sabit: true),
      p('X', sali, 13),
    ];
    final s = gunuKapat(pzt, planlar);
    expect(s.bos, isTrue);
    expect(s.yapilmayanSayisi, 0);
  });

  test('gelecekte yapıldı/iptal işaretli planlar banda girmez', () {
    final planlar = [
      p('K', pzt, 9),
      p('ErkenBitti', sali, 10, durum: PlanDurumu.yapildi),
      p('Iptal', sali, 11, durum: PlanDurumu.iptal),
      p('X', sali, 12),
    ];
    expect(uygula(planlar, gunuKapat(pzt, planlar)), [
      'Salı 10:00 ErkenBitti',
      'Salı 11:00 Iptal',
      'Salı 12:00 K',
      'Çarşamba 12:00 X',
    ]);
  });

  test('yapılmadı sayacı birikir', () {
    final planlar = [p('K', pzt, 9, sayac: 2), p('X', sali, 9, sayac: 5)];
    final s = gunuKapat(pzt, planlar);
    expect(bul(s, 'K').yapilmadiSayisi, 3);
    expect(bul(s, 'X').yapilmadiSayisi, 5);
  });

  test('kapanan günden önceki planlar yok sayılır', () {
    final planlar = [
      p('Eski', gunEkle(pzt, -1), 9),
      p('K', pzt, 9),
      p('X', sali, 9),
    ];
    final s = gunuKapat(pzt, planlar);
    expect(s.degisenPlanlar.map((x) => x.baslik), ['K', 'X']);
  });

  test('zincir sonundakiler sıralarını korur (aradaki günler uzaksa)', () {
    // Bant: Salı 13 ve Cuma 9. İki plan yapılmadı → bant iki kayar.
    // X'in kendi saati (13:00) Cuma 9'dan önceye düşmemeli.
    final planlar = [
      p('A', pzt, 8),
      p('B', pzt, 9),
      p('X', sali, 13),
      p('Y', cuma, 9),
    ];
    expect(uygula(planlar, gunuKapat(pzt, planlar)), [
      'Salı 13:00 A',
      'Cuma 09:00 B',
      'Cuma 13:00 X',
      'Cumartesi 09:00 Y',
    ]);
    expect(cmt.weekday, DateTime.saturday);
  });

  test('saf fonksiyon: girdi listesi değişmez', () {
    final planlar = [p('K', pzt, 9), p('X', sali, 9)];
    final kopya = List.of(planlar);
    gunuKapat(pzt, planlar);
    expect(planlar, kopya);
  });
}
