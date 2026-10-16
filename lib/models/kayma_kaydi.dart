import '../utils/tarih.dart';

/// Kapanan günde, yapılmadığı için kayan planın geride bıraktığı iz
/// (bkz. docs/SPEC.md §4 kural 6).
///
/// Gün görünümünde soluk olarak gösterilir:
/// `Kitap okuma — yapılmadı → Salı 13:00'e kaydı`
class KaymaKaydi {
  final int? id;

  /// Kayan planın kimliği (plan sonradan silinirse kayıt yine kalır).
  final int planId;

  /// Kayma anındaki başlık.
  final String baslik;

  /// Planın yapılmadığı gün ve slot.
  final DateTime gun;
  final int baslangicSaati;
  final int sure;

  /// Planın kaydığı gün ve saat.
  final DateTime yeniGun;
  final int yeniBaslangicSaati;

  KaymaKaydi({
    this.id,
    required this.planId,
    required this.baslik,
    required DateTime gun,
    required this.baslangicSaati,
    required this.sure,
    required DateTime yeniGun,
    required this.yeniBaslangicSaati,
  }) : gun = gunOf(gun),
       yeniGun = gunOf(yeniGun);

  /// `yapılmadı → Salı 13:00'e kaydı`
  String get aciklama =>
      'yapılmadı → ${gunAdi(yeniGun)} '
      '${saatMetni(yeniBaslangicSaati)}${saatYonelmeEki(yeniBaslangicSaati)} kaydı';

  Map<String, Object?> toMap() => {
    'id': id,
    'plan_id': planId,
    'baslik': baslik,
    'gun': gunAnahtari(gun),
    'baslangic_saati': baslangicSaati,
    'sure': sure,
    'yeni_gun': gunAnahtari(yeniGun),
    'yeni_baslangic_saati': yeniBaslangicSaati,
  };

  factory KaymaKaydi.fromMap(Map<String, Object?> m) => KaymaKaydi(
    id: m['id'] as int?,
    planId: m['plan_id'] as int,
    baslik: m['baslik'] as String,
    gun: gunAnahtarindan(m['gun'] as String),
    baslangicSaati: m['baslangic_saati'] as int,
    sure: m['sure'] as int,
    yeniGun: gunAnahtarindan(m['yeni_gun'] as String),
    yeniBaslangicSaati: m['yeni_baslangic_saati'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is KaymaKaydi &&
      other.id == id &&
      other.planId == planId &&
      other.baslik == baslik &&
      other.gun == gun &&
      other.baslangicSaati == baslangicSaati &&
      other.sure == sure &&
      other.yeniGun == yeniGun &&
      other.yeniBaslangicSaati == yeniBaslangicSaati;

  @override
  int get hashCode => Object.hash(
    id,
    planId,
    baslik,
    gun,
    baslangicSaati,
    sure,
    yeniGun,
    yeniBaslangicSaati,
  );
}
