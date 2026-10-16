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

  Future<KaymaKaydi> kaymaKaydiEkle(KaymaKaydi kayit) async {
    final map = kayit.toMap()..remove('id');
    final id = await _db.insert('kayma_kayitlari', map);
    return KaymaKaydi.fromMap({...map, 'id': id});
  }

  // --------------------------------------------------------------- kaydırma

  /// Bir gün kapanışının sonucunu tek bir işlemde (transaction) yazar:
  /// planların yeni yerleri, kayma kayıtları ve verilen ayarlar. Yarıda
  /// kesilirse hiçbiri yazılmaz, planlar yarım kaymış halde kalmaz.
  Future<void> kaydirmaKaydet(
    KaydirmaSonucu sonuc, {
    Map<String, String> ayarlar = const {},
  }) async {
    await _db.transaction((txn) async {
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
      for (final a in ayarlar.entries) {
        await txn.insert('ayarlar', {
          'anahtar': a.key,
          'deger': a.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
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
