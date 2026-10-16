import 'package:http/http.dart' as http;

import 'http_istegi.dart';
import 'yz.dart';

/// Google Gemini API (POST /v1beta/models/{model}:generateContent).
///
/// Gemini 3 ve sonrası düşünme imzalarını (thoughtSignature) modelin
/// ürettiği parçalarda taşır; bu parçalar sonraki istekte aynen geri
/// gönderilmelidir. Bu yüzden modelin içeriği geçmişe hiç değiştirilmeden
/// eklenir.
class GeminiIstemcisi extends GecmisliIstemci {
  @override
  final String apiAnahtari;
  @override
  final YzModeli model;
  final JsonIstegi _istek;

  GeminiIstemcisi({
    required this.apiAnahtari,
    required this.model,
    http.Client? httpIstemcisi,
    Duration? tekrarBeklemesi,
  }) : _istek = JsonIstegi(
         httpIstemcisi: httpIstemcisi,
         tekrarBeklemesi: tekrarBeklemesi,
       );

  Uri get adres => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/'
    '${Uri.encodeComponent(model.id)}:generateContent',
  );

  @override
  Map<String, Object?> kullaniciMesaji(String baglam, String metin) => {
    'role': 'user',
    'parts': [
      {'text': baglam},
      {'text': metin},
    ],
  };

  Map<String, Object?> govde(String sistem, List<AracTanimi> araclar) => {
    'systemInstruction': {
      'parts': [
        {'text': sistem},
      ],
    },
    'contents': gecmis,
    'tools': [
      {
        'functionDeclarations': [
          for (final a in araclar)
            {
              'name': a.ad,
              'description': a.aciklama,
              'parameters': geminiSemasi(a.sema),
            },
        ],
      },
    ],
    'generationConfig': {'maxOutputTokens': 16000},
  };

  @override
  Future<YzYaniti> yanitAl({
    required String sistem,
    required List<AracTanimi> araclar,
  }) async {
    final j = await _istek.gonder(
      adres,
      saglayiciAdi: 'Gemini',
      basliklar: {'x-goog-api-key': apiAnahtari},
      govde: govde(sistem, araclar),
      hataCevir: (durum, mesaj) {
        final k = mesaj.toLowerCase();
        if (durum == 400 && k.contains('api key')) {
          return YzHatasi(
            'API anahtarı geçersiz. Ayarlar → Asistan '
            'bölümünden kontrol et.',
          );
        }
        if (durum == 429 && (k.contains('quota') || k.contains('exhausted'))) {
          return YzHatasi(
            'Gemini kullanım kotan doldu (ücretsiz kotada '
            'dakikalık ve günlük sınır var). Biraz sonra tekrar dene ya da '
            'aistudio.google.com\'dan faturalandırmayı aç.',
          );
        }
        return null;
      },
    );

    final u = (j['usageMetadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    int t(String k) => (u[k] as num?)?.toInt() ?? 0;
    final onbellek = t('cachedContentTokenCount');
    final kullanim = Kullanim(
      girdi: t('promptTokenCount') - onbellek,
      onbellekOkunan: onbellek,
      cikti: t('candidatesTokenCount') + t('thoughtsTokenCount'),
    );

    final aday = ((j['candidates'] as List?) ?? const []).firstOrNull as Map?;
    if (aday == null) {
      // İstek güvenlik filtresine takıldı (promptFeedback.blockReason).
      return YzYaniti(son: YanitSonu.ret, kullanim: kullanim);
    }
    final icerik = Map<String, Object?>.from(
      (aday['content'] as Map?) ?? {'role': 'model', 'parts': <Object>[]},
    );
    icerik['role'] ??= 'model';
    icerik['parts'] ??= <Object>[];
    gecmis.add(icerik);

    final parcalar = (icerik['parts'] as List).cast<Map>();
    final metinler = [
      for (final p in parcalar)
        if (p['text'] is String && p['thought'] != true) p['text'] as String,
    ];
    final cagrilar = <AracCagrisi>[];
    for (var i = 0; i < parcalar.length; i++) {
      final c = parcalar[i]['functionCall'];
      if (c is! Map) continue;
      cagrilar.add(
        AracCagrisi(
          // Eski modeller kimlik vermiyor; ad ve sırayla eşleştirilir.
          id: (c['id'] as String?) ?? '${c['name']}#$i',
          ad: c['name'] as String,
          girdi: argumanlariCoz(c['args'] ?? const {}),
        ),
      );
    }

    final neden = aday['finishReason'];
    return YzYaniti(
      metinler: metinler,
      cagrilar: cagrilar,
      son: switch (neden) {
        'MAX_TOKENS' => YanitSonu.uzunluk,
        'SAFETY' ||
        'PROHIBITED_CONTENT' ||
        'BLOCKLIST' ||
        'SPII' ||
        'RECITATION' => YanitSonu.ret,
        _ => cagrilar.isNotEmpty ? YanitSonu.arac : YanitSonu.bitti,
      },
      kullanim: kullanim,
    );
  }

  @override
  void sonuclariEkle(List<AracSonucu> sonuclar) {
    // Bütün sonuçlar tek bir kullanıcı içeriğinde, çağrı sırasıyla.
    gecmis.add({
      'role': 'user',
      'parts': [
        for (final s in sonuclar)
          {
            'functionResponse': {
              'name': s.cagri.ad,
              if (!s.cagri.id.contains('#')) 'id': s.cagri.id,
              'response': s.hata ? {'hata': s.metin} : {'sonuc': s.metin},
            },
          },
      ],
    });
  }
}

/// JSON Schema'yı Gemini'nin şema biçimine çevirir: tür adları büyük harf
/// (OBJECT, STRING...). Diğer alanlar (properties, items, enum, required,
/// description) aynen kalır.
Map<String, Object?> geminiSemasi(Map<String, Object?> sema) {
  Object? donustur(Object? d) {
    if (d is Map) {
      return {
        for (final e in d.entries)
          e.key as String: e.key == 'type' && e.value is String
              ? (e.value as String).toUpperCase()
              : e.key == 'properties' && e.value is Map
              ? {
                  for (final p in (e.value as Map).entries)
                    p.key as String: donustur(p.value),
                }
              : donustur(e.value),
      };
    }
    if (d is List) return d.map(donustur).toList();
    return d;
  }

  return donustur(sema) as Map<String, Object?>;
}
