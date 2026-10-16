import '../utils/tarih.dart';

/// Bir planın işaretlenme durumu (bkz. docs/SPEC.md §3).
enum PlanDurumu {
  /// Henüz işaretlenmedi. Sabit değilse gün sonunda kayar.
  isaretsiz,

  /// Yapıldı. Yerinde kalır.
  yapildi,

  /// Yapılmayacak ama ertelenmesin de. Kaymaz, kimseyi itmez.
  iptal,
}

/// Bir güne ait saatlik plan.
///
/// Plan tam saatte başlar ve tam saat sürer. Kapladığı saat aralığı
/// [baslangicSaati] ile [bitisSaati] arasıdır (bitiş hariç), buna **slot**
/// denir. Plan gece yarısını geçemez.
class Plan {
  /// Veritabanı kimliği. Henüz kaydedilmemiş plan için `null`.
  final int? id;

  final String baslik;
  final String not;

  /// Planın günü (saatsiz, bkz. [gunOf]).
  final DateTime gun;

  /// 0–23 arası başlangıç saati.
  final int baslangicSaati;

  /// Saat cinsinden süre (en az 1).
  final int sure;

  /// 📌 Sabit plan hiçbir zaman kaymaz.
  final bool sabit;

  final PlanDurumu durum;

  /// Plan kaç kez yapılmadan ertesi güne kaydı.
  final int yapilmadiSayisi;

  Plan({
    this.id,
    required this.baslik,
    this.not = '',
    required DateTime gun,
    required this.baslangicSaati,
    this.sure = 1,
    this.sabit = false,
    this.durum = PlanDurumu.isaretsiz,
    this.yapilmadiSayisi = 0,
  }) : gun = gunOf(gun) {
    if (baslik.trim().isEmpty) {
      throw ArgumentError('Plan başlığı boş olamaz.');
    }
    if (baslangicSaati < 0 || baslangicSaati > 23) {
      throw ArgumentError('Başlangıç saati 0–23 arasında olmalı.');
    }
    if (sure < 1 || baslangicSaati + sure > 24) {
      throw ArgumentError(
        'Plan en az 1 saat sürmeli ve gece yarısını geçmemeli.',
      );
    }
  }

  /// Planın bittiği saat (dahil değil). 13:00–15:00 planı için 15.
  int get bitisSaati => baslangicSaati + sure;

  /// Gün sonunda kayacak mı? (sabit değil ve işaretsiz)
  bool get kayabilir => !sabit && durum == PlanDurumu.isaretsiz;

  /// Aynı gün ve saat aralıkları kesişiyorsa `true`.
  bool cakisir(Plan diger) =>
      gun == diger.gun &&
      baslangicSaati < diger.bitisSaati &&
      diger.baslangicSaati < bitisSaati;

  /// `13:00` veya `13:00–15:00`.
  String get saatAraligi => sure == 1
      ? saatMetni(baslangicSaati)
      : '${saatMetni(baslangicSaati)}–${saatMetni(bitisSaati)}';

  Plan copyWith({
    int? id,
    String? baslik,
    String? not,
    DateTime? gun,
    int? baslangicSaati,
    int? sure,
    bool? sabit,
    PlanDurumu? durum,
    int? yapilmadiSayisi,
  }) {
    return Plan(
      id: id ?? this.id,
      baslik: baslik ?? this.baslik,
      not: not ?? this.not,
      gun: gun ?? this.gun,
      baslangicSaati: baslangicSaati ?? this.baslangicSaati,
      sure: sure ?? this.sure,
      sabit: sabit ?? this.sabit,
      durum: durum ?? this.durum,
      yapilmadiSayisi: yapilmadiSayisi ?? this.yapilmadiSayisi,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'baslik': baslik,
    'not_metni': not,
    'gun': gunAnahtari(gun),
    'baslangic_saati': baslangicSaati,
    'sure': sure,
    'sabit': sabit ? 1 : 0,
    'durum': durum.name,
    'yapilmadi_sayisi': yapilmadiSayisi,
  };

  factory Plan.fromMap(Map<String, Object?> m) => Plan(
    id: m['id'] as int?,
    baslik: m['baslik'] as String,
    not: (m['not_metni'] as String?) ?? '',
    gun: gunAnahtarindan(m['gun'] as String),
    baslangicSaati: m['baslangic_saati'] as int,
    sure: m['sure'] as int,
    sabit: (m['sabit'] as int) == 1,
    durum: PlanDurumu.values.byName(m['durum'] as String),
    yapilmadiSayisi: m['yapilmadi_sayisi'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is Plan &&
      other.id == id &&
      other.baslik == baslik &&
      other.not == not &&
      other.gun == gun &&
      other.baslangicSaati == baslangicSaati &&
      other.sure == sure &&
      other.sabit == sabit &&
      other.durum == durum &&
      other.yapilmadiSayisi == yapilmadiSayisi;

  @override
  int get hashCode => Object.hash(
    id,
    baslik,
    not,
    gun,
    baslangicSaati,
    sure,
    sabit,
    durum,
    yapilmadiSayisi,
  );

  @override
  String toString() =>
      'Plan(${gunAnahtari(gun)} $saatAraligi $baslik${sabit ? ' 📌' : ''} '
      '${durum.name})';
}
