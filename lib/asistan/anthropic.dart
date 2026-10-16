import 'package:http/http.dart' as http;

import 'http_istegi.dart';
import 'yz.dart';

/// Anthropic Messages API (POST /v1/messages), ham HTTP ile (Dart için
/// resmi Anthropic SDK'sı yok).
class AnthropicIstemcisi extends GecmisliIstemci {
  static final adres = Uri.parse('https://api.anthropic.com/v1/messages');

  @override
  final String apiAnahtari;
  @override
  final YzModeli model;
  final JsonIstegi _istek;

  AnthropicIstemcisi({
    required this.apiAnahtari,
    required this.model,
    http.Client? httpIstemcisi,
    Duration? tekrarBeklemesi,
  }) : _istek = JsonIstegi(
         httpIstemcisi: httpIstemcisi,
         tekrarBeklemesi: tekrarBeklemesi,
       );

  /// Sunucu taraflı yedek model ("fallbacks": "default"): Claude güvenlik
  /// sınıflandırıcısı yüzünden bir isteği reddederse API uygun bir yedek
  /// modelle otomatik tekrar dener. Opus 5.5 ve Sonnet 5.5'te var, Haiku'da
  /// yok; elle yazılan modellerde bilinmediği için gönderilmez.
  bool get _yedekModel =>
      model.id == 'claude-opus-5-5' || model.id == 'claude-sonnet-5-5';

  @override
  Map<String, Object?> kullaniciMesaji(String baglam, String metin) => {
    'role': 'user',
    'content': [
      {'type': 'text', 'text': baglam},
      {'type': 'text', 'text': metin},
    ],
  };

  Map<String, Object?> govde(String sistem, List<AracTanimi> araclar) => {
    'model': model.id,
    'max_tokens': 16000,
    'system': sistem,
    'tools': [
      for (final a in araclar)
        {'name': a.ad, 'description': a.aciklama, 'input_schema': a.sema},
    ],
    'messages': gecmis,
    // Düşünme uyarlamalı (varsayılan); derinliği efor belirler. Plan
    // düzenleme için orta efor yeterli ve ekonomik.
    'output_config': {'effort': 'medium'},
    // Sohbet uzadıkça önceki kısım önbellekten okunsun.
    'cache_control': {'type': 'ephemeral'},
    if (_yedekModel) 'fallbacks': 'default',
  };

  @override
  Future<YzYaniti> yanitAl({
    required String sistem,
    required List<AracTanimi> araclar,
  }) async {
    final j = await _istek.gonder(
      adres,
      saglayiciAdi: 'Claude',
      basliklar: {
        'x-api-key': apiAnahtari,
        'anthropic-version': '2023-06-01',
        if (_yedekModel) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      govde: govde(sistem, araclar),
      hataCevir: (durum, mesaj) =>
          durum == 400 && mesaj.toLowerCase().contains('credit balance')
          ? YzHatasi(
              'Anthropic hesabının bakiyesi yetersiz. '
              'console.anthropic.com → Billing bölümünden kredi yükle.',
            )
          : null,
    );

    final icerik = (j['content'] as List).cast<Map<String, dynamic>>();
    // Yanıt olduğu gibi geçmişe eklenir (düşünme blokları dahil).
    gecmis.add({'role': 'assistant', 'content': icerik});

    final u = (j['usage'] as Map?)?.cast<String, dynamic>() ?? const {};
    int t(String k) => (u[k] as num?)?.toInt() ?? 0;

    return YzYaniti(
      metinler: [
        for (final b in icerik)
          if (b['type'] == 'text') b['text'] as String,
      ],
      cagrilar: [
        for (final b in icerik)
          if (b['type'] == 'tool_use')
            AracCagrisi(
              id: b['id'] as String,
              ad: b['name'] as String,
              girdi: Map<String, dynamic>.from(b['input'] as Map),
            ),
      ],
      son: switch (j['stop_reason']) {
        'tool_use' => YanitSonu.arac,
        'max_tokens' => YanitSonu.uzunluk,
        'refusal' => YanitSonu.ret,
        _ => YanitSonu.bitti,
      },
      kullanim: Kullanim(
        girdi: t('input_tokens'),
        onbellekOkunan: t('cache_read_input_tokens'),
        onbellekYazilan: t('cache_creation_input_tokens'),
        cikti: t('output_tokens'),
      ),
    );
  }

  @override
  void sonuclariEkle(List<AracSonucu> sonuclar) {
    // Bütün araç sonuçları tek bir kullanıcı mesajında.
    gecmis.add({
      'role': 'user',
      'content': [
        for (final s in sonuclar)
          {
            'type': 'tool_result',
            'tool_use_id': s.cagri.id,
            'content': s.metin,
            if (s.hata) 'is_error': true,
          },
      ],
    });
  }
}
