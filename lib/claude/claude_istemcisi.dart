import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Ayarlardan seçilebilen Claude modelleri. Fiyatlar milyon token başına
/// ABD doları (Ekim 2026).
class ClaudeModeli {
  final String id;
  final String ad;
  final String aciklama;
  final double girdiFiyati;
  final double ciktiFiyati;

  /// Sunucu taraflı yedek model ("fallbacks": "default") destekliyor mu?
  final bool yedekModelDestekli;

  const ClaudeModeli({
    required this.id,
    required this.ad,
    required this.aciklama,
    required this.girdiFiyati,
    required this.ciktiFiyati,
    required this.yedekModelDestekli,
  });

  static const opus = ClaudeModeli(
    id: 'claude-opus-5-5',
    ad: 'Claude Opus 5.5',
    aciklama: 'En akıllısı (önerilen)',
    girdiFiyati: 4,
    ciktiFiyati: 20,
    yedekModelDestekli: true,
  );
  static const sonnet = ClaudeModeli(
    id: 'claude-sonnet-5-5',
    ad: 'Claude Sonnet 5.5',
    aciklama: 'Hızlı ve yaklaşık yarı fiyatına',
    girdiFiyati: 2,
    ciktiFiyati: 10,
    yedekModelDestekli: true,
  );
  static const haiku = ClaudeModeli(
    id: 'claude-haiku-5-5',
    ad: 'Claude Haiku 5.5',
    aciklama: 'En hızlı ve en ucuzu',
    girdiFiyati: 0.10,
    ciktiFiyati: 0.50,
    yedekModelDestekli: false,
  );

  static const hepsi = [opus, sonnet, haiku];

  static ClaudeModeli idden(String? id) =>
      hepsi.where((m) => m.id == id).firstOrNull ?? opus;

  /// Bir yanıtın yaklaşık maliyeti (dolar).
  double maliyet(Map<String, dynamic>? kullanim) {
    if (kullanim == null) return 0;
    int t(String k) => (kullanim[k] as num?)?.toInt() ?? 0;
    final girdi =
        t('input_tokens') +
        t('cache_creation_input_tokens') * 1.25 +
        t('cache_read_input_tokens') * 0.1;
    return (girdi * girdiFiyati + t('output_tokens') * ciktiFiyati) / 1e6;
  }
}

/// Claude'a ulaşılamadığında kullanıcıya gösterilecek Türkçe hata.
class ClaudeHatasi implements Exception {
  final String mesaj;

  ClaudeHatasi(this.mesaj);

  @override
  String toString() => mesaj;
}

/// Anthropic Messages API'ye (POST /v1/messages) doğrudan HTTP istemcisi.
///
/// Dart için resmi Anthropic SDK'sı olmadığı için istek ham HTTP ile atılır.
/// Kullanıcı kendi API anahtarını ayarlara girer; anahtar yalnızca bu
/// isteklerde, doğrudan api.anthropic.com'a gönderilir.
class ClaudeIstemcisi {
  static final adres = Uri.parse('https://api.anthropic.com/v1/messages');

  final http.Client _http;
  final String apiAnahtari;
  final ClaudeModeli model;

  /// Testlerde beklemesiz tekrar denemek için.
  final Duration tekrarBeklemesi;

  ClaudeIstemcisi({
    required this.apiAnahtari,
    this.model = ClaudeModeli.opus,
    http.Client? httpIstemcisi,
    this.tekrarBeklemesi = const Duration(seconds: 2),
  }) : _http = httpIstemcisi ?? http.Client();

  /// İstek gövdesi. Sohbet geçmişi ([mesajlar]) olduğu gibi gönderilir.
  Map<String, Object?> govde({
    required String sistem,
    required List<Map<String, Object?>> araclar,
    required List<Map<String, Object?>> mesajlar,
  }) => {
    'model': model.id,
    'max_tokens': 16000,
    'system': sistem,
    'tools': araclar,
    'messages': mesajlar,
    // Düşünme her üç modelde de uyarlamalı (varsayılan); derinliği efor
    // belirler. Plan düzenleme için orta efor yeterli ve ekonomik.
    'output_config': {'effort': 'medium'},
    // Sohbet uzadıkça önceki kısım önbellekten okunsun (girdinin ~%10'u).
    'cache_control': {'type': 'ephemeral'},
    // Claude güvenlik sınıflandırıcısı yüzünden bir isteği reddederse API
    // isteği otomatik olarak uygun bir yedek modelle tekrar dener.
    if (model.yedekModelDestekli) 'fallbacks': 'default',
  };

  Map<String, String> get basliklar => {
    'content-type': 'application/json',
    'x-api-key': apiAnahtari,
    'anthropic-version': '2023-06-01',
    if (model.yedekModelDestekli)
      'anthropic-beta': 'server-side-fallback-2026-07-01',
  };

  /// Bir mesaj isteği gönderir ve yanıtı (JSON) döndürür. Yoğunluk ve geçici
  /// ağ hatalarında 2 kez daha dener.
  Future<Map<String, dynamic>> mesajGonder({
    required String sistem,
    required List<Map<String, Object?>> araclar,
    required List<Map<String, Object?>> mesajlar,
  }) async {
    final istek = jsonEncode(
      govde(sistem: sistem, araclar: araclar, mesajlar: mesajlar),
    );

    for (var deneme = 0; ; deneme++) {
      final sonDeneme = deneme == 2;
      final http.Response yanit;
      try {
        yanit = await _http
            .post(adres, headers: basliklar, body: istek)
            .timeout(const Duration(minutes: 3));
      } on TimeoutException {
        if (sonDeneme) {
          throw ClaudeHatasi(
            'Claude çok uzun süre yanıt vermedi. '
            'Tekrar dene.',
          );
        }
        await Future<void>.delayed(tekrarBeklemesi * (deneme + 1));
        continue;
      } on SocketException {
        if (sonDeneme) {
          throw ClaudeHatasi(
            'İnternet bağlantısı yok ya da Claude\'a '
            'ulaşılamıyor.',
          );
        }
        await Future<void>.delayed(tekrarBeklemesi * (deneme + 1));
        continue;
      } on http.ClientException {
        if (sonDeneme) {
          throw ClaudeHatasi(
            'Claude\'a bağlanılamadı. İnternet bağlantını '
            'kontrol et.',
          );
        }
        await Future<void>.delayed(tekrarBeklemesi * (deneme + 1));
        continue;
      }

      if (yanit.statusCode == 200) {
        return jsonDecode(utf8.decode(yanit.bodyBytes)) as Map<String, dynamic>;
      }

      final tekrarlanabilir =
          yanit.statusCode == 429 ||
          yanit.statusCode == 408 ||
          yanit.statusCode >= 500;
      if (tekrarlanabilir && !sonDeneme) {
        final saniye = int.tryParse(yanit.headers['retry-after'] ?? '');
        await Future<void>.delayed(
          saniye != null && saniye <= 30
              ? Duration(seconds: saniye)
              : tekrarBeklemesi * (deneme + 1),
        );
        continue;
      }
      throw _hata(yanit);
    }
  }

  ClaudeHatasi _hata(http.Response yanit) {
    String mesaj = '';
    try {
      final j = jsonDecode(utf8.decode(yanit.bodyBytes));
      mesaj = (j['error']?['message'] as String?) ?? '';
    } catch (_) {}
    final kucuk = mesaj.toLowerCase();

    switch (yanit.statusCode) {
      case 401:
        return ClaudeHatasi(
          'API anahtarı geçersiz. Ayarlar → Claude '
          'bölümünden kontrol et.',
        );
      case 403:
        return ClaudeHatasi('Bu API anahtarının bu modeli kullanma izni yok.');
      case 429:
        return ClaudeHatasi(
          'Çok fazla istek gönderildi. Biraz bekleyip '
          'tekrar dene.',
        );
      case 400 when kucuk.contains('credit balance'):
        return ClaudeHatasi(
          'Anthropic hesabının bakiyesi yetersiz. '
          'console.anthropic.com → Billing bölümünden kredi yükle.',
        );
      case >= 500:
        return ClaudeHatasi(
          'Claude şu an çok yoğun. Birkaç dakika sonra '
          'tekrar dene.',
        );
      default:
        return ClaudeHatasi(
          'Claude isteği reddetti (${yanit.statusCode})'
          '${mesaj.isEmpty ? '' : ': $mesaj'}',
        );
    }
  }
}
