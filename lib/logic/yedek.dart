import 'dart:convert';

import '../models/kayma_kaydi.dart';
import '../models/plan.dart';

/// Yedek dosyası okunamazsa ya da bu uygulamaya ait değilse atılır.
class YedekHatasi implements Exception {
  final String mesaj;

  YedekHatasi(this.mesaj);

  @override
  String toString() => mesaj;
}

/// Uygulamanın bütün verisi: planlar, kayma kayıtları ve ayarlar
/// (docs/SPEC.md §8).
///
/// Ayarlar da yedeklenir; "son işlenen gün" dahil. Böylece eski bir yedek
/// yüklenince aradaki günler açılışta sırayla kaydırılır ve takvim tutarlı
/// kalır.
class Yedek {
  static const uygulamaAdi = 'Takvim Takip';

  /// Biçim değişirse artar; daha yeni biçimdeki yedek eski uygulamaya
  /// yüklenmez.
  static const bicimSurumu = 1;

  final DateTime olusturma;
  final List<Plan> planlar;
  final List<KaymaKaydi> kaymaKayitlari;
  final Map<String, String> ayarlar;

  const Yedek({
    required this.olusturma,
    required this.planlar,
    required this.kaymaKayitlari,
    required this.ayarlar,
  });

  /// Okunaklı (girintili) JSON metni.
  String jsonMetni() => const JsonEncoder.withIndent('  ').convert({
    'uygulama': uygulamaAdi,
    'bicim': bicimSurumu,
    'olusturma': olusturma.toIso8601String(),
    'planlar': [for (final p in planlar) p.toMap()],
    'kayma_kayitlari': [for (final k in kaymaKayitlari) k.toMap()],
    'ayarlar': ayarlar,
  });

  /// JSON metnini çözer ve doğrular. Hatalıysa [YedekHatasi] atar; böylece
  /// mevcut veriler silinmeden önce sorun anlaşılır.
  factory Yedek.coz(String metin) {
    final Object? veri;
    try {
      veri = jsonDecode(metin);
    } on FormatException {
      throw YedekHatasi('Dosya okunamadı: geçerli bir yedek dosyası değil.');
    }
    if (veri is! Map<String, dynamic> || veri['uygulama'] != uygulamaAdi) {
      throw YedekHatasi('Bu dosya bir Takvim Takip yedeği değil.');
    }
    final bicim = veri['bicim'];
    if (bicim is! int || bicim > bicimSurumu) {
      throw YedekHatasi(
        'Bu yedek uygulamanın daha yeni bir sürümüyle alınmış. '
        'Önce uygulamayı güncelle.',
      );
    }

    try {
      return Yedek(
        olusturma: DateTime.parse(veri['olusturma'] as String),
        planlar: [
          for (final m in veri['planlar'] as List)
            Plan.fromMap(Map<String, Object?>.from(m as Map)),
        ],
        kaymaKayitlari: [
          for (final m in veri['kayma_kayitlari'] as List)
            KaymaKaydi.fromMap(Map<String, Object?>.from(m as Map)),
        ],
        ayarlar: {
          for (final e in (veri['ayarlar'] as Map).entries)
            e.key as String: e.value as String,
        },
      );
    } catch (_) {
      throw YedekHatasi('Yedek dosyası bozuk: bazı kayıtlar okunamadı.');
    }
  }

  /// Önerilen dosya adı: `takvim_takip_yedek_2026-10-16_1430.json`
  String dosyaAdi() {
    String iki(int n) => n.toString().padLeft(2, '0');
    final t = olusturma;
    return 'takvim_takip_yedek_${t.year}-${iki(t.month)}-${iki(t.day)}_'
        '${iki(t.hour)}${iki(t.minute)}.json';
  }
}
