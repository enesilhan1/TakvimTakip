import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'yz.dart';

/// Bütün sağlayıcıların ortak HTTP gönderimi: JSON POST, yoğunluk ve geçici
/// ağ hatalarında 2 kez daha deneme, hataları Türkçe mesaja çevirme.
class JsonIstegi {
  final http.Client http_;
  final Duration tekrarBeklemesi;

  JsonIstegi({http.Client? httpIstemcisi, Duration? tekrarBeklemesi})
    : http_ = httpIstemcisi ?? http.Client(),
      tekrarBeklemesi = tekrarBeklemesi ?? const Duration(seconds: 2);

  /// [hataCevir] sağlayıcıya özel durumları (bakiye, geçersiz anahtar...)
  /// tanır; tanımadıklarını null döndürür, ortak mesaj kullanılır.
  Future<Map<String, dynamic>> gonder(
    Uri adres, {
    required Map<String, String> basliklar,
    required Map<String, Object?> govde,
    required String saglayiciAdi,
    YzHatasi? Function(int durum, String mesaj)? hataCevir,
  }) async {
    final istek = jsonEncode(govde);

    for (var deneme = 0; ; deneme++) {
      final sonDeneme = deneme == 2;
      Future<void> bekle([Duration? sure]) =>
          Future<void>.delayed(sure ?? tekrarBeklemesi * (deneme + 1));

      final http.Response yanit;
      try {
        yanit = await http_
            .post(
              adres,
              headers: {'content-type': 'application/json', ...basliklar},
              body: istek,
            )
            .timeout(const Duration(minutes: 3));
      } on TimeoutException {
        if (sonDeneme) {
          throw YzHatasi(
            '$saglayiciAdi çok uzun süre yanıt vermedi. '
            'Tekrar dene.',
          );
        }
        await bekle();
        continue;
      } on SocketException {
        if (sonDeneme) {
          throw YzHatasi(
            'İnternet bağlantısı yok ya da sunucuya ulaşılamıyor '
            '($saglayiciAdi).',
          );
        }
        await bekle();
        continue;
      } on http.ClientException {
        if (sonDeneme) {
          throw YzHatasi(
            'Bağlanılamadı ($saglayiciAdi). İnternet bağlantını '
            'kontrol et.',
          );
        }
        await bekle();
        continue;
      }

      final metin = utf8.decode(yanit.bodyBytes);
      if (yanit.statusCode == 200) {
        return jsonDecode(metin) as Map<String, dynamic>;
      }

      final mesaj = _hataMesaji(metin);
      final ozel = hataCevir?.call(yanit.statusCode, mesaj);
      if (ozel != null) throw ozel;

      final tekrarlanabilir =
          yanit.statusCode == 429 ||
          yanit.statusCode == 408 ||
          yanit.statusCode >= 500;
      if (tekrarlanabilir && !sonDeneme) {
        final saniye = int.tryParse(yanit.headers['retry-after'] ?? '');
        await bekle(
          saniye != null && saniye <= 30 ? Duration(seconds: saniye) : null,
        );
        continue;
      }
      throw _ortakHata(yanit.statusCode, mesaj, saglayiciAdi);
    }
  }

  static String _hataMesaji(String govde) {
    try {
      final j = jsonDecode(govde);
      final e = j is List ? j.first['error'] : j['error'];
      if (e is Map) return '${e['message'] ?? ''}';
      if (e is String) return e;
    } catch (_) {}
    return '';
  }

  static YzHatasi _ortakHata(int durum, String mesaj, String ad) {
    switch (durum) {
      case 401:
        return YzHatasi(
          'API anahtarı geçersiz. Ayarlar → Asistan bölümünden '
          'kontrol et.',
        );
      case 403:
        return YzHatasi('Bu API anahtarının bu modeli kullanma izni yok.');
      case 404:
        return YzHatasi(
          'Model bulunamadı. Ayarlardan model adını kontrol et'
          '${mesaj.isEmpty ? '' : ' ($mesaj)'}.',
        );
      case 429:
        return YzHatasi(
          'Çok fazla istek gönderildi ya da kullanım kotan '
          'doldu. Biraz bekleyip tekrar dene.',
        );
      case >= 500:
        return YzHatasi(
          '$ad şu an çok yoğun. Birkaç dakika sonra tekrar dene.',
        );
      default:
        return YzHatasi(
          '$ad isteği reddetti ($durum)'
          '${mesaj.isEmpty ? '' : ': $mesaj'}',
        );
    }
  }
}
