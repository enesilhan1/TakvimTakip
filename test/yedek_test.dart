import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takvim_takip/logic/yedek.dart';
import 'package:takvim_takip/models/kayma_kaydi.dart';
import 'package:takvim_takip/models/plan.dart';

void main() {
  final pzt = DateTime.utc(2026, 10, 19);
  final sali = DateTime.utc(2026, 10, 20);

  Yedek ornek() => Yedek(
    olusturma: DateTime(2026, 10, 16, 14, 30),
    planlar: [
      Plan(
        id: 1,
        baslik: 'Kitap okuma',
        not: '50 sayfa',
        gun: sali,
        baslangicSaati: 13,
        sure: 2,
        yapilmadiSayisi: 1,
      ),
      Plan(
        id: 2,
        baslik: 'Spor',
        gun: sali,
        baslangicSaati: 16,
        sabit: true,
        durum: PlanDurumu.yapildi,
      ),
    ],
    kaymaKayitlari: [
      KaymaKaydi(
        id: 1,
        planId: 1,
        baslik: 'Kitap okuma',
        gun: pzt,
        baslangicSaati: 15,
        sure: 1,
        yeniGun: sali,
        yeniBaslangicSaati: 13,
      ),
    ],
    ayarlar: {'son_islenen_gun': '2026-10-19', 'sabah_saati': '8'},
  );

  test('JSON gidiş-dönüş bütün veriyi korur', () {
    final y = ornek();
    final geri = Yedek.coz(y.jsonMetni());

    expect(geri.olusturma, y.olusturma);
    expect(geri.planlar, y.planlar);
    expect(geri.kaymaKayitlari, y.kaymaKayitlari);
    expect(geri.ayarlar, y.ayarlar);
  });

  test('JSON okunaklı ve uygulama bilgisini taşır', () {
    final metin = ornek().jsonMetni();
    expect(metin, contains('\n  "uygulama": "Takvim Takip"'));
    expect(metin, contains('"bicim": 1'));
    expect(metin, contains('"baslik": "Kitap okuma"'));
  });

  test('dosya adı tarih ve saati içerir', () {
    expect(ornek().dosyaAdi(), 'takvim_takip_yedek_2026-10-16_1430.json');
  });

  group('hatalı dosyalar', () {
    void hata(String metin, String mesajParcasi) {
      expect(
        () => Yedek.coz(metin),
        throwsA(
          isA<YedekHatasi>().having(
            (e) => e.mesaj,
            'mesaj',
            contains(mesajParcasi),
          ),
        ),
      );
    }

    test(
      'JSON değil',
      () => hata('merhaba', 'geçerli bir yedek dosyası değil'),
    );

    test('başka uygulamanın JSON dosyası', () {
      hata('{"a": 1}', 'Takvim Takip yedeği değil');
      hata('[1, 2]', 'Takvim Takip yedeği değil');
    });

    test('daha yeni biçim', () {
      final m = jsonDecode(ornek().jsonMetni()) as Map<String, dynamic>;
      m['bicim'] = 99;
      hata(jsonEncode(m), 'daha yeni bir sürümüyle');
    });

    test('bozuk plan kaydı', () {
      final m = jsonDecode(ornek().jsonMetni()) as Map<String, dynamic>;
      (m['planlar'] as List).first['baslangic_saati'] = 30;
      hata(jsonEncode(m), 'bozuk');
    });
  });
}
