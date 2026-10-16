import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../logic/kaydirma_motoru.dart';
import '../logic/yedek.dart';
import '../models/kayma_kaydi.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';

/// Eklenen veya düzenlenen plan aynı gün başka bir planla çakışırsa atılır.
class PlanCakismaHatasi implements Exception {
  final Plan cakisan;

  PlanCakismaHatasi(this.cakisan);

  @override
  String toString() =>
      'Bu saat aralığında zaten bir plan var: '
      '${cakisan.saatAraligi} ${cakisan.baslik}';
}

/// Planların, kayma kayıtlarının ve ayarların veritabanı işlemleri.
///
/// Uygulamanın geri kalanı veritabanına doğrudan değil, bu sınıf üzerinden
/// erişir.
class PlanDeposu {
  final Database _db;

  PlanDeposu(this._db);

  final _degisiklik = StreamController<void>.broadcast();

  /// Planlar her eklendiğinde, değiştiğinde, silindiğinde ya da kaydığında
  /// bir olay yayar (bildirimler yeniden kurulsun diye).
  Stream<void> get degisiklikler => _degisiklik.stream;

  // ---------------------------------------------------------------- planlar

  /// [gun]ün planları, saat sırasıyla.
  Future<List<Plan>> gununPlanlari(DateTime gun) => araliktakiPlanlar(gun, gun);

  /// [baslangic] ile [bitis] günleri arasındaki (ikisi dahil) planlar,
  /// gün ve saat sırasıyla. Haftalık/aylık görünümler için.
  Future<List<Plan>> araliktakiPlanlar(
    DateTime baslangic,
    DateTime bitis,
  ) async {
    final satirlar = await _db.query(
      'planlar',
      where: 'gun >= ? AND gun <= ?',
      whereArgs: [gunAnahtari(baslangic), gunAnahtari(bitis)],
      orderBy: 'gun, baslangic_saati',
    );
    return satirlar.map(Plan.fromMap).toList();
  }

  /// [gun] ve sonrasındaki tüm planlar, gün ve saat sırasıyla.
  /// Kaydırma motoru "bant"ı bundan kurar.
  Future<List<Plan>> gundenItibarenPlanlar(DateTime gun) async {
    final satirlar = await _db.query(
      'planlar',
      where: 'gun >= ?',
      whereArgs: [gunAnahtari(gun)],
      orderBy: 'gun, baslangic_saati',
    );
    return satirlar.map(Plan.fromMap).toList();
  }

  /// En çok yapılmayıp ertelenen planlar (sayaç sırasıyla, en fazla [limit]).
  Future<List<Plan>> enCokErtelenenler({int limit = 3}) async {
    final satirlar = await _db.query(
      'planlar',
      where: 'yapilmadi_sayisi > 0',
      orderBy: 'yapilmadi_sayisi DESC, gun, baslangic_saati',
      limit: limit,
    );
    return satirlar.map(Plan.fromMap).toList();
  }

  Future<Plan?> planGetir(int id) async {
    final satirlar = await _db.query(
      'planlar',
      where: 'id = ?',
      whereArgs: [id],
    );
    return satirlar.isEmpty ? null : Plan.fromMap(satirlar.first);
  }

  /// Yeni plan ekler ve kimliği atanmış halini döndürür.
  /// Aynı gün çakışan plan varsa [PlanCakismaHatasi] atar.
  Future<Plan> ekle(Plan plan) async {
    await _cakismaKontrol(plan);
    final map = plan.toMap()..remove('id');
    final id = await _db.insert('planlar', map);
    _degisiklik.add(null);
    return plan.copyWith(id: id);
  }

  /// Var olan planı günceller (gün/saat değişikliği dahil).
  /// Aynı gün başka bir planla çakışırsa [PlanCakismaHatasi] atar.
  Future<void> guncelle(Plan plan) async {
    final id = plan.id;
    if (id == null) throw ArgumentError('Kaydedilmemiş plan güncellenemez.');
    await _cakismaKontrol(plan);
    await _db.update(
      'planlar',
      plan.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
    _degisiklik.add(null);
  }

  Future<void> durumDegistir(int id, PlanDurumu durum) async {
    await _db.update(
      'planlar',
      {'durum': durum.name},
      where: 'id = ?',
      whereArgs: [id],
    );
    _degisiklik.add(null);
  }

  Future<void> sil(int id) async {
    await _db.delete('planlar', where: 'id = ?', whereArgs: [id]);
    _degisiklik.add(null);
  }

  Future<void> _cakismaKontrol(Plan plan) async {
    for (final diger in await gununPlanlari(plan.gun)) {
      if (diger.id != plan.id && diger.cakisir(plan)) {
        throw PlanCakismaHatasi(diger);
      }
    }
  }

  // -------------------------------------------------------- kayma kayıtları

  /// [gun]de yapılmadığı için kayan planların izleri, saat sırasıyla.
  Future<List<KaymaKaydi>> gununKaymaKayitlari(DateTime gun) async {
    final satirlar = await _db.query(
      'kayma_kayitlari',
      where: 'gun = ?',
      whereArgs: [gunAnahtari(gun)],
      orderBy: 'baslangic_saati',
    );
    return satirlar.map(KaymaKaydi.fromMap).toList();
  }

  /// [baslangic] ile [bitis] günleri arasındaki (ikisi dahil) kayma kayıtları.
  Future<List<KaymaKaydi>> araliktakiKaymaKayitlari(
    DateTime baslangic,
    DateTime bitis,
  ) async {
    final satirlar = await _db.query(
      'kayma_kayitlari',
      where: 'gun >= ? AND gun <= ?',
      whereArgs: [gunAnahtari(baslangic), gunAnahtari(bitis)],
      orderBy: 'gun, baslangic_saati',
    );
    return satirlar.map(KaymaKaydi.fromMap).toList();
  }

  Future<KaymaKaydi> kaymaKaydiEkle(KaymaKaydi kayit) async {
    final map = kayit.toMap()..remove('id');
    final id = await _db.insert('kayma_kayitlari', map);
    return KaymaKaydi.fromMap({...map, 'id': id});
  }

  // --------------------------------------------------------------- kaydırma

  /// [gun]ü kapatır: kaydırmayı hesaplar ve sonucu yazar (docs/SPEC.md §4).
  ///
  /// Hepsi tek bir **özel** (exclusive) işlemde yapılır: kontrol, okuma,
  /// hesaplama ve yazma arasında başka hiçbir bağlantı veritabanına
  /// yazamaz. Gece yarısı arka plan görevi ile açılan uygulama aynı anda
  /// çalışsa bile gün iki kez kaydırılmaz:
  /// [sonGunAyari] hâlâ bir önceki günü göstermiyorsa (gün zaten
  /// kapatılmışsa ya da sıra atlanıyorsa) hiçbir şey yapmaz ve `null` döner.
  ///
  /// Yarıda kesilirse hiçbiri yazılmaz; planlar yarım kaymış halde kalmaz.
  Future<KaydirmaSonucu?> gunuKapatIslemi(
    DateTime gun, {
    required String sonGunAyari,
  }) async {
    final sonuc = await _gunuKapat(gun, sonGunAyari);
    if (sonuc != null && !sonuc.bos) _degisiklik.add(null);
    return sonuc;
  }

  Future<KaydirmaSonucu?> _gunuKapat(DateTime gun, String sonGunAyari) {
    return _db.transaction((txn) async {
      final kayitli = await txn.query(
        'ayarlar',
        where: 'anahtar = ?',
        whereArgs: [sonGunAyari],
      );
      if (kayitli.isEmpty ||
          kayitli.first['deger'] != gunAnahtari(gunEkle(gun, -1))) {
        return null;
      }

      final satirlar = await txn.query(
        'planlar',
        where: 'gun >= ?',
        whereArgs: [gunAnahtari(gun)],
      );
      final sonuc = gunuKapat(gun, satirlar.map(Plan.fromMap).toList());

      for (final plan in sonuc.degisenPlanlar) {
        await txn.update(
          'planlar',
          plan.toMap()..remove('id'),
          where: 'id = ?',
          whereArgs: [plan.id],
        );
      }
      for (final kayit in sonuc.kaymaKayitlari) {
        await txn.insert('kayma_kayitlari', kayit.toMap()..remove('id'));
      }
      Future<void> ayar(String anahtar, String deger) => txn.insert('ayarlar', {
        'anahtar': anahtar,
        'deger': deger,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await ayar(sonGunAyari, gunAnahtari(gun));
      // Sabah bildirimindeki "Dün 1 plan yapılmadı, 4 plan kaydı" için.
      await ayar(
        _kapanisOzetiAyari(gun),
        '${sonuc.yapilmayanSayisi};${sonuc.kayanSayisi}',
      );
      return sonuc;
    }, exclusive: true);
  }

  static String _kapanisOzetiAyari(DateTime gun) =>
      'kapanis_ozeti_${gunAnahtari(gun)}';

  /// [gun] kapanırken kaç planın yapılmadığı ve toplam kaç planın kaydığı.
  /// Gün henüz kapanmadıysa `null`.
  Future<({int yapilmayan, int kayan})?> kapanisOzeti(DateTime gun) async {
    final deger = await ayarOku(_kapanisOzetiAyari(gun));
    if (deger == null) return null;
    final p = deger.split(';');
    return (yapilmayan: int.parse(p[0]), kayan: int.parse(p[1]));
  }

  // ------------------------------------------------------------- yedekleme

  /// Bütün verinin anlık görüntüsü (docs/SPEC.md §8).
  Future<Yedek> yedekAl(DateTime simdi) async {
    return _db.transaction((txn) async {
      final planlar = await txn.query('planlar', orderBy: 'id');
      final kayitlar = await txn.query('kayma_kayitlari', orderBy: 'id');
      final ayarlar = await txn.query('ayarlar', orderBy: 'anahtar');
      return Yedek(
        olusturma: simdi,
        planlar: planlar.map(Plan.fromMap).toList(),
        kaymaKayitlari: kayitlar.map(KaymaKaydi.fromMap).toList(),
        ayarlar: {
          for (final a in ayarlar) a['anahtar'] as String: a['deger'] as String,
        },
      );
    });
  }

  /// Mevcut bütün veriyi silip [yedek]tekiyle değiştirir. Tek bir işlemde
  /// yapılır: yarıda kesilirse eski veriler olduğu gibi kalır.
  Future<void> yedektenYukle(Yedek yedek) async {
    await _db.transaction((txn) async {
      await txn.delete('planlar');
      await txn.delete('kayma_kayitlari');
      await txn.delete('ayarlar');
      // Kimlikler korunur: kayma kayıtları planlara kimlikle bağlı.
      for (final p in yedek.planlar) {
        await txn.insert('planlar', p.toMap());
      }
      for (final k in yedek.kaymaKayitlari) {
        await txn.insert('kayma_kayitlari', k.toMap());
      }
      for (final a in yedek.ayarlar.entries) {
        await txn.insert('ayarlar', {'anahtar': a.key, 'deger': a.value});
      }
    }, exclusive: true);
    _degisiklik.add(null);
  }

  // ---------------------------------------------------------------- ayarlar

  Future<String?> ayarOku(String anahtar) async {
    final satirlar = await _db.query(
      'ayarlar',
      where: 'anahtar = ?',
      whereArgs: [anahtar],
    );
    return satirlar.isEmpty ? null : satirlar.first['deger'] as String;
  }

  /// Ayarı yazar. Sabah bildirimi saati gibi ayarlar bildirimleri
  /// etkilediği için değişiklik olayı da yayılır.
  Future<void> ayarYaz(String anahtar, String deger) async {
    await _db.insert('ayarlar', {
      'anahtar': anahtar,
      'deger': deger,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _degisiklik.add(null);
  }
}
