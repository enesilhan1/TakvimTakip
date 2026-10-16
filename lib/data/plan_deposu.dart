import 'package:sqflite/sqflite.dart';

import '../logic/kaydirma_motoru.dart';
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
  }

  Future<void> durumDegistir(int id, PlanDurumu durum) async {
    await _db.update(
      'planlar',
      {'durum': durum.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> sil(int id) async {
    await _db.delete('planlar', where: 'id = ?', whereArgs: [id]);
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
  }) {
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

  // ---------------------------------------------------------------- ayarlar

  Future<String?> ayarOku(String anahtar) async {
    final satirlar = await _db.query(
      'ayarlar',
      where: 'anahtar = ?',
      whereArgs: [anahtar],
    );
    return satirlar.isEmpty ? null : satirlar.first['deger'] as String;
  }

  Future<void> ayarYaz(String anahtar, String deger) async {
    await _db.insert('ayarlar', {
      'anahtar': anahtar,
      'deger': deger,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
