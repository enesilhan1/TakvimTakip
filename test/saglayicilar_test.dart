import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/asistan/asistan_sohbeti.dart';
import 'package:takvim_takip/asistan/deepseek.dart';
import 'package:takvim_takip/asistan/gemini.dart';
import 'package:takvim_takip/asistan/istemciler.dart';
import 'package:takvim_takip/asistan/openai.dart';
import 'package:takvim_takip/asistan/yz.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/models/plan.dart';

/// Sırayla verilen yanıtları döndüren sahte sunucu; istekleri kaydeder.
class Sahte {
  final List<http.Response> yanitlar;
  final List<http.Request> istekler = [];

  Sahte(this.yanitlar);

  late final client = MockClient((r) async {
    istekler.add(r);
    return yanitlar[istekler.length - 1];
  });

  Map<String, dynamic> govde(int i) =>
      jsonDecode(istekler[i].body) as Map<String, dynamic>;
}

http.Response json(Object o, [int durum = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(o)),
  durum,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const listeleArgs = {'baslangic': '2026-11-01', 'bitis': '2026-11-30'};

AracSonucu sonuc(YzYaniti y) => AracSonucu(y.cagrilar.single, 'Plan yok.');

void main() {
  group('OpenAI (Responses API)', () {
    final model = Saglayici.openai.varsayilanModel;
    final dusunme = {
      'type': 'reasoning',
      'id': 'rs_1',
      'encrypted_content': 'gizli',
      'summary': <Object>[],
    };

    OpenAiIstemcisi istemci(Sahte s) => OpenAiIstemcisi(
      apiAnahtari: 'sk-openai-test-anahtari',
      model: model,
      httpIstemcisi: s.client,
      tekrarBeklemesi: Duration.zero,
    );

    test('istek biçimi, araç çağrısı ve sonucun geri gönderilmesi', () async {
      final s = Sahte([
        json({
          'status': 'completed',
          'output': [
            dusunme,
            {
              'type': 'function_call',
              'id': 'fc_1',
              'call_id': 'call_1',
              'name': 'planlari_listele',
              'arguments': jsonEncode(listeleArgs),
            },
          ],
          'usage': {
            'input_tokens': 1000,
            'input_tokens_details': {'cached_tokens': 400},
            'output_tokens': 50,
          },
        }),
        json({
          'status': 'completed',
          'output': [
            {
              'type': 'message',
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': 'Kasımda plan yok.'},
              ],
            },
          ],
          'usage': {'input_tokens': 10, 'output_tokens': 5},
        }),
      ]);
      final i = istemci(s)..kullaniciEkle('<baglam/>', 'Kasımda ne var?');

      final y1 = await i.yanitAl(sistem: 'SİSTEM', araclar: araclar);
      expect(y1.son, YanitSonu.arac);
      expect(y1.cagrilar.single.ad, 'planlari_listele');
      expect(y1.cagrilar.single.girdi, listeleArgs);
      expect(y1.kullanim.girdi, 600);
      expect(y1.kullanim.onbellekOkunan, 400);

      final r = s.istekler[0];
      expect(r.url.toString(), 'https://api.openai.com/v1/responses');
      expect(r.headers['authorization'], 'Bearer sk-openai-test-anahtari');
      final g = s.govde(0);
      expect(g['model'], 'gpt-6.1-sol');
      expect(g['instructions'], 'SİSTEM');
      expect(g['store'], false);
      expect(g['include'], ['reasoning.encrypted_content']);
      expect(g['reasoning'], {'effort': 'medium'});
      expect(g['tools'][0], {
        'type': 'function',
        'name': 'planlari_listele',
        'description': araclar[0].aciklama,
        'parameters': araclar[0].sema,
      });
      expect(g['input'][0]['content'][1], {
        'type': 'input_text',
        'text': 'Kasımda ne var?',
      });

      i.sonuclariEkle([sonuc(y1)]);
      final y2 = await i.yanitAl(sistem: 'SİSTEM', araclar: araclar);
      expect(y2.son, YanitSonu.bitti);
      expect(y2.metinler, ['Kasımda plan yok.']);

      // Düşünme öğesi ve araç çağrısı aynen, sonra araç sonucu
      final girdi = s.govde(1)['input'] as List;
      expect(girdi[1], dusunme);
      expect(girdi[2]['type'], 'function_call');
      expect(girdi[3], {
        'type': 'function_call_output',
        'call_id': 'call_1',
        'output': 'Plan yok.',
      });
    });

    test('çıktı sınırı, ret ve kredi hatası', () async {
      final s = Sahte([
        json({
          'status': 'incomplete',
          'incomplete_details': {'reason': 'max_output_tokens'},
          'output': <Object>[],
        }),
        json({
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'refusal', 'refusal': 'Yapamam.'},
              ],
            },
          ],
        }),
        json({
          'error': {
            'message':
                'You exceeded your current quota, please check your '
                'plan and billing details.',
          },
        }, 429),
      ]);
      final i = istemci(s)..kullaniciEkle('b', 'm');
      expect(
        (await i.yanitAl(sistem: '', araclar: araclar)).son,
        YanitSonu.uzunluk,
      );
      expect(
        (await i.yanitAl(sistem: '', araclar: araclar)).son,
        YanitSonu.ret,
      );
      await expectLater(
        i.yanitAl(sistem: '', araclar: araclar),
        throwsA(
          isA<YzHatasi>().having((e) => e.mesaj, 'mesaj', contains('kredi')),
        ),
      );
    });
  });

  group('DeepSeek', () {
    final model = Saglayici.deepseek.varsayilanModel;

    DeepSeekIstemcisi istemci(Sahte s) => DeepSeekIstemcisi(
      apiAnahtari: 'sk-deepseek-test-anahtari',
      model: model,
      httpIstemcisi: s.client,
      tekrarBeklemesi: Duration.zero,
    );

    test('reasoning_content araç turlarında aynen geri gönderilir', () async {
      final asistan = {
        'role': 'assistant',
        'content': '',
        'reasoning_content': 'Önce kasımı listelemeliyim.',
        'tool_calls': [
          {
            'id': 'call_9',
            'type': 'function',
            'function': {
              'name': 'planlari_listele',
              'arguments': jsonEncode(listeleArgs),
            },
          },
        ],
      };
      final s = Sahte([
        json({
          'choices': [
            {'message': asistan, 'finish_reason': 'tool_calls'},
          ],
          'usage': {
            'prompt_cache_hit_tokens': 300,
            'prompt_cache_miss_tokens': 700,
            'completion_tokens': 40,
          },
        }),
        json({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Plan yok.'},
              'finish_reason': 'stop',
            },
          ],
        }),
      ]);
      final i = istemci(s)..kullaniciEkle('<baglam/>', 'Kasım?');

      final y1 = await i.yanitAl(sistem: 'SİSTEM', araclar: araclar);
      expect(y1.son, YanitSonu.arac);
      expect(y1.metinler, isEmpty); // boş içerik gösterilmez
      expect(y1.kullanim.girdi, 700);
      expect(y1.kullanim.onbellekOkunan, 300);

      final r = s.istekler[0];
      expect(r.url.toString(), 'https://api.deepseek.com/chat/completions');
      expect(r.headers['authorization'], 'Bearer sk-deepseek-test-anahtari');
      final g = s.govde(0);
      expect(g['model'], 'deepseek-flash');
      expect(g['messages'][0], {'role': 'system', 'content': 'SİSTEM'});
      expect(g['messages'][1]['content'], '<baglam/>\n\nKasım?');
      expect(g['tools'][0]['function']['name'], 'planlari_listele');

      i.sonuclariEkle([sonuc(y1)]);
      final y2 = await i.yanitAl(sistem: 'SİSTEM', araclar: araclar);
      expect(y2.metinler, ['Plan yok.']);

      final m = s.govde(1)['messages'] as List;
      expect(m[2], asistan); // reasoning_content dahil, değişmeden
      expect(m[3], {
        'role': 'tool',
        'tool_call_id': 'call_9',
        'content': 'Plan yok.',
      });
    });

    test('402 bakiye hatası', () async {
      final s = Sahte([
        json({
          'error': {'message': 'Insufficient Balance'},
        }, 402),
      ]);
      final i = istemci(s)..kullaniciEkle('b', 'm');
      await expectLater(
        i.yanitAl(sistem: '', araclar: araclar),
        throwsA(
          isA<YzHatasi>().having((e) => e.mesaj, 'mesaj', contains('bakiye')),
        ),
      );
    });
  });

  group('Gemini', () {
    final model = Saglayici.gemini.varsayilanModel;

    GeminiIstemcisi istemci(Sahte s) => GeminiIstemcisi(
      apiAnahtari: 'AIza-gemini-test-anahtari',
      model: model,
      httpIstemcisi: s.client,
      tekrarBeklemesi: Duration.zero,
    );

    test('şema, imzalı parçaların korunması ve functionResponse', () async {
      final modelIcerigi = {
        'role': 'model',
        'parts': [
          {'text': 'Düşünüyorum...', 'thought': true},
          {
            'functionCall': {
              'id': 'fc_7',
              'name': 'planlari_listele',
              'args': listeleArgs,
            },
            'thoughtSignature': 'imza==',
          },
        ],
      };
      final s = Sahte([
        json({
          'candidates': [
            {'content': modelIcerigi, 'finishReason': 'STOP'},
          ],
          'usageMetadata': {
            'promptTokenCount': 900,
            'cachedContentTokenCount': 100,
            'candidatesTokenCount': 30,
            'thoughtsTokenCount': 70,
          },
        }),
        json({
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {'text': 'Kasımda plan yok.'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }),
      ]);
      final i = istemci(s)..kullaniciEkle('<baglam/>', 'Kasım?');

      final y1 = await i.yanitAl(sistem: 'SİSTEM', araclar: araclar);
      expect(y1.son, YanitSonu.arac);
      expect(y1.metinler, isEmpty, reason: 'düşünme parçası gösterilmez');
      expect(y1.cagrilar.single.id, 'fc_7');
      expect(y1.kullanim.girdi, 800);
      expect(y1.kullanim.cikti, 100);

      final r = s.istekler[0];
      expect(
        r.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.8-flash:generateContent',
      );
      expect(r.headers['x-goog-api-key'], 'AIza-gemini-test-anahtari');
      final g = s.govde(0);
      expect(g['systemInstruction']['parts'][0]['text'], 'SİSTEM');
      final bildirim = g['tools'][0]['functionDeclarations'][1];
      expect(bildirim['name'], 'degisiklik_oner');
      expect(bildirim['parameters']['type'], 'OBJECT');
      expect(
        bildirim['parameters']['properties']['islemler']['items']['properties']['plan_id']['type'],
        'INTEGER',
      );
      // Özellik adları ("tur", "not"...) değişmez
      expect(
        (bildirim['parameters']['properties']['islemler']['items']['properties']
                as Map)
            .keys,
        contains('tur'),
      );

      i.sonuclariEkle([sonuc(y1)]);
      final y2 = await i.yanitAl(sistem: 'SİSTEM', araclar: araclar);
      expect(y2.metinler, ['Kasımda plan yok.']);

      final c = s.govde(1)['contents'] as List;
      expect(c[1], modelIcerigi, reason: 'thoughtSignature aynen geri gider');
      expect(c[2], {
        'role': 'user',
        'parts': [
          {
            'functionResponse': {
              'name': 'planlari_listele',
              'id': 'fc_7',
              'response': {'sonuc': 'Plan yok.'},
            },
          },
        ],
      });
    });

    test('engellenen istek, geçersiz anahtar ve kota', () async {
      final s = Sahte([
        json({
          'promptFeedback': {'blockReason': 'SAFETY'},
        }),
        json({
          'error': {
            'code': 400,
            'message': 'API key not valid. Please pass a valid API key.',
            'status': 'INVALID_ARGUMENT',
          },
        }, 400),
        json({
          'error': {
            'code': 429,
            'message': 'You exceeded your current quota.',
            'status': 'RESOURCE_EXHAUSTED',
          },
        }, 429),
      ]);
      final i = istemci(s)..kullaniciEkle('b', 'm');
      expect(
        (await i.yanitAl(sistem: '', araclar: araclar)).son,
        YanitSonu.ret,
      );
      await expectLater(
        i.yanitAl(sistem: '', araclar: araclar),
        throwsA(
          isA<YzHatasi>().having((e) => e.mesaj, 'mesaj', contains('geçersiz')),
        ),
      );
      await expectLater(
        i.yanitAl(sistem: '', araclar: araclar),
        throwsA(
          isA<YzHatasi>().having((e) => e.mesaj, 'mesaj', contains('kotan')),
        ),
      );
    });
  });

  test('model kataloğu: varsayılanlar ve elle yazılan model', () {
    expect(Saglayici.anthropic.varsayilanModel.id, 'claude-opus-5-5');
    expect(Saglayici.openai.varsayilanModel.id, 'gpt-6.1-sol');
    expect(Saglayici.gemini.varsayilanModel.id, 'gemini-3.8-flash');
    expect(Saglayici.deepseek.varsayilanModel.id, 'deepseek-flash');

    final elle = Saglayici.openai.model('gpt-7-deneme');
    expect(elle.elleYazildi, isTrue);
    expect(elle.maliyet(const Kullanim(girdi: 1000)), isNull);
    expect(Saglayici.openai.model('gpt-6-luna').ad, 'GPT-6 Luna');
    expect(Saglayici.adindan('gemini'), Saglayici.gemini);
    expect(Saglayici.adindan('bilinmeyen'), Saglayici.anthropic);
  });

  // Her sağlayıcıyla uçtan uca: öneri → onay → plan değişir.
  group('uçtan uca öneri ve onay', () {
    sqfliteFfiInit();
    late Database db;
    late PlanDeposu depo;
    final cuma = DateTime.utc(2026, 10, 16);

    setUp(() async {
      db = await Veritabani.acFactory(databaseFactoryFfi, inMemoryDatabasePath);
      depo = PlanDeposu(db);
    });
    tearDown(() => db.close());

    Map<String, Object?> oneriArgs(int id) => {
      'aciklama': 'Dersi 18:00\'e al',
      'islemler': [
        {'tur': 'guncelle', 'plan_id': id, 'baslangic_saati': 18},
      ],
    };

    final yanitlar = <Saglayici, List<http.Response> Function(int id)>{
      Saglayici.openai: (id) => [
        json({
          'output': [
            {
              'type': 'function_call',
              'call_id': 'c1',
              'name': 'degisiklik_oner',
              'arguments': jsonEncode(oneriArgs(id)),
            },
          ],
        }),
        json({
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'Tamam.'},
              ],
            },
          ],
        }),
      ],
      Saglayici.deepseek: (id) => [
        json({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'reasoning_content': '...',
                'tool_calls': [
                  {
                    'id': 'c1',
                    'type': 'function',
                    'function': {
                      'name': 'degisiklik_oner',
                      'arguments': jsonEncode(oneriArgs(id)),
                    },
                  },
                ],
              },
              'finish_reason': 'tool_calls',
            },
          ],
        }),
        json({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Tamam.'},
              'finish_reason': 'stop',
            },
          ],
        }),
      ],
      Saglayici.gemini: (id) => [
        json({
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {
                    'functionCall': {
                      'name': 'degisiklik_oner',
                      'args': oneriArgs(id),
                    },
                  },
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }),
        json({
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {'text': 'Tamam.'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }),
      ],
    };

    for (final e in yanitlar.entries) {
      test(e.key.kisaAd, () async {
        final ders = await depo.ekle(
          Plan(baslik: 'Ders', gun: cuma, baslangicSaati: 15),
        );
        final s = Sahte(e.value(ders.id!));
        final sohbet = AsistanSohbeti(
          depo: depo,
          simdi: () => DateTime(2026, 10, 16, 12),
          istemci: istemciOlustur(
            model: e.key.varsayilanModel,
            apiAnahtari: 'test-anahtari-12345678901234',
            httpIstemcisi: s.client,
            tekrarBeklemesi: Duration.zero,
          ),
        );

        final is_ = sohbet.gonder('Dersi akşama al');
        DegisiklikOnerisi? oneri;
        for (var i = 0; i < 2000 && oneri == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          oneri = sohbet.ogeler.whereType<DegisiklikOnerisi>().firstOrNull;
        }
        expect(oneri, isNotNull);
        sohbet.karar(oneri!, true);
        await is_;

        expect(oneri.durum, OneriDurumu.onaylandi);
        expect((await depo.planGetir(ders.id!))!.baslangicSaati, 18);
        expect((sohbet.ogeler.last as AsistanMesaji).metin, 'Tamam.');
        expect(s.istekler, hasLength(2));
        expect(sohbet.maliyet, isNotNull);
      });
    }
  });
}
