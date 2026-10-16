import '../data/plan_deposu.dart';
import '../utils/tarih.dart';
import 'kaydirma_motoru.dart';

/// Kapanmış ama henüz işlenmemiş günleri bulur ve sırayla kaydırır
/// (docs/SPEC.md §5).
///
/// Uygulama her açılışta ve gece yarısı arka plan görevinde
/// [bekleyenGunleriIsle]'yi çağırır. Telefon kapalı kaldıysa ya da uygulama
/// günlerce açılmadıysa kaçırılan günler eskiden yeniye işlenir; sonuç,
/// kaydırma her gün zamanında çalışmış gibi olur.
class KaydirmaServisi {
  /// Ayarlarda en son kapanışı yapılan günün anahtarı (`2026-10-19`).
  static const sonIslenenGunAyari = 'son_islenen_gun';

  final PlanDeposu depo;

  KaydirmaServisi(this.depo);

  /// [simdi]den önceki, işlenmemiş tüm günleri kapatır ve her gün için
  /// sonucu döndürür (hiçbir şey kaymadıysa sonuç boş olur).
  ///
  /// İlk çalıştırmada geçmiş işlenmez; dünden itibaren takip başlar.
  Future<List<KaydirmaSonucu>> bekleyenGunleriIsle(DateTime simdi) async {
    final dun = gunEkle(gunOf(simdi), -1);
    final kayitli = await depo.ayarOku(sonIslenenGunAyari);

    if (kayitli == null) {
      await depo.ayarYaz(sonIslenenGunAyari, gunAnahtari(dun));
      return const [];
    }

    final sonuclar = <KaydirmaSonucu>[];
    var gun = gunEkle(gunAnahtarindan(kayitli), 1);
    while (!gun.isAfter(dun)) {
      final sonuc = gunuKapat(gun, await depo.gundenItibarenPlanlar(gun));
      // Planlar ve "son işlenen gün" aynı işlemde yazılır: yarıda kesilirse
      // bu gün bir sonraki açılışta baştan işlenir, iki kez işlenmez.
      await depo.kaydirmaKaydet(
        sonuc,
        ayarlar: {sonIslenenGunAyari: gunAnahtari(gun)},
      );
      sonuclar.add(sonuc);
      gun = gunEkle(gun, 1);
    }
    return sonuclar;
  }
}
