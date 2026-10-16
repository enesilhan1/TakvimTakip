import '../models/kayma_kaydi.dart';
import '../models/plan.dart';

/// Bir günün tamamlanma özeti (aylık ve yıllık görünümler için).
class GunOzeti {
  /// O günde yapılan planlar.
  final int yapilan;

  /// O günde hâlâ duran, iptal edilmemiş planlar (yapılan dahil).
  final int kalan;

  /// O gün yapılmadığı için başka güne kayan planlar.
  final int kayan;

  final int iptal;

  const GunOzeti({
    this.yapilan = 0,
    this.kalan = 0,
    this.kayan = 0,
    this.iptal = 0,
  });

  /// O güne planlanmış (iptal hariç) toplam plan: yerinde duranlar +
  /// yapılmayıp kayanlar. Örneğin 3 planın 2'si yapıldı, 1'i kaydıysa 3.
  int get planSayisi => kalan + kayan;

  /// 0–1 arası tamamlanma oranı; plan yoksa `null`.
  double? get oran => planSayisi == 0 ? null : yapilan / planSayisi;

  bool get bos => planSayisi == 0 && iptal == 0;
}

/// Planları ve kayma kayıtlarını günlere göre özetler.
Map<DateTime, GunOzeti> gunlukOzet(
  List<Plan> planlar,
  List<KaymaKaydi> kaymaKayitlari,
) {
  final yapilan = <DateTime, int>{};
  final kalan = <DateTime, int>{};
  final kayan = <DateTime, int>{};
  final iptal = <DateTime, int>{};

  void artir(Map<DateTime, int> m, DateTime g) => m[g] = (m[g] ?? 0) + 1;

  for (final p in planlar) {
    if (p.durum == PlanDurumu.iptal) {
      artir(iptal, p.gun);
      continue;
    }
    artir(kalan, p.gun);
    if (p.durum == PlanDurumu.yapildi) artir(yapilan, p.gun);
  }
  for (final k in kaymaKayitlari) {
    artir(kayan, k.gun);
  }

  final gunler = {...kalan.keys, ...kayan.keys, ...iptal.keys};
  return {
    for (final g in gunler)
      g: GunOzeti(
        yapilan: yapilan[g] ?? 0,
        kalan: kalan[g] ?? 0,
        kayan: kayan[g] ?? 0,
        iptal: iptal[g] ?? 0,
      ),
  };
}
