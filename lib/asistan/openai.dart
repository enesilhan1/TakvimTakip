import 'package:http/http.dart' as http;

import 'http_istegi.dart';
import 'yz.dart';

/// OpenAI Responses API (POST /v1/responses). Güncel GPT modelleri araç
/// kullanmak için Chat Completions değil bu API'yi istiyor.
///
/// Sunucuda saklama kapalı (`store: false`); geçmiş her istekte yeniden
/// gönderilir. Modelin çıktı öğeleri (şifreli düşünme öğeleri dahil)
/// değiştirilmeden geçmişe eklenir.
class OpenAiIstemcisi extends GecmisliIstemci {
  static final adres = Uri.parse('https://api.openai.com/v1/responses');

  @override
  final String apiAnahtari;
  @override
  final YzModeli model;
  final JsonIstegi _istek;

  OpenAiIstemcisi({
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
    'content': [
      {'type': 'input_text', 'text': baglam},
      {'type': 'input_text', 'text': metin},
    ],
  };

  Map<String, Object?> govde(String sistem, List<AracTanimi> araclar) => {
    'model': model.id,
    'instructions': sistem,
    'input': gecmis,
    'tools': [
      for (final a in araclar)
        {
          'type': 'function',
          'name': a.ad,
          'description': a.aciklama,
          'parameters': a.sema,
        },
    ],
    'reasoning': {'effort': 'medium'},
    'max_output_tokens': 16000,
    'store': false,
    // Saklama kapalıyken düşünme öğeleri şifreli olarak geri gelsin ki
    // sonraki istekte aynen gönderilebilsin.
    'include': ['reasoning.encrypted_content'],
  };

  @override
  Future<YzYaniti> yanitAl({
    required String sistem,
    required List<AracTanimi> araclar,
  }) async {
    final j = await _istek.gonder(
      adres,
      saglayiciAdi: 'ChatGPT',
      basliklar: {'authorization': 'Bearer $apiAnahtari'},
      govde: govde(sistem, araclar),
      hataCevir: (durum, mesaj) =>
          durum == 429 && mesaj.toLowerCase().contains('quota')
          ? YzHatasi(
              'OpenAI hesabında kullanılabilir kredi yok. '
              'platform.openai.com → Billing bölümünden kredi yükle.',
            )
          : null,
    );

    final cikti = ((j['output'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    gecmis.addAll(cikti);

    final metinler = <String>[];
    final cagrilar = <AracCagrisi>[];
    var ret = false;
    for (final o in cikti) {
      switch (o['type']) {
        case 'message':
          for (final p in (o['content'] as List? ?? const [])) {
            if (p['type'] == 'output_text') metinler.add(p['text'] as String);
            if (p['type'] == 'refusal') ret = true;
          }
        case 'function_call':
          cagrilar.add(
            AracCagrisi(
              id: o['call_id'] as String,
              ad: o['name'] as String,
              girdi: argumanlariCoz(o['arguments']),
            ),
          );
      }
    }

    final neden = (j['incomplete_details'] as Map?)?['reason'];
    final u = (j['usage'] as Map?)?.cast<String, dynamic>() ?? const {};
    final girdi = (u['input_tokens'] as num?)?.toInt() ?? 0;
    final onbellek =
        ((u['input_tokens_details'] as Map?)?['cached_tokens'] as num?)
            ?.toInt() ??
        0;

    return YzYaniti(
      metinler: metinler,
      cagrilar: cagrilar,
      son: ret || neden == 'content_filter'
          ? YanitSonu.ret
          : neden == 'max_output_tokens'
          ? YanitSonu.uzunluk
          : cagrilar.isNotEmpty
          ? YanitSonu.arac
          : YanitSonu.bitti,
      kullanim: Kullanim(
        girdi: girdi - onbellek,
        onbellekOkunan: onbellek,
        cikti: (u['output_tokens'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  void sonuclariEkle(List<AracSonucu> sonuclar) {
    for (final s in sonuclar) {
      gecmis.add({
        'type': 'function_call_output',
        'call_id': s.cagri.id,
        // Responses API'de ayrı bir hata işareti yok; metinle belirtilir.
        'output': s.hata ? 'HATA: ${s.metin}' : s.metin,
      });
    }
  }
}
