import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Yerel SQLite veritabanının şeması ve açılışı.
///
/// Şema değişirse [surum] artırılır ve [_yukselt] içine geçiş adımı eklenir;
/// böylece telefondaki mevcut veriler silinmeden yeni şemaya taşınır.
class Veritabani {
  static const surum = 1;
  static const dosyaAdi = 'takvim_takip.db';

  /// Telefondaki veritabanını açar (yoksa oluşturur).
  ///
  /// [ayriBaglanti]: arka plan görevi (gece yarısı kaydırması) uygulamayla
  /// aynı bağlantıyı paylaşmasın diye kendi bağlantısını açar; aynı anda
  /// çalışırlarsa SQLite kilidi işlemleri sıraya koyar.
  static Future<Database> ac({bool ayriBaglanti = false}) async {
    final klasor = await getDatabasesPath();
    return acFactory(
      databaseFactory,
      p.join(klasor, dosyaAdi),
      tekOrnek: !ayriBaglanti,
    );
  }

  /// Belirli bir factory ve yol ile açar. Testlerde bellek içi veritabanı
  /// için kullanılır.
  static Future<Database> acFactory(
    DatabaseFactory factory,
    String yol, {
    bool tekOrnek = true,
  }) {
    return factory.openDatabase(
      yol,
      options: OpenDatabaseOptions(
        version: surum,
        onCreate: _olustur,
        onUpgrade: _yukselt,
        singleInstance: tekOrnek,
      ),
    );
  }

  static Future<void> _olustur(Database db, int surum) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE planlar (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        baslik           TEXT    NOT NULL,
        not_metni        TEXT    NOT NULL DEFAULT '',
        gun              TEXT    NOT NULL,
        baslangic_saati  INTEGER NOT NULL CHECK (baslangic_saati BETWEEN 0 AND 23),
        sure             INTEGER NOT NULL CHECK (sure >= 1 AND baslangic_saati + sure <= 24),
        sabit            INTEGER NOT NULL DEFAULT 0,
        durum            TEXT    NOT NULL DEFAULT 'isaretsiz',
        yapilmadi_sayisi INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_planlar_gun ON planlar (gun, baslangic_saati)',
    );

    batch.execute('''
      CREATE TABLE kayma_kayitlari (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id              INTEGER NOT NULL,
        baslik               TEXT    NOT NULL,
        gun                  TEXT    NOT NULL,
        baslangic_saati      INTEGER NOT NULL,
        sure                 INTEGER NOT NULL,
        yeni_gun             TEXT    NOT NULL,
        yeni_baslangic_saati INTEGER NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_kayma_gun ON kayma_kayitlari (gun, baslangic_saati)',
    );

    // Anahtar–değer ayarlar: son işlenen gün, sabah bildirimi saati vb.
    batch.execute('''
      CREATE TABLE ayarlar (
        anahtar TEXT PRIMARY KEY,
        deger   TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
  }

  static Future<void> _yukselt(Database db, int eski, int yeni) async {
    // Henüz geçiş yok (sürüm 1).
  }
}
