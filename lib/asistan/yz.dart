/// Asistanın kullanabileceği yapay zekâ sağlayıcıları, modelleri ve
/// sağlayıcıdan bağımsız ortak türler (docs/SPEC.md §9).
library;

/// Yapay zekâ sağlayıcısı. Her birinin kendi API'si ve API anahtarı var.
enum Saglayici {
  anthropic(
    ad: 'Claude (Anthropic)',
    kisaAd: 'Claude',
    anahtarSayfasi: 'console.anthropic.com → API Keys',
    anahtarOneki: 'sk-ant-',
  ),
  openai(
    ad: 'ChatGPT (OpenAI)',
    kisaAd: 'ChatGPT',
    anahtarSayfasi: 'platform.openai.com → API keys',
    anahtarOneki: 'sk-',
  ),
  gemini(
    ad: 'Gemini (Google)',
    kisaAd: 'Gemini',
    anahtarSayfasi: 'aistudio.google.com → Get API key',
    anahtarOneki: null,
  ),
  deepseek(
    ad: 'DeepSeek',
    kisaAd: 'DeepSeek',
    anahtarSayfasi: 'platform.deepseek.com → API keys',
    anahtarOneki: 'sk-',
  );

  final String ad;
  final String kisaAd;

  /// API anahtarının nereden alınacağı.
  final String anahtarSayfasi;

  /// Anahtarın başlaması beklenen ön ek (doğrulama için; yoksa null).
  final String? anahtarOneki;

  const Saglayici({
    required this.ad,
    required this.kisaAd,
    required this.anahtarSayfasi,
    required this.anahtarOneki,
  });

  static Saglayici adindan(String? ad) =>
      values.where((s) => s.name == ad).firstOrNull ?? anthropic;

  /// Hazır model listesi; ilki varsayılan.
  List<YzModeli> get modeller => switch (this) {
    anthropic => const [
      YzModeli(
        saglayici: anthropic,
        id: 'claude-opus-5-5',
        ad: 'Claude Opus 5.5',
        aciklama: 'En akıllısı (önerilen)',
        girdi: 4,
        onbellekOkuma: 0.20,
        onbellekYazma: 5,
        cikti: 20,
      ),
      YzModeli(
        saglayici: anthropic,
        id: 'claude-sonnet-5-5',
        ad: 'Claude Sonnet 5.5',
        aciklama: 'Hızlı ve yaklaşık yarı fiyatına',
        girdi: 2,
        onbellekOkuma: 0.20,
        onbellekYazma: 2.5,
        cikti: 10,
      ),
      YzModeli(
        saglayici: anthropic,
        id: 'claude-haiku-5-5',
        ad: 'Claude Haiku 5.5',
        aciklama: 'En hızlı ve en ucuzu',
        girdi: 0.10,
        onbellekOkuma: 0.01,
        onbellekYazma: 0.125,
        cikti: 0.50,
      ),
    ],
    openai => const [
      YzModeli(
        saglayici: openai,
        id: 'gpt-6.1-sol',
        ad: 'GPT-6.1 Sol',
        aciklama: 'Dengeli (önerilen)',
        girdi: 2,
        onbellekOkuma: 0.10,
        cikti: 10,
      ),
      YzModeli(
        saglayici: openai,
        id: 'gpt-6-astra',
        ad: 'GPT-6 Astra',
        aciklama: 'En güçlüsü, pahalı',
        girdi: 10,
        onbellekOkuma: 1,
        cikti: 50,
      ),
      YzModeli(
        saglayici: openai,
        id: 'gpt-6-luna',
        ad: 'GPT-6 Luna',
        aciklama: 'En ucuzu',
        girdi: 0.10,
        onbellekOkuma: 0.01,
        cikti: 0.50,
      ),
    ],
    gemini => const [
      YzModeli(
        saglayici: gemini,
        id: 'gemini-3.8-flash',
        ad: 'Gemini 3.8 Flash',
        aciklama: 'Hızlı, ücretsiz kotası var (önerilen)',
        girdi: 0.75,
        cikti: 3.75,
      ),
      YzModeli(
        saglayici: gemini,
        id: 'gemini-4-argon',
        ad: 'Gemini 4 Argon',
        aciklama: 'En güçlüsü, ücretsiz kotası yok',
        girdi: 2,
        cikti: 10,
      ),
      YzModeli(
        saglayici: gemini,
        id: 'gemini-3.5-flash-lite',
        ad: 'Gemini 3.5 Flash-Lite',
        aciklama: 'En ucuzu, ücretsiz kotası var',
        girdi: 0.30,
        cikti: 2.50,
      ),
    ],
    deepseek => const [
      YzModeli(
        saglayici: deepseek,
        id: 'deepseek-flash',
        ad: 'DeepSeek Flash',
        aciklama: 'Çok ucuz (önerilen)',
        // Yoğun saat fiyatı (gece yarısı fiyatın yarısı); tahmin üst sınır.
        girdi: 0.30,
        onbellekOkuma: 0.006,
        cikti: 1.20,
      ),
      YzModeli(
        saglayici: deepseek,
        id: 'deepseek-v4-pro',
        ad: 'DeepSeek V4 Pro',
        aciklama: 'Daha güçlü, yine ucuz',
        girdi: 1.32,
        onbellekOkuma: 0.044,
        cikti: 3.96,
      ),
    ],
  };

  YzModeli get varsayilanModel => modeller.first;

  /// Kayıtlı model kimliğine göre model; listede yoksa elle yazılmış model.
  YzModeli model(String? id) {
    if (id == null || id.trim().isEmpty) return varsayilanModel;
    return modeller.where((m) => m.id == id).firstOrNull ??
        YzModeli.elle(this, id.trim());
  }
}

/// Bir model ve milyon token başına fiyatları (ABD doları, Ekim 2026).
class YzModeli {
  final Saglayici saglayici;
  final String id;
  final String ad;
  final String aciklama;

  /// Fiyatlar; elle yazılan modellerde bilinmez (null).
  final double? girdi;
  final double? onbellekOkuma;
  final double? onbellekYazma;
  final double? cikti;

  const YzModeli({
    required this.saglayici,
    required this.id,
    required this.ad,
    required this.aciklama,
    this.girdi,
    this.onbellekOkuma,
    this.onbellekYazma,
    this.cikti,
  });

  /// Kullanıcının elle yazdığı, listede olmayan model.
  YzModeli.elle(this.saglayici, this.id)
    : ad = id,
      aciklama = 'Elle yazılan model',
      girdi = null,
      onbellekOkuma = null,
      onbellekYazma = null,
      cikti = null;

  bool get elleYazildi => girdi == null;

  /// Yaklaşık maliyet (dolar); fiyat bilinmiyorsa null.
  double? maliyet(Kullanim k) {
    final g = girdi, c = cikti;
    if (g == null || c == null) return null;
    return (k.girdi * g +
            k.onbellekOkunan * (onbellekOkuma ?? g) +
            k.onbellekYazilan * (onbellekYazma ?? g) +
            k.cikti * c) /
        1e6;
  }

  @override
  bool operator ==(Object other) =>
      other is YzModeli && other.saglayici == saglayici && other.id == id;

  @override
  int get hashCode => Object.hash(saglayici, id);
}

/// Bir yanıtın token kullanımı (sağlayıcıdan bağımsız).
class Kullanim {
  /// Önbellekten okunmayan girdi.
  final int girdi;
  final int onbellekOkunan;
  final int onbellekYazilan;

  /// Düşünme dahil çıktı.
  final int cikti;

  const Kullanim({
    this.girdi = 0,
    this.onbellekOkunan = 0,
    this.onbellekYazilan = 0,
    this.cikti = 0,
  });
}

/// Asistana tanıtılan bir araç (JSON Schema ile).
class AracTanimi {
  final String ad;
  final String aciklama;
  final Map<String, Object?> sema;

  const AracTanimi({
    required this.ad,
    required this.aciklama,
    required this.sema,
  });
}

/// Modelin bir aracı çağırması.
class AracCagrisi {
  final String id;
  final String ad;
  final Map<String, dynamic> girdi;

  const AracCagrisi({required this.id, required this.ad, required this.girdi});
}

/// Bir araç çağrısının sonucu.
class AracSonucu {
  final AracCagrisi cagri;
  final String metin;
  final bool hata;

  const AracSonucu(this.cagri, this.metin, {this.hata = false});
}

enum YanitSonu {
  /// Model sözünü bitirdi.
  bitti,

  /// Model araç çağırdı; sonuçlar gönderilip devam edilmeli.
  arac,

  /// Çıktı sınırına takıldı.
  uzunluk,

  /// Model ya da güvenlik filtresi isteği reddetti.
  ret,
}

class YzYaniti {
  final List<String> metinler;
  final List<AracCagrisi> cagrilar;
  final YanitSonu son;
  final Kullanim kullanim;

  const YzYaniti({
    this.metinler = const [],
    this.cagrilar = const [],
    required this.son,
    this.kullanim = const Kullanim(),
  });
}

/// Sağlayıcıya ulaşılamadığında kullanıcıya gösterilecek Türkçe hata.
class YzHatasi implements Exception {
  final String mesaj;

  YzHatasi(this.mesaj);

  @override
  String toString() => mesaj;
}

/// Bir sağlayıcının sohbet istemcisi.
///
/// Konuşma geçmişini sağlayıcının kendi biçiminde tutar ve API'ye hiç
/// değiştirmeden, yalnızca sonuna ekleyerek gönderir (düşünme blokları,
/// imzalar ve benzeri dahil; bazı sağlayıcılar bunu zorunlu tutuyor).
abstract class YzIstemcisi {
  YzModeli get model;
  String get apiAnahtari;

  /// Kullanıcının yeni mesajı: önce güncel bağlam, sonra mesajın kendisi.
  void kullaniciEkle(String baglam, String metin);

  /// Geçmişi gönderip modelin yanıtını alır ve geçmişe ekler.
  Future<YzYaniti> yanitAl({
    required String sistem,
    required List<AracTanimi> araclar,
  });

  /// Araç sonuçlarını (hepsi birlikte) geçmişe ekler.
  void sonuclariEkle(List<AracSonucu> sonuclar);

  /// Hata olunca geçmişi son kullanıcı mesajından önceki haline döndürür.
  void geriAl();

  /// Yeni sohbet.
  void temizle();
}

/// Geçmişi bir liste olarak tutan istemcilerin ortak kısmı.
abstract class GecmisliIstemci implements YzIstemcisi {
  final List<Map<String, Object?>> gecmis = [];
  int _kontrolNoktasi = 0;

  /// Sağlayıcının kullanıcı mesajı biçimi.
  Map<String, Object?> kullaniciMesaji(String baglam, String metin);

  @override
  void kullaniciEkle(String baglam, String metin) {
    _kontrolNoktasi = gecmis.length;
    gecmis.add(kullaniciMesaji(baglam, metin));
  }

  @override
  void geriAl() => gecmis.removeRange(_kontrolNoktasi, gecmis.length);

  @override
  void temizle() {
    gecmis.clear();
    _kontrolNoktasi = 0;
  }
}
