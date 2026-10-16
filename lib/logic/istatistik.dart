import '../utils/tarih.dart';
import 'gun_ozeti.dart';

/// Bir yılın bugüne kadarki özeti (yıllık görünümün üstündeki kart).
class YilIstatistigi {
  /// Bugüne kadar planlanan (iptal hariç) toplam plan.
  final int planSayisi;
  final int yapilan;

  /// Planların yapılmadığı için kaç kez ertesi güne kaydığı.
  final int kayma;

  /// Bütün planlarının yapıldığı en uzun ardışık gün serisi.
  final int enUzunSeri;

  /// Şu anki seri (bugün henüz bitmediği için tamamlanmadıysa seriyi bozmaz).
  final int mevcutSeri;

  const YilIstatistigi({
    required this.planSayisi,
    required this.yapilan,
    required this.kayma,
    required this.enUzunSeri,
    required this.mevcutSeri,
  });

  double? get oran => planSayisi == 0 ? null : yapilan / planSayisi;
}

/// [ozet]teki [yil] günlerinden bugüne kadarkileri özetler.
///
/// Seri: planı olan günlerde planların hepsi yapıldıysa seri devam eder,
/// biri bile kaldıysa sıfırlanır. Planı olmayan günler seriyi bozmaz.
YilIstatistigi yilIstatistigi(
  Map<DateTime, GunOzeti> ozet, {
  required int yil,
  required DateTime bugun,
}) {
  var planSayisi = 0, yapilan = 0, kayma = 0;
  var seri = 0, enUzun = 0;

  final ilk = DateTime.utc(yil, 1, 1);
  final son = DateTime.utc(yil, 12, 31);
  final bitis = bugun.isBefore(son) ? bugun : son;

  for (var g = ilk; !g.isAfter(bitis); g = gunEkle(g, 1)) {
    final o = ozet[g];
    if (o == null || o.planSayisi == 0) continue;
    planSayisi += o.planSayisi;
    yapilan += o.yapilan;
    kayma += o.kayan;

    if (o.yapilan == o.planSayisi) {
      seri++;
      if (seri > enUzun) enUzun = seri;
    } else if (g != bugun) {
      // Bugün henüz bitmedi: eksik kalan plan seriyi bozmaz.
      seri = 0;
    }
  }

  return YilIstatistigi(
    planSayisi: planSayisi,
    yapilan: yapilan,
    kayma: kayma,
    enUzunSeri: enUzun,
    mevcutSeri: seri,
  );
}

/// Yıllık kutucuğun renk yoğunluğu (0–4), GitHub katkı grafiği gibi.
/// Planı olmayan gün `null`.
int? yogunluk(GunOzeti? o) {
  final oran = o?.oran;
  if (oran == null) return null;
  if (oran >= 1) return 4;
  if (oran >= 0.66) return 3;
  if (oran >= 0.33) return 2;
  if (oran > 0) return 1;
  return 0;
}
