import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/claude/claude_istemcisi.dart';
import 'package:takvim_takip/claude/claude_sohbet.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

/// Sırayla verilen yanıtları döndüren sahte Anthropic API'si.
class SahteApi {
  final List<http.Response Function(Map<String, dynamic> govde)> yanitlar;
  final List<Map<String, dynamic>> istekler = [];
  final List<Map<String, String>> basliklar = [];

  SahteApi(this.yanitlar);

  late final client = MockClient((istek) async {
    final govde = jsonDecode(istek.body) as Map<String, dynamic>;
    istekler.add(govde);
    basliklar.add(istek.headers);
    return yanitlar[istekler.length - 1](govde);
  });
}

http.Response mesaj(
  List<Map<String, Object?>> icerik, {
  String stop = 'end_turn',
}) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'content': icerik,
      'stop_reason': stop,
      'usage': {'input_tokens': 1000, 'output_tokens': 100},
    }),
  ),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> metin(String t) => {'type': 'text', 'text': t};

Map<String, Object?> arac(String ad, Map<String, Object?> girdi) => {
  'type': 'tool_use',
  'id': 'toolu_$ad',
  'name': ad,
  'input': girdi,
};

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlanDeposu depo;
  final cuma = DateTime.utc(2026, 10, 16);
  final simdi = DateTime(2026, 10, 16, 15, 42);

  setUp(() async {
    db = await Veritabani.acFactory(databaseFactoryFfi, inMemoryDatabasePath);
    depo = PlanDeposu(db);
  });

  tearDown(() => db.close());

  ClaudeSohbeti sohbet(
    SahteApi api, {
    ClaudeModeli model = ClaudeModeli.opus,
  }) => ClaudeSohbeti(
    depo: depo,
    simdi: () => simdi,
    istemci: ClaudeIstemcisi(
      apiAnahtari: 'test-anahtari',
      model: model,
      httpIstemcisi: api.client,
      tekrarBeklemesi: Duration.zero,
    ),
  );

  group('istemci', () {
    test(
      'istek biçimi: model, efor, önbellek, yedek model, başlıklar',
      () async {
        final api = SahteApi([
          (_) => mesaj([metin('Merhaba!')]),
        ]);
        await sohbet(api).gonder('selam');

        final g = api.istekler.single;
        expect(g['model'], 'claude-opus-5-5');
        expect(g['max_tokens'], 16000);
        expect(g['output_config'], {'effort': 'medium'});
        expect(g['cache_control'], {'type': 'ephemeral'});
        expect(g['fallbacks'], 'default');
        expect(g.containsKey('thinking'), isFalse);
        expect((g['tools'] as List).map((t) => t['name']), [
          'planlari_listele',
          'degisiklik_oner',
        ]);
        final b = api.basliklar.single;
        expect(b['x-api-key'], 'test-anahtari');
        expect(b['anthropic-version'], '2023-06-01');
        expect(b['anthropic-beta'], 'server-side-fallback-2026-07-01');
      },
    );

    test('Haiku yedek model desteklemez, gönderilmez', () async {
      final api = SahteApi([
        (_) => mesaj([metin('ok')]),
      ]);
      await sohbet(api, model: ClaudeModeli.haiku).gonder('selam');

      expect(api.istekler.single['model'], 'claude-haiku-5-5');
      expect(api.istekler.single.containsKey('fallbacks'), isFalse);
      expect(api.basliklar.single.containsKey('anthropic-beta'), isFalse);
    });

    test('429 ve 529 tekrar denenir', () async {
      final api = SahteApi([
        (_) => http.Response('{}', 429),
        (_) => http.Response('{}', 529),
        (_) => mesaj([metin('Sonunda!')]),
      ]);
      final s = sohbet(api);
      await s.gonder('selam');
      expect(api.istekler, hasLength(3));
      expect((s.ogeler.last as ClaudeMesaji).metin, 'Sonunda!');
    });

    test('hatalar Türkçe ve anlaşılır', () async {
      Future<String> hata(http.Response r) async {
        final api = SahteApi([(_) => r, (_) => r, (_) => r]);
        final s = sohbet(api);
        await s.gonder('selam');
        return (s.ogeler.last as BilgiMesaji).metin;
      }

      expect(
        await hata(
          http.Response('{"error":{"message":"invalid x-api-key"}}', 401),
        ),
        contains('API anahtarı geçersiz'),
      );
      expect(
        await hata(
          http.Response(
            '{"error":{"message":"Your credit balance is too low"}}',
            400,
          ),
        ),
        contains('bakiyesi yetersiz'),
      );
      expect(await hata(http.Response('{}', 503)), contains('çok yoğun'));
    });
  });

  group('sohbet', () {
    test('bağlamda tarih ve 14 günün planları gönderilir', () async {
      await depo.ekle(
        Plan(baslik: 'Ders', not: 'türev', gun: cuma, baslangicSaati: 15),
      );
      await depo.ekle(
        Plan(baslik: 'Uzak', gun: gunEkle(cuma, 20), baslangicSaati: 9),
      );
      final api = SahteApi([
        (_) => mesaj([metin('Tamam.')]),
      ]);
      final s = sohbet(api);
      await s.gonder('Bugün neler var?');

      final icerik =
          (api.istekler.single['messages'] as List).single['content'] as List;
      final baglam = icerik[0]['text'] as String;
      expect(baglam, contains('16 Ekim 2026 Cuma, saat 15:42'));
      expect(
        baglam,
        contains(
          '#1 · 2026-10-16 Cuma · 15:00–16:00 · Ders · '
          'isaretsiz · not: türev',
        ),
      );
      expect(baglam, isNot(contains('Uzak')));
      expect(icerik[1]['text'], 'Bugün neler var?');
      expect(s.ogeler.map((o) => o.runtimeType), [
        KullaniciMesaji,
        ClaudeMesaji,
      ]);
    });

    test('öneri onaylanınca uygulanır, sonuç Claude\'a bildirilir', () async {
      final ders = await depo.ekle(
        Plan(baslik: 'Ders', gun: cuma, baslangicSaati: 15),
      );
      final api = SahteApi([
        (_) => mesaj([
          metin('Dersi 18:00\'e alıyorum.'),
          arac('degisiklik_oner', {
            'aciklama': 'Dersi akşama al',
            'islemler': [
              {'tur': 'guncelle', 'plan_id': ders.id, 'baslangic_saati': 18},
            ],
          }),
        ], stop: 'tool_use'),
        (_) => mesaj([metin('Tamamdır, ders artık 18:00\'de.')]),
      ]);
      final s = sohbet(api);
      final is_ = s.gonder('Dersi akşama al');

      // Claude öneriyi yaptı, kullanıcının onayı bekleniyor
      await pumpEventQueue();
      final oneri = s.ogeler.whereType<DegisiklikOnerisi>().single;
      expect(oneri.durum, OneriDurumu.bekliyor);
      expect(
        oneri.plan.onizleme.single,
        '✏️ Ders: Cuma 15:00 → Cuma 16 Ekim 18:00',
      );
      expect(s.onayBekliyor, isTrue);
      expect((await depo.planGetir(ders.id!))!.baslangicSaati, 15);

      s.karar(oneri, true);
      await is_;

      expect(oneri.durum, OneriDurumu.onaylandi);
      expect((await depo.planGetir(ders.id!))!.baslangicSaati, 18);

      // İkinci istekte geçmiş: kullanıcı, asistan (tool_use), araç sonucu
      final m = api.istekler[1]['messages'] as List;
      expect(m.map((x) => x['role']), ['user', 'assistant', 'user']);
      final sonuc = (m[2]['content'] as List).single;
      expect(sonuc['type'], 'tool_result');
      expect(sonuc['tool_use_id'], 'toolu_degisiklik_oner');
      expect(sonuc['content'], contains('onayladı'));
      expect(sonuc.containsKey('is_error'), isFalse);
      expect(
        (s.ogeler.last as ClaudeMesaji).metin,
        'Tamamdır, ders artık 18:00\'de.',
      );
    });

    test('reddedilen öneri uygulanmaz', () async {
      final ders = await depo.ekle(
        Plan(baslik: 'Ders', gun: cuma, baslangicSaati: 15),
      );
      final api = SahteApi([
        (_) => mesaj([
          arac('degisiklik_oner', {
            'aciklama': 'Dersi sil',
            'islemler': [
              {'tur': 'sil', 'plan_id': ders.id},
            ],
          }),
        ], stop: 'tool_use'),
        (_) => mesaj([metin('Peki, silmedim.')]),
      ]);
      final s = sohbet(api);
      final is_ = s.gonder('Dersi sil');
      await pumpEventQueue();
      s.karar(s.ogeler.whereType<DegisiklikOnerisi>().single, false);
      await is_;

      expect(await depo.planGetir(ders.id!), isNotNull);
      final sonuc =
          ((api.istekler[1]['messages'] as List)[2]['content'] as List).single;
      expect(sonuc['content'], contains('REDDETTİ'));
    });

    test(
      'geçersiz öneri hata olarak Claude\'a döner, kullanıcıya sorulmaz',
      () async {
        await depo.ekle(Plan(baslik: 'Ders', gun: cuma, baslangicSaati: 15));
        final api = SahteApi([
          (_) => mesaj([
            arac('degisiklik_oner', {
              'aciklama': 'Çakışan ekleme',
              'islemler': [
                {
                  'tur': 'ekle',
                  'baslik': 'Spor',
                  'gun': '2026-10-16',
                  'baslangic_saati': 15,
                },
              ],
            }),
          ], stop: 'tool_use'),
          (_) => mesaj([metin('15:00 dolu, 16:00 olur mu?')]),
        ]);
        final s = sohbet(api);
        await s.gonder('15:00\'e spor ekle');

        expect(s.ogeler.whereType<DegisiklikOnerisi>(), isEmpty);
        expect(
          s.ogeler.whereType<BilgiMesaji>().single.metin,
          contains('Çakışma'),
        );
        final sonuc =
            ((api.istekler[1]['messages'] as List)[2]['content'] as List)
                .single;
        expect(sonuc['is_error'], isTrue);
        expect(await depo.gununPlanlari(cuma), hasLength(1));
      },
    );

    test('planlari_listele onaysız çalışır', () async {
      await depo.ekle(
        Plan(
          baslik: 'Uzak',
          gun: DateTime.utc(2026, 11, 20),
          baslangicSaati: 9,
        ),
      );
      final api = SahteApi([
        (_) => mesaj([
          arac('planlari_listele', {
            'baslangic': '2026-11-01',
            'bitis': '2026-11-30',
          }),
        ], stop: 'tool_use'),
        (_) => mesaj([metin('20 Kasım\'da Uzak var.')]),
      ]);
      await sohbet(api).gonder('Kasımda ne var?');

      final sonuc =
          ((api.istekler[1]['messages'] as List)[2]['content'] as List).single;
      expect(
        sonuc['content'],
        contains('2026-11-20 Cuma · 09:00–10:00 · Uzak'),
      );
    });

    test('ret (refusal) bilgi mesajı olarak gösterilir', () async {
      final api = SahteApi([(_) => mesaj(const [], stop: 'refusal')]);
      final s = sohbet(api);
      await s.gonder('...');
      expect((s.ogeler.last as BilgiMesaji).metin, contains('yanıtlayamadı'));
    });

    test('hatadan sonra sohbet bozulmadan devam eder', () async {
      final api = SahteApi([
        (_) => http.Response('{}', 401),
        (_) => mesaj([metin('Şimdi çalıştı.')]),
      ]);
      final s = sohbet(api);
      await s.gonder('ilk');
      await s.gonder('ikinci');

      // İkinci istekte yanıtsız kalan ilk mesaj yok: tek kullanıcı mesajı
      final m = api.istekler[1]['messages'] as List;
      expect(m, hasLength(1));
      expect((m.single['content'] as List)[1]['text'], 'ikinci');
      expect((s.ogeler.last as ClaudeMesaji).metin, 'Şimdi çalıştı.');
    });

    test('düşünme blokları geçmişte olduğu gibi geri gönderilir', () async {
      final dusunme = {'type': 'thinking', 'thinking': '', 'signature': 'abc'};
      final api = SahteApi([
        (_) => mesaj([dusunme, metin('Bir.')]),
        (_) => mesaj([metin('İki.')]),
      ]);
      final s = sohbet(api);
      await s.gonder('bir');
      await s.gonder('iki');

      final asistan = (api.istekler[1]['messages'] as List)[1];
      expect(asistan['content'][0], dusunme);
      expect(s.maliyet, greaterThan(0));
    });
  });
}
