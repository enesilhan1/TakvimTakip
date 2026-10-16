import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/logic/plan_islemleri.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  final pzt = DateTime.utc(2026, 10, 19);
  final sali = gunEkle(pzt, 1);
  final paz = gunEkle(pzt, -1);

  Plan p(
    int id,
    String baslik,
    DateTime gun,
    int saat, {
    int sure = 1,
    bool sabit = false,
    PlanDurumu durum = PlanDurumu.isaretsiz,
  }) => Plan(
    id: id,
    baslik: baslik,
    gun: gun,
    baslangicSaati: saat,
    sure: sure,
    sabit: sabit,
    durum: durum,
  );

  List<PlanIslemi> coz(List<Map<String, dynamic>> l) =>
      l.map(PlanIslemi.jsondan).toList();

  Matcher hata(String parca) => throwsA(
    isA<IslemHatasi>().having((e) => e.mesaj, 'mesaj', contains(parca)),
  );

  group('çözümleme', () {
    test('dört işlem türü', () {
      final l = coz([
        {
          'tur': 'ekle',
          'baslik': 'Ders',
          'gun': '2026-10-20',
          'baslangic_saati': 14,
          'sure': 2,
          'not': 'türev',
        },
        {'tur': 'guncelle', 'plan_id': 3, 'baslangic_saati': 18},
        {'tur': 'sil', 'plan_id': 4},
        {'tur': 'durum', 'plan_id': 5, 'durum': 'yapildi'},
      ]);
      final e = l[0] as Ekle;
      expect(e.gun, sali);
      expect(e.sure, 2);
      expect(e.not, 'türev');
      expect(e.sabit, isFalse);
      final g = l[1] as Guncelle;
      expect(g.baslangicSaati, 18);
      expect(g.gun, isNull);
      expect((l[2] as Sil).planId, 4);
      expect((l[3] as DurumDegistir).durum, PlanDurumu.yapildi);
    });

    test('JSON sayıları 14.0 gibi gelse de kabul edilir', () {
      final e = PlanIslemi.jsondan({
        'tur': 'ekle',
        'baslik': 'X',
        'gun': '2026-10-20',
        'baslangic_saati': 14.0,
      });
      expect((e as Ekle).baslangicSaati, 14);
    });

    test('hatalı alanlar anlaşılır mesaj verir', () {
      expect(() => PlanIslemi.jsondan({'tur': 'uç'}), hata('Bilinmeyen'));
      expect(
        () => PlanIslemi.jsondan({'tur': 'ekle', 'gun': '2026-10-20'}),
        hata('"baslik" alanı eksik'),
      );
      expect(
        () => PlanIslemi.jsondan({
          'tur': 'ekle',
          'baslik': 'X',
          'gun': '20.10.2026',
          'baslangic_saati': 9,
        }),
        hata('YYYY-AA-GG'),
      );
      expect(
        () => PlanIslemi.jsondan({
          'tur': 'ekle',
          'baslik': 'X',
          'gun': '2026-02-30',
          'baslangic_saati': 9,
        }),
        hata('Geçersiz tarih'),
      );
      expect(
        () => PlanIslemi.jsondan({
          'tur': 'durum',
          'plan_id': 1,
          'durum': 'bitti',
        }),
        hata('Geçersiz durum'),
      );
    });
  });

  group('doğrulama ve önizleme', () {
    final mevcut = [
      p(1, 'Ders', sali, 13, sure: 2),
      p(2, 'Spor', sali, 16, sabit: true),
      p(3, 'Kitap', pzt, 9),
    ];

    test('karışık işlemler ve önizleme satırları', () {
      final plan = islemleriDogrula(
        coz([
          {
            'tur': 'ekle',
            'baslik': 'Yürüyüş',
            'gun': '2026-10-20',
            'baslangic_saati': 18,
          },
          {'tur': 'guncelle', 'plan_id': 1, 'baslangic_saati': 10},
          {'tur': 'sil', 'plan_id': 2},
          {'tur': 'durum', 'plan_id': 3, 'durum': 'yapildi'},
        ]),
        mevcut,
        bugun: pzt,
      );

      expect(plan.eklenecek.single.baslik, 'Yürüyüş');
      expect(plan.guncellenecek.map((x) => x.id), unorderedEquals([1, 3]));
      expect(
        plan.guncellenecek.firstWhere((x) => x.id == 1).baslangicSaati,
        10,
      );
      expect(plan.guncellenecek.firstWhere((x) => x.id == 1).sure, 2);
      expect(plan.silinecek, [2]);
      expect(plan.onizleme, [
        '➕ Salı 20 Ekim 18:00 Yürüyüş',
        '✏️ Ders: Salı 13:00–15:00 → Salı 20 Ekim 10:00–12:00',
        '🗑 Sil: Salı 20 Ekim 16:00 📌Spor',
        '✅ Kitap: yapıldı',
      ]);
    });

    test('sonuçta çakışma varsa hiçbiri kabul edilmez', () {
      expect(
        () => islemleriDogrula(
          coz([
            {
              'tur': 'ekle',
              'baslik': 'Yeni',
              'gun': '2026-10-20',
              'baslangic_saati': 14,
            },
          ]),
          mevcut,
          bugun: pzt,
        ),
        hata('Çakışma'),
      );
    });

    test('silinen planın yerine ekleme serbest (sıra önemli)', () {
      final plan = islemleriDogrula(
        coz([
          {'tur': 'sil', 'plan_id': 1},
          {
            'tur': 'ekle',
            'baslik': 'Yeni',
            'gun': '2026-10-20',
            'baslangic_saati': 13,
          },
        ]),
        mevcut,
        bugun: pzt,
      );
      expect(plan.silinecek, [1]);
      expect(plan.eklenecek, hasLength(1));
    });

    test('geçmiş gün kuralları', () {
      final gecmis = [
        ...mevcut,
        p(4, 'Dün', paz, 9, durum: PlanDurumu.yapildi),
        p(5, 'DünSabit', paz, 10, sabit: true),
      ];
      expect(
        () => islemleriDogrula(
          coz([
            {
              'tur': 'ekle',
              'baslik': 'X',
              'gun': gunAnahtari(paz),
              'baslangic_saati': 12,
            },
          ]),
          gecmis,
          bugun: pzt,
        ),
        hata('geçmiş bir güne'),
      );
      expect(
        () => islemleriDogrula(
          coz([
            {'tur': 'guncelle', 'plan_id': 1, 'gun': gunAnahtari(paz)},
          ]),
          gecmis,
          bugun: pzt,
        ),
        hata('geçmiş bir güne'),
      );
      expect(
        () => islemleriDogrula(
          coz([
            {'tur': 'guncelle', 'plan_id': 4, 'baslik': 'Y'},
          ]),
          gecmis,
          bugun: pzt,
        ),
        hata('sadece durumu'),
      );
      expect(
        () => islemleriDogrula(
          coz([
            {'tur': 'durum', 'plan_id': 4, 'durum': 'isaretsiz'},
          ]),
          gecmis,
          bugun: pzt,
        ),
        hata('takılı kalır'),
      );
      // Sabit planın işareti geçmişte de değiştirilebilir
      final ok = islemleriDogrula(
        coz([
          {'tur': 'durum', 'plan_id': 5, 'durum': 'yapildi'},
        ]),
        gecmis,
        bugun: pzt,
      );
      expect(ok.guncellenecek.single.durum, PlanDurumu.yapildi);
    });

    test('olmayan plan ve geçersiz saat', () {
      expect(
        () => islemleriDogrula(
          coz([
            {'tur': 'sil', 'plan_id': 99},
          ]),
          mevcut,
          bugun: pzt,
        ),
        hata('99 numaralı plan bulunamadı'),
      );
      expect(
        () => islemleriDogrula(
          coz([
            {'tur': 'guncelle', 'plan_id': 1, 'baslangic_saati': 23},
          ]),
          mevcut,
          bugun: pzt,
        ),
        hata('gece yarısını geçmemeli'),
      );
    });

    test('etkilenen günler', () {
      final gunler = etkilenenGunler(
        coz([
          {
            'tur': 'ekle',
            'baslik': 'X',
            'gun': '2026-10-22',
            'baslangic_saati': 9,
          },
          {'tur': 'guncelle', 'plan_id': 3, 'gun': '2026-10-21'},
        ]),
        (id) => id == 3 ? pzt : null,
      );
      expect(gunler, {
        DateTime.utc(2026, 10, 22),
        pzt,
        DateTime.utc(2026, 10, 21),
      });
    });
  });

  test('topluUygula hepsini tek işlemde uygular', () async {
    sqfliteFfiInit();
    final db = await Veritabani.acFactory(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    final depo = PlanDeposu(db);
    final a = await depo.ekle(Plan(baslik: 'A', gun: sali, baslangicSaati: 9));
    final b = await depo.ekle(Plan(baslik: 'B', gun: sali, baslangicSaati: 10));

    final plan = islemleriDogrula(
      coz([
        {'tur': 'sil', 'plan_id': a.id},
        {'tur': 'guncelle', 'plan_id': b.id, 'baslangic_saati': 9},
        {
          'tur': 'ekle',
          'baslik': 'C',
          'gun': '2026-10-20',
          'baslangic_saati': 11,
        },
      ]),
      await depo.gununPlanlari(sali),
      bugun: pzt,
    );
    await depo.topluUygula(
      eklenecek: plan.eklenecek,
      guncellenecek: plan.guncellenecek,
      silinecek: plan.silinecek,
    );

    final son = await depo.gununPlanlari(sali);
    expect(son.map((x) => '${x.baslangicSaati} ${x.baslik}'), ['9 B', '11 C']);
    await db.close();
  });
}
