import '../models/kayma_kaydi.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';
import 'gun_ozeti.dart';

/// Ana ekran widget'larının göstereceği her şey (docs/SPEC.md §11).
///
/// Dart'ta hesaplanır ve JSON olarak widget deposuna yazılır; Android
/// tarafı (Kotlin) yalnızca gösterir.
class WidgetVerisi {
  final Sayac gun;
  final Sayac hafta;
  final Sayac ay;

  /// Haftanın 7 günü (Pzt–Paz): tamamlanma oranı, plan yoksa null.
  final List<HaftaGunu> haftaGunleri;

  /// Şu an yapılması gereken ya da sıradaki plan; yoksa null.
  final OdakPlan? odak;

  /// Odaktan sonraki en fazla 3 plan (büyük widget'ta listelenir).
  final List<SiradakiPlan> sonrakiler;

  /// Widget'ın bir sonraki kendini yenilemesi gereken an (şu anki planın
  /// bitişi, sıradaki planın başlangıcı ya da gece yarısı).
  final DateTime sonrakiGuncelleme;

  const WidgetVerisi({
    required this.gun,
    required this.hafta,
    required this.ay,
    required this.haftaGunleri,
    required this.odak,
    required this.sonrakiler,
    required this.sonrakiGuncelleme,
  });

  Map<String, Object?> toJson() => {
    'gun': gun.toJson(),
    'hafta': hafta.toJson(),
    'ay': ay.toJson(),
    'hafta_gunleri': [for (final g in haftaGunleri) g.toJson()],
    'odak': odak?.toJson(),
    'sonrakiler': [for (final s in sonrakiler) s.toJson()],
  };
}

class Sayac {
  final String baslik;
  final int yapilan;
  final int toplam;

  const Sayac(this.baslik, this.yapilan, this.toplam);

  Map<String, Object?> toJson() => {
    'baslik': baslik,
    'yapilan': yapilan,
    'toplam': toplam,
  };
}

class HaftaGunu {
  final String ad;
  final double? oran;
  final bool bugun;

  const HaftaGunu(this.ad, this.oran, {required this.bugun});

  Map<String, Object?> toJson() => {'ad': ad, 'oran': oran, 'bugun': bugun};
}

class OdakPlan {
  /// "Şimdi", "Sıradaki", "Yarın", "Cmt 24 Eki"
  final String etiket;

  /// "14:00–16:00" ya da "17:00"
  final String saat;

  /// "2 sa 15 dk sonra", "1 sa 10 dk kaldı" (bugün değilse boş)
  final String neZaman;
  final String baslik;
  final String not;
  final bool sabit;
  final int planId;

  /// "✓ Yapıldı" butonu gösterilsin mi (yalnızca bugünün planlarında).
  final bool isaretlenebilir;

  const OdakPlan({
    required this.etiket,
    required this.saat,
    required this.neZaman,
    required this.baslik,
    required this.not,
    required this.sabit,
    required this.planId,
    required this.isaretlenebilir,
  });

  Map<String, Object?> toJson() => {
    'etiket': etiket,
    'saat': saat,
    'ne_zaman': neZaman,
    'baslik': baslik,
    'not': not,
    'sabit': sabit,
    'plan_id': planId,
    'isaretlenebilir': isaretlenebilir,
  };
}

class SiradakiPlan {
  /// "17:00" ya da "Yarın 09:00"
  final String zaman;
  final String baslik;

  const SiradakiPlan(this.zaman, this.baslik);

  Map<String, Object?> toJson() => {'zaman': zaman, 'baslik': baslik};
}

/// Widget verisinin hesaplanması için gereken tarih aralığı: bu hafta, bu
/// ay ve önümüzdeki 30 gün.
({DateTime bas, DateTime bit}) widgetAraligi(DateTime simdi) {
  final bugun = gunOf(simdi);
  final pzt = haftaBasi(bugun);
  final ay1 = ayBasi(bugun);
  final ayson = DateTime.utc(bugun.year, bugun.month, aydakiGunSayisi(bugun));
  final adaylar = [gunEkle(pzt, 6), ayson, gunEkle(bugun, 30)];
  return (
    bas: pzt.isBefore(ay1) ? pzt : ay1,
    bit: adaylar.reduce((a, b) => a.isAfter(b) ? a : b),
  );
}

/// Widget verisini hesaplar. [planlar] ve [izler] [widgetAraligi]'nı
/// kapsamalıdır.
WidgetVerisi widgetVerisiHesapla({
  required DateTime simdi,
  required List<Plan> planlar,
  required List<KaymaKaydi> izler,
}) {
  final bugun = gunOf(simdi);
  final ozet = gunlukOzet(planlar, izler);

  Sayac topla(String baslik, DateTime bas, DateTime bit) {
    var yapilan = 0, toplam = 0;
    for (var g = bas; !g.isAfter(bit); g = gunEkle(g, 1)) {
      final o = ozet[g];
      if (o == null) continue;
      yapilan += o.yapilan;
      toplam += o.planSayisi;
    }
    return Sayac(baslik, yapilan, toplam);
  }

  final pzt = haftaBasi(bugun);
  final paz = gunEkle(pzt, 6);
  final ay1 = ayBasi(bugun);
  final ayson = DateTime.utc(bugun.year, bugun.month, aydakiGunSayisi(bugun));

  // Şu anki ve sıradaki planlar: işaretsiz olanlar, zaman sırasıyla.
  final saat = simdi.hour;
  bool gecti(Plan p) =>
      p.gun.isBefore(bugun) || (p.gun == bugun && p.bitisSaati <= saat);
  final bekleyenler =
      planlar
          .where((p) => p.durum == PlanDurumu.isaretsiz && !gecti(p))
          .toList()
        ..sort((a, b) {
          final g = a.gun.compareTo(b.gun);
          return g != 0 ? g : a.baslangicSaati.compareTo(b.baslangicSaati);
        });

  DateTime an(Plan p, int s) => DateTime(p.gun.year, p.gun.month, p.gun.day, s);

  OdakPlan? odak;
  if (bekleyenler.isNotEmpty) {
    final p = bekleyenler.first;
    final simdiki = p.gun == bugun && p.baslangicSaati <= saat;
    odak = OdakPlan(
      etiket: simdiki
          ? 'Şimdi'
          : p.gun == bugun
          ? 'Sıradaki'
          : _gunEtiketi(p.gun, bugun),
      saat: p.saatAraligi,
      neZaman: p.gun != bugun
          ? ''
          : simdiki
          ? '${_sure(an(p, p.bitisSaati).difference(simdi))} kaldı'
          : '${_sure(an(p, p.baslangicSaati).difference(simdi))} sonra',
      baslik: p.baslik,
      not: p.not,
      sabit: p.sabit,
      planId: p.id!,
      isaretlenebilir: p.gun == bugun,
    );
  }

  final sonrakiler = [
    for (final p in bekleyenler.skip(1).take(3))
      SiradakiPlan(
        p.gun == bugun
            ? saatMetni(p.baslangicSaati)
            : '${_gunEtiketi(p.gun, bugun)} ${saatMetni(p.baslangicSaati)}',
        p.baslik,
      ),
  ];

  // Bir sonraki değişim anı: şu anki planın bitişi ya da sıradakinin
  // başlangıcı (bugün içindeyse), yoksa gece yarısı.
  var sonraki = DateTime(simdi.year, simdi.month, simdi.day + 1);
  for (final p in bekleyenler.where((p) => p.gun == bugun)) {
    for (final s in [p.baslangicSaati, p.bitisSaati]) {
      final t = an(p, s);
      if (t.isAfter(simdi) && t.isBefore(sonraki)) sonraki = t;
    }
  }

  return WidgetVerisi(
    gun: topla(
      'Bugün · ${bugun.day} ${_kisaAy(bugun)} ${gunAdi(bugun)}',
      bugun,
      bugun,
    ),
    hafta: topla(
      'Bu hafta · ${pzt.day} ${_kisaAy(pzt)} – ${paz.day} ${_kisaAy(paz)}',
      pzt,
      paz,
    ),
    ay: topla('${ayAdlari[bugun.month - 1]} ${bugun.year}', ay1, ayson),
    haftaGunleri: [
      for (var i = 0; i < 7; i++)
        HaftaGunu(
          kisaGunAdi(gunEkle(pzt, i)),
          ozet[gunEkle(pzt, i)]?.oran,
          bugun: gunEkle(pzt, i) == bugun,
        ),
    ],
    odak: odak,
    sonrakiler: sonrakiler,
    sonrakiGuncelleme: sonraki,
  );
}

String _kisaAy(DateTime g) => ayAdlari[g.month - 1].substring(0, 3);

String _gunEtiketi(DateTime gun, DateTime bugun) {
  if (gun == gunEkle(bugun, 1)) return 'Yarın';
  return '${kisaGunAdi(gun)} ${gun.day} ${_kisaAy(gun)}';
}

/// "45 dk", "2 sa", "2 sa 15 dk"
String _sure(Duration d) {
  final dk = (d.inSeconds / 60).ceil();
  final sa = dk ~/ 60, kalan = dk % 60;
  if (sa == 0) return '$kalan dk';
  if (kalan == 0) return '$sa sa';
  return '$sa sa $kalan dk';
}
