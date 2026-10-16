import 'package:http/http.dart' as http;

import 'http_istegi.dart';
import 'yz.dart';

/// DeepSeek API (OpenAI biçimli POST /chat/completions).
///
/// Düşünme modu varsayılan olarak açık. Araç kullanılan konuşmalarda
/// DeepSeek, asistan mesajlarındaki `reasoning_content`'in sonraki her
/// istekte aynen geri gönderilmesini şart koşuyor (yoksa 400); bu yüzden
/// yanıt mesajı geçmişe hiç değiştirilmeden eklenir.
class DeepSeekIstemcisi extends GecmisliIstemci {
  static final adres = Uri.parse('https://api.deepseek.com/chat/completions');

  @override
  final String apiAnahtari;
  @override
  final YzModeli model;
  final JsonIstegi _istek;

  DeepSeekIstemcisi({
    required this.apiAnahtari,
    required this.model,
    http.Client? httpIstemcisi,
    Duration? tekrarBeklemesi,
  }) : _istek = JsonIstegi(
         httpIstemcisi: httpIstemcisi,
         tekrarBeklemesi: tekrarBeklemesi,
       );

  @override
  Map<String, Object?> kullaniciMesaji(String baglam, String metin) => {
    'role': 'user',
    'content': '$baglam\n\n$metin',
  };

  Map<String, Object?> govde(String sistem, List<AracTanimi> araclar) => {
    'model': model.id,
    'messages': [
      {'role': 'system', 'content': sistem},
      ...gecmis,
    ],
    'tools': [
      for (final a in araclar)
        {
          'type': 'function',
          'function': {
            'name': a.ad,
            'description': a.aciklama,
            'parameters': a.sema,
          },
        },
    ],
    'max_tokens': 16000,
    'stream': false,
  };

  @override
  Future<YzYaniti> yanitAl({
    required String sistem,
    required List<AracTanimi> araclar,
  }) async {
    final j = await _istek.gonder(
      adres,
      saglayiciAdi: 'DeepSeek',
      basliklar: {'authorization': 'Bearer $apiAnahtari'},
      govde: govde(sistem, araclar),
      hataCevir: (durum, mesaj) => durum == 402
          ? YzHatasi(
              'DeepSeek hesabının bakiyesi yetersiz. '
              'platform.deepseek.com → Top up bölümünden yükle.',
            )
          : null,
    );

    final secim = ((j['choices'] as List?) ?? const []).firstOrNull as Map?;
    if (secim == null) return const YzYaniti(son: YanitSonu.ret);
    final mesaj = Map<String, Object?>.from(secim['message'] as Map);
    gecmis.add(mesaj);

    final cagrilar = [
      for (final c in (mesaj['tool_calls'] as List? ?? const []))
        AracCagrisi(
          id: c['id'] as String,
          ad: c['function']['name'] as String,
          girdi: argumanlariCoz(c['function']['arguments']),
        ),
    ];
    final metin = mesaj['content'] as String?;

    final u = (j['usage'] as Map?)?.cast<String, dynamic>() ?? const {};
    int t(String k) => (u[k] as num?)?.toInt() ?? 0;

    return YzYaniti(
      metinler: [if (metin != null && metin.isNotEmpty) metin],
      cagrilar: cagrilar,
      son: switch (secim['finish_reason']) {
        'tool_calls' => YanitSonu.arac,
        'length' => YanitSonu.uzunluk,
        'content_filter' => YanitSonu.ret,
        _ => cagrilar.isNotEmpty ? YanitSonu.arac : YanitSonu.bitti,
      },
      kullanim: Kullanim(
        girdi: t('prompt_cache_miss_tokens'),
        onbellekOkunan: t('prompt_cache_hit_tokens'),
        cikti: t('completion_tokens'),
      ),
    );
  }

  @override
  void sonuclariEkle(List<AracSonucu> sonuclar) {
    for (final s in sonuclar) {
      gecmis.add({
        'role': 'tool',
        'tool_call_id': s.cagri.id,
        'content': s.hata ? 'HATA: ${s.metin}' : s.metin,
      });
    }
  }
}
