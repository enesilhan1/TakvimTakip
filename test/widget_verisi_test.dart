import 'package:flutter_test/flutter_test.dart';
import 'package:takvim_takip/logic/widget_verisi.dart';
import 'package:takvim_takip/models/kayma_kaydi.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  // Cumartesi 17 Ekim 2026; hafta 12–18 Ekim
  final cmt = DateTime.utc(2026, 10, 17);
  final paz = gunEkle(cmt, 1);
  final pzt = gunEkle(cmt, 2); // sonraki hafta
  final sali12 = DateTime.utc(2026, 10, 13);

  var id = 0;
  setUp(() => id = 0);

  Plan p(
    String baslik,
    DateTime gun,
    int saat, {
    int sure = 1,
    PlanDurumu durum = PlanDurumu.isaretsiz,
    String not = '',
    bool sabit = false,
  }) => Plan(
    id: ++id,
    baslik: baslik,
    gun: gun,
    baslangicSaati: saat,
    sure: sure,
    durum: durum,
    not: not,
    sabit: sabit,
  );

  WidgetVerisi hesapla(
    DateTime simdi,
    List<Plan> planlar, [
    List<KaymaKaydi> izler = const [],
  ]) => widgetVerisiHesapla(simdi: simdi, planlar: planlar, izler: izler);

  test(
    'sayılar: bugün, bütün hafta ve bütün ay (kayanlar dahil, iptal hariç)',
    () {
      final planlar = [
        p('A', cmt, 9, durum: PlanDurumu.yapildi),
        p('B', cmt, 14),
        p('C', cmt, 16, durum: PlanDurumu.iptal),
        p('D', sali12, 9, durum: PlanDurumu.yapildi),
        p('E', paz, 10), // haftanın gelecek günü de sayılır
        p('F', DateTime.utc(2026, 10, 2), 9, durum: PlanDurumu.yapildi),
        p('G', pzt, 9), // sonraki hafta, ayın içinde
      ];
      final izler = [
        KaymaKaydi(
          planId: 99,
          baslik: 'K',
          gun: sali12,
          baslangicSaati: 15,
          sure: 1,
          yeniGun: cmt,
          yeniBaslangicSaati: 14,
        ),
      ];
      final v = hesapla(DateTime(2026, 10, 17, 12), planlar, izler);

      expect(v.gun.yapilan, 1);
      expect(v.gun.toplam, 2);
      expect(v.gun.baslik, 'Bugün · 17 Eki Cumartesi');
      expect(v.hafta.yapilan, 2);
      expect(v.hafta.toplam, 5); // A,B,D,E + Salı'dan kayan K
      expect(v.hafta.baslik, 'Bu hafta · 12 Eki – 18 Eki');
      expect(v.ay.yapilan, 3);
      expect(v.ay.toplam, 7);
      expect(v.ay.baslik, 'Ekim 2026');

      expect(v.haftaGunleri.map((g) => g.ad), [
        'Pzt',
        'Sal',
        'Çar',
        'Per',
        'Cum',
        'Cmt',
        'Paz',
      ]);
      expect(v.haftaGunleri[0].oran, isNull); // plan yok
      expect(v.haftaGunleri[1].oran, 0.5); // D yapıldı, K kaydı
      expect(v.haftaGunleri[5].oran, 0.5);
      expect(v.haftaGunleri[5].bugun, isTrue);
    },
  );

  test('şu an süren işaretsiz plan "Şimdi" olarak gösterilir', () {
    final v = hesapla(DateTime(2026, 10, 17, 14, 20), [
      p('Ders', cmt, 13, sure: 2, not: 'türev'),
      p('Kitap', cmt, 17),
      p('Spor', paz, 9),
    ]);
    final o = v.odak!;
    expect(o.etiket, 'Şimdi');
    expect(o.saat, '13:00–15:00');
    expect(o.neZaman, '40 dk kaldı');
    expect(o.baslik, 'Ders');
    expect(o.not, 'türev');
    expect(o.isaretlenebilir, isTrue);
    expect(v.sonrakiler.map((s) => '${s.zaman} ${s.baslik}'), [
      '17:00 Kitap',
      'Yarın 09:00 Spor',
    ]);
    expect(v.sonrakiGuncelleme, DateTime(2026, 10, 17, 15));
  });

  test('şu anki plan yapıldıysa sıradaki gösterilir', () {
    final v = hesapla(DateTime(2026, 10, 17, 14, 45), [
      p('Ders', cmt, 14, durum: PlanDurumu.yapildi),
      p('Kitap', cmt, 17, sabit: true),
    ]);
    expect(v.odak!.etiket, 'Sıradaki');
    expect(v.odak!.neZaman, '2 sa 15 dk sonra');
    expect(v.odak!.sabit, isTrue);
    expect(v.sonrakiGuncelleme, DateTime(2026, 10, 17, 17));
  });

  test('bugün plan kalmadıysa sonraki günler; işaretleme butonu yok', () {
    final v = hesapla(DateTime(2026, 10, 17, 20), [
      p('Bitti', cmt, 9),
      p('Uzak', DateTime.utc(2026, 10, 24), 10),
    ]);
    // Bugünün 09:00 planı geçti (gece kaydırılacak), odak değil
    expect(v.odak!.baslik, 'Uzak');
    expect(v.odak!.etiket, 'Cmt 24 Eki');
    expect(v.odak!.neZaman, '');
    expect(v.odak!.isaretlenebilir, isFalse);
    expect(v.sonrakiGuncelleme, DateTime(2026, 10, 18));
  });

  test('hiç plan yoksa odak yok, güncelleme gece yarısı', () {
    final v = hesapla(DateTime(2026, 10, 17, 10), const []);
    expect(v.odak, isNull);
    expect(v.sonrakiler, isEmpty);
    expect(v.gun.toplam, 0);
    expect(v.sonrakiGuncelleme, DateTime(2026, 10, 18));
  });

  test('JSON biçimi', () {
    final j = hesapla(DateTime(2026, 10, 17, 13, 30), [
      p('Ders', cmt, 13),
    ]).toJson();
    expect(j['gun'], {
      'baslik': 'Bugün · 17 Eki Cumartesi',
      'yapilan': 0,
      'toplam': 1,
    });
    expect((j['odak'] as Map)['plan_id'], 1);
    expect((j['odak'] as Map)['ne_zaman'], '30 dk kaldı');
    expect((j['hafta_gunleri'] as List), hasLength(7));
  });

  test('veri aralığı haftayı, ayı ve 30 günü kapsar', () {
    // 1 Ekim 2026 Perşembe: hafta 28 Eylül'de başlar
    final r = widgetAraligi(DateTime(2026, 10, 1, 9));
    expect(r.bas, DateTime.utc(2026, 9, 28));
    expect(r.bit, DateTime.utc(2026, 10, 31));
    final r2 = widgetAraligi(DateTime(2026, 10, 28, 9));
    expect(r2.bit, DateTime.utc(2026, 11, 27));
  });
}
