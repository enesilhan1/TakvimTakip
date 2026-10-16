import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takvim_takip/data/plan_deposu.dart';
import 'package:takvim_takip/data/veritabani.dart';
import 'package:takvim_takip/logic/gun_ozeti.dart';
import 'package:takvim_takip/logic/istatistik.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  final g1 = DateTime.utc(2026, 10, 1);
  DateTime g(int n) => gunEkle(g1, n);

  GunOzeti tam(int n) => GunOzeti(yapilan: n, kalan: n);
  GunOzeti eksik() => const GunOzeti(yapilan: 1, kalan: 1, kayan: 1);

  group('yilIstatistigi', () {
    test('toplamlar ve oran bugüne kadar sayılır', () {
      final ozet = {
        g(0): tam(2),
        g(1): eksik(), // 1/2, 1 kaydı
        g(5): const GunOzeti(kalan: 3), // gelecek: sayılmaz
      };
      final i = yilIstatistigi(ozet, yil: 2026, bugun: g(2));

      expect(i.planSayisi, 4);
      expect(i.yapilan, 3);
      expect(i.kayma, 1);
      expect(i.oran, 0.75);
    });

    test('seri: planı olmayan gün bozmaz, eksik gün sıfırlar', () {
      final ozet = {
        g(0): tam(1),
        g(1): tam(1),
        g(2): eksik(),
        g(3): tam(1),
        // g(4) planı yok
        g(5): tam(2),
        g(6): tam(1),
      };
      final i = yilIstatistigi(ozet, yil: 2026, bugun: g(7));
      expect(i.enUzunSeri, 3); // g3, g5, g6
      expect(i.mevcutSeri, 3);
    });

    test('bugün tamamlanmadıysa mevcut seri bozulmaz', () {
      final ozet = {
        g(0): tam(1),
        g(1): tam(1),
        g(2): const GunOzeti(kalan: 2), // bugün, henüz yapılmadı
      };
      final i = yilIstatistigi(ozet, yil: 2026, bugun: g(2));
      expect(i.mevcutSeri, 2);
    });

    test('başka yılın günleri sayılmaz, boş yılın oranı yok', () {
      final ozet = {DateTime.utc(2025, 12, 31): tam(5)};
      final i = yilIstatistigi(ozet, yil: 2026, bugun: g(0));
      expect(i.planSayisi, 0);
      expect(i.oran, isNull);
    });
  });

  test('yoğunluk seviyeleri', () {
    expect(yogunluk(null), isNull);
    expect(yogunluk(const GunOzeti(iptal: 1)), isNull);
    expect(yogunluk(const GunOzeti(kalan: 3)), 0);
    expect(yogunluk(const GunOzeti(yapilan: 1, kalan: 4)), 1);
    expect(yogunluk(const GunOzeti(yapilan: 1, kalan: 2)), 2);
    expect(yogunluk(const GunOzeti(yapilan: 3, kalan: 4)), 3);
    expect(yogunluk(tam(2)), 4);
  });

  test('enCokErtelenenler sayaç sırasıyla döner', () async {
    sqfliteFfiInit();
    final db = await Veritabani.acFactory(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    final depo = PlanDeposu(db);
    Future<void> ekle(String b, int saat, int sayac) => depo.ekle(
      Plan(baslik: b, gun: g1, baslangicSaati: saat, yapilmadiSayisi: sayac),
    );
    await ekle('Az', 9, 1);
    await ekle('Hiç', 10, 0);
    await ekle('Çok', 11, 5);
    await ekle('Orta', 12, 3);
    await ekle('Biraz', 13, 2);

    final liste = await depo.enCokErtelenenler();
    expect(liste.map((p) => p.baslik), ['Çok', 'Orta', 'Biraz']);
    await db.close();
  });
}
