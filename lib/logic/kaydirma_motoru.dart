import '../models/kayma_kaydi.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';

/// Bir günün kapanışında yapılan kaydırmanın sonucu.
class KaydirmaSonucu {
  final DateTime kapananGun;

  /// Yeni gün/saat/süresi (ve yapılmadı sayısı) atanmış planlar.
  /// Veritabanına aynen yazılır.
  final List<Plan> degisenPlanlar;

  /// Kapanan günde, yapılmayan her plan için bir iz.
  final List<KaymaKaydi> kaymaKayitlari;

  const KaydirmaSonucu(
    this.kapananGun,
    this.degisenPlanlar,
    this.kaymaKayitlari,
  );

  /// Kapanan günde yapılmayan (kendi kayan) plan sayısı.
  int get yapilmayanSayisi => kaymaKayitlari.length;

  /// Yeri değişen toplam plan sayısı (itilenler dahil).
  int get kayanSayisi => degisenPlanlar.length;

  bool get bos => degisenPlanlar.isEmpty;
}

/// Bir planın kapladığı saat aralığı.
class _Slot {
  final DateTime gun;
  final int bas;
  final int sure;

  _Slot(this.gun, this.bas, this.sure);

  _Slot.of(Plan p) : this(p.gun, p.baslangicSaati, p.sure);

  int get bit => bas + sure;

  bool cakisir(_Slot o) => gun == o.gun && bas < o.bit && o.bas < bit;

  /// Zaman sırasında [o]dan sonra mı başlıyor?
  bool sonra(_Slot o) => gun.isAfter(o.gun) || (gun == o.gun && bas > o.bas);
}

int _zamanSirasi(Plan a, Plan b) {
  final g = a.gun.compareTo(b.gun);
  return g != 0 ? g : a.baslangicSaati.compareTo(b.baslangicSaati);
}

/// [kapananGun] 23:59'da kapanırken "yürüyen bant" kuralını uygular
/// (docs/SPEC.md §4).
///
/// [planlar] en az kapanan gün ve sonrasındaki tüm planları içermelidir;
/// daha önceki günlerin planları yok sayılır. Planların kimliği (id)
/// olmalıdır. Fonksiyon saftır: hiçbir şeyi değiştirmez, sadece sonucu
/// hesaplar.
KaydirmaSonucu gunuKapat(DateTime kapananGun, List<Plan> planlar) {
  final gun = gunOf(kapananGun);
  final ilgili = planlar.where((p) => !p.gun.isBefore(gun)).toList()
    ..sort(_zamanSirasi);

  // Kapanan günün yapılmayanları, saat sırasıyla (kural 2).
  final yapilmayanlar = ilgili
      .where((p) => p.gun == gun && p.kayabilir)
      .toList();
  if (yapilmayanlar.isEmpty) return KaydirmaSonucu(gun, const [], const []);

  // Bant: sonraki günlerin sabit olmayan, işaretsiz planları (kural 1).
  // Sabitler, yapıldı/iptal olanlar ve boş saatler banda girmez.
  final bant = ilgili.where((p) => p.gun.isAfter(gun) && p.kayabilir).toList();

  // İçerikler bant üzerinde, yapılmayanlar başta olacak şekilde sıralanır.
  final icerikler = [...yapilmayanlar, ...bant];
  final yeniSlotlar = <_Slot>[for (final p in bant) _Slot.of(p)];

  // Bantta yeri kalmayanlar (zincirin sonu, kural 4): kendi eski saat
  // aralığıyla, ertesi günden başlayarak, zincirde kendinden öncekinden sonra
  // gelen ve hiçbir planla çakışmayan ilk güne yerleşir.
  final dolu = <_Slot>[
    for (final p in ilgili)
      if (p.gun.isAfter(gun)) _Slot.of(p),
  ];
  var onceki = yeniSlotlar.isEmpty ? null : yeniSlotlar.last;
  for (final p in icerikler.skip(bant.length)) {
    var aday = _Slot(gunEkle(p.gun, 1), p.baslangicSaati, p.sure);
    while ((onceki != null && !aday.sonra(onceki)) || dolu.any(aday.cakisir)) {
      aday = _Slot(gunEkle(aday.gun, 1), aday.bas, aday.sure);
    }
    yeniSlotlar.add(aday);
    dolu.add(aday);
    onceki = aday;
  }

  final degisen = <Plan>[];
  final kayitlar = <KaymaKaydi>[];
  for (var i = 0; i < icerikler.length; i++) {
    final p = icerikler[i];
    final s = yeniSlotlar[i];
    final yapilmadi = i < yapilmayanlar.length;

    // İçerik girdiği slotun süresini alır (kural 3); sayaç sadece
    // yapılmayanlarda artar (kural 5).
    degisen.add(
      p.copyWith(
        gun: s.gun,
        baslangicSaati: s.bas,
        sure: s.sure,
        yapilmadiSayisi: p.yapilmadiSayisi + (yapilmadi ? 1 : 0),
      ),
    );

    if (yapilmadi) {
      // Kapanan günde kalan iz (kural 6).
      kayitlar.add(
        KaymaKaydi(
          planId: p.id!,
          baslik: p.baslik,
          gun: p.gun,
          baslangicSaati: p.baslangicSaati,
          sure: p.sure,
          yeniGun: s.gun,
          yeniBaslangicSaati: s.bas,
        ),
      );
    }
  }

  return KaydirmaSonucu(gun, degisen, kayitlar);
}
