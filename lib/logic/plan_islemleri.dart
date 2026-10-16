import '../models/plan.dart';
import '../utils/tarih.dart';

/// Claude'un önerdiği tek bir plan değişikliği (docs/SPEC.md §9).
///
/// Claude bu işlemleri `degisiklik_oner` aracıyla JSON olarak gönderir;
/// uygulama önce doğrular ve önizleme gösterir, kullanıcı onaylarsa uygular.
sealed class PlanIslemi {
  const PlanIslemi();

  /// Claude'un aracından gelen tek bir işlem nesnesini çözer.
  /// Eksik ya da hatalı alan varsa [IslemHatasi] atar.
  factory PlanIslemi.jsondan(Map<String, dynamic> m) {
    final tur = m['tur'];
    switch (tur) {
      case 'ekle':
        return Ekle(
          baslik: _metin(m, 'baslik', zorunlu: true)!,
          not: _metin(m, 'not') ?? '',
          gun: _gun(m, 'gun', zorunlu: true)!,
          baslangicSaati: _tamsayi(m, 'baslangic_saati', zorunlu: true)!,
          sure: _tamsayi(m, 'sure') ?? 1,
          sabit: _mantiksal(m, 'sabit') ?? false,
        );
      case 'guncelle':
        return Guncelle(
          planId: _tamsayi(m, 'plan_id', zorunlu: true)!,
          baslik: _metin(m, 'baslik'),
          not: _metin(m, 'not'),
          gun: _gun(m, 'gun'),
          baslangicSaati: _tamsayi(m, 'baslangic_saati'),
          sure: _tamsayi(m, 'sure'),
          sabit: _mantiksal(m, 'sabit'),
        );
      case 'sil':
        return Sil(planId: _tamsayi(m, 'plan_id', zorunlu: true)!);
      case 'durum':
        final d = _metin(m, 'durum', zorunlu: true)!;
        final durum = PlanDurumu.values.where((x) => x.name == d).firstOrNull;
        if (durum == null) {
          throw IslemHatasi(
            'Geçersiz durum "$d" (isaretsiz, yapildi ya da iptal olmalı).',
          );
        }
        return DurumDegistir(
          planId: _tamsayi(m, 'plan_id', zorunlu: true)!,
          durum: durum,
        );
      default:
        throw IslemHatasi(
          'Bilinmeyen işlem türü "$tur" (ekle, guncelle, sil ya da durum).',
        );
    }
  }
}

class Ekle extends PlanIslemi {
  final String baslik;
  final String not;
  final DateTime gun;
  final int baslangicSaati;
  final int sure;
  final bool sabit;

  const Ekle({
    required this.baslik,
    this.not = '',
    required this.gun,
    required this.baslangicSaati,
    this.sure = 1,
    this.sabit = false,
  });
}

/// Verilmeyen alanlar değişmez.
class Guncelle extends PlanIslemi {
  final int planId;
  final String? baslik;
  final String? not;
  final DateTime? gun;
  final int? baslangicSaati;
  final int? sure;
  final bool? sabit;

  const Guncelle({
    required this.planId,
    this.baslik,
    this.not,
    this.gun,
    this.baslangicSaati,
    this.sure,
    this.sabit,
  });
}

class Sil extends PlanIslemi {
  final int planId;

  const Sil({required this.planId});
}

class DurumDegistir extends PlanIslemi {
  final int planId;
  final PlanDurumu durum;

  const DurumDegistir({required this.planId, required this.durum});
}

/// Bir işlem çözülemez ya da uygulanamazsa. Mesaj hem kullanıcıya hem
/// Claude'a gösterilir (Claude düzeltip yeniden önerebilsin).
class IslemHatasi implements Exception {
  final String mesaj;

  IslemHatasi(this.mesaj);

  @override
  String toString() => mesaj;
}

/// Doğrulanmış, uygulanmaya hazır değişiklik seti.
class DegisiklikPlani {
  final List<Plan> eklenecek;
  final List<Plan> guncellenecek;
  final List<int> silinecek;

  /// Önizleme satırları, işlem sırasıyla:
  /// `➕ Salı 21 Ekim 14:00–16:00 Ders`
  final List<String> onizleme;

  const DegisiklikPlani({
    required this.eklenecek,
    required this.guncellenecek,
    required this.silinecek,
    required this.onizleme,
  });

  bool get bos =>
      eklenecek.isEmpty && guncellenecek.isEmpty && silinecek.isEmpty;
}

/// İşlemleri sırayla, mevcut planların bir kopyası üzerinde dener; kurallara
/// uymayan bir şey varsa (geçmiş gün, çakışma, olmayan plan...) hiçbir şey
/// uygulanmadan [IslemHatasi] atar. Böylece öneri ya tamamen uygulanır ya hiç.
///
/// [mevcut] işlemlerin dokunduğu bütün günlerin planlarını içermelidir
/// (bkz. [etkilenenGunler]).
DegisiklikPlani islemleriDogrula(
  List<PlanIslemi> islemler,
  List<Plan> mevcut, {
  required DateTime bugun,
}) {
  if (islemler.isEmpty) throw IslemHatasi('Önerilecek işlem yok.');

  final planlar = {for (final p in mevcut) p.id!: p};
  final orijinal = Map.of(planlar);
  final eklenen = <Plan>[];
  final silinen = <int>{};
  final satirlar = <String>[];

  Plan bul(int id) {
    final p = planlar[id];
    if (p == null) throw IslemHatasi('$id numaralı plan bulunamadı.');
    return p;
  }

  void gecmisKontrol(DateTime gun, String ne) {
    if (gun.isBefore(bugun)) {
      throw IslemHatasi(
        '$ne: geçmiş bir güne (${uzunTarih(gun)}) plan '
        'eklenemez ya da taşınamaz.',
      );
    }
  }

  Plan olustur(
    String ne, {
    int? id,
    required String baslik,
    required String not,
    required DateTime gun,
    required int baslangicSaati,
    required int sure,
    required bool sabit,
    PlanDurumu durum = PlanDurumu.isaretsiz,
    int yapilmadiSayisi = 0,
  }) {
    try {
      return Plan(
        id: id,
        baslik: baslik,
        not: not,
        gun: gun,
        baslangicSaati: baslangicSaati,
        sure: sure,
        sabit: sabit,
        durum: durum,
        yapilmadiSayisi: yapilmadiSayisi,
      );
    } on ArgumentError catch (e) {
      throw IslemHatasi('$ne: ${e.message}');
    }
  }

  for (final islem in islemler) {
    switch (islem) {
      case Ekle():
        gecmisKontrol(islem.gun, 'Ekleme "${islem.baslik}"');
        final p = olustur(
          'Ekleme "${islem.baslik}"',
          baslik: islem.baslik,
          not: islem.not,
          gun: islem.gun,
          baslangicSaati: islem.baslangicSaati,
          sure: islem.sure,
          sabit: islem.sabit,
        );
        eklenen.add(p);
        satirlar.add('➕ ${_planMetni(p)}');

      case Guncelle():
        final eski = bul(islem.planId);
        final yerDegisiyor =
            islem.gun != null ||
            islem.baslangicSaati != null ||
            islem.sure != null;
        if (eski.gun.isBefore(bugun)) {
          throw IslemHatasi(
            '"${eski.baslik}" geçmiş bir günde, '
            'sadece durumu değiştirilebilir.',
          );
        }
        if (yerDegisiyor) {
          gecmisKontrol(islem.gun ?? eski.gun, '"${eski.baslik}" taşıma');
        }
        final yeni = olustur(
          '"${eski.baslik}" düzenleme',
          id: eski.id,
          baslik: islem.baslik ?? eski.baslik,
          not: islem.not ?? eski.not,
          gun: islem.gun ?? eski.gun,
          baslangicSaati: islem.baslangicSaati ?? eski.baslangicSaati,
          sure: islem.sure ?? eski.sure,
          sabit: islem.sabit ?? eski.sabit,
          durum: eski.durum,
          yapilmadiSayisi: eski.yapilmadiSayisi,
        );
        planlar[eski.id!] = yeni;
        satirlar.add('✏️ ${_degisiklikMetni(eski, yeni)}');

      case Sil():
        final p = bul(islem.planId);
        planlar.remove(islem.planId);
        silinen.add(islem.planId);
        satirlar.add('🗑 Sil: ${_planMetni(p)}');

      case DurumDegistir():
        final p = bul(islem.planId);
        final gecmis = p.gun.isBefore(bugun);
        if (islem.durum == PlanDurumu.isaretsiz &&
            gecmis &&
            !p.sabit &&
            p.durum != PlanDurumu.isaretsiz) {
          throw IslemHatasi(
            '"${p.baslik}" geçmiş bir günde ve sabit değil; '
            'işareti kaldırılırsa takılı kalır.',
          );
        }
        planlar[p.id!] = p.copyWith(durum: islem.durum);
        satirlar.add(
          '${_durumIkonu(islem.durum)} ${p.baslik}: '
          '${_durumAdi(islem.durum)}',
        );
    }
  }

  // Sonuçta aynı günde çakışan plan kalmamalı.
  final son = [...planlar.values, ...eklenen];
  for (var i = 0; i < son.length; i++) {
    for (var j = i + 1; j < son.length; j++) {
      if (son[i].cakisir(son[j])) {
        throw IslemHatasi(
          'Çakışma: ${_planMetni(son[i])} ile '
          '${_planMetni(son[j])} aynı saatte.',
        );
      }
    }
  }

  return DegisiklikPlani(
    eklenecek: eklenen,
    guncellenecek: [
      for (final p in planlar.values)
        if (orijinal[p.id] != p) p,
    ],
    silinecek: silinen.toList(),
    onizleme: satirlar,
  );
}

/// İşlemlerin dokunduğu günler: çakışma kontrolü için bu günlerin bütün
/// planları [islemleriDogrula]'ya verilmelidir. Plan kimliğiyle gelen
/// işlemlerin günü önceden bilinmediği için [planGunu] ile sorulur.
Set<DateTime> etkilenenGunler(
  List<PlanIslemi> islemler,
  DateTime? Function(int planId) planGunu,
) {
  final gunler = <DateTime>{};
  void ekleId(int id) {
    final g = planGunu(id);
    if (g != null) gunler.add(g);
  }

  for (final i in islemler) {
    switch (i) {
      case Ekle():
        gunler.add(i.gun);
      case Guncelle():
        ekleId(i.planId);
        if (i.gun != null) gunler.add(i.gun!);
      case Sil():
        ekleId(i.planId);
      case DurumDegistir():
        ekleId(i.planId);
    }
  }
  return gunler;
}

String _planMetni(Plan p) =>
    '${gunAdi(p.gun)} ${p.gun.day} ${ayAdlari[p.gun.month - 1]} '
    '${p.saatAraligi} ${p.sabit ? '📌' : ''}${p.baslik}'
    '${p.not.isEmpty ? '' : ' (${p.not})'}';

String _degisiklikMetni(Plan eski, Plan yeni) {
  final parcalar = <String>[];
  if (eski.gun != yeni.gun ||
      eski.baslangicSaati != yeni.baslangicSaati ||
      eski.sure != yeni.sure) {
    parcalar.add(
      '${gunAdi(eski.gun)} ${eski.saatAraligi} → '
      '${gunAdi(yeni.gun)} ${yeni.gun.day} ${ayAdlari[yeni.gun.month - 1]} '
      '${yeni.saatAraligi}',
    );
  }
  if (eski.baslik != yeni.baslik) parcalar.add('başlık: "${yeni.baslik}"');
  if (eski.not != yeni.not) {
    parcalar.add(yeni.not.isEmpty ? 'not silindi' : 'not: "${yeni.not}"');
  }
  if (eski.sabit != yeni.sabit) {
    parcalar.add(yeni.sabit ? '📌 sabit yapıldı' : 'sabitlik kaldırıldı');
  }
  return '${eski.baslik}: ${parcalar.isEmpty ? 'değişiklik yok' : parcalar.join(', ')}';
}

String _durumAdi(PlanDurumu d) => switch (d) {
  PlanDurumu.yapildi => 'yapıldı',
  PlanDurumu.iptal => 'iptal (kaymaz)',
  PlanDurumu.isaretsiz => 'işaret kaldırıldı',
};

String _durumIkonu(PlanDurumu d) => switch (d) {
  PlanDurumu.yapildi => '✅',
  PlanDurumu.iptal => '🚫',
  PlanDurumu.isaretsiz => '↩️',
};

String? _metin(Map<String, dynamic> m, String alan, {bool zorunlu = false}) {
  final v = m[alan];
  if (v == null) {
    if (zorunlu) throw IslemHatasi('"$alan" alanı eksik.');
    return null;
  }
  if (v is! String) throw IslemHatasi('"$alan" metin olmalı.');
  return v.trim();
}

int? _tamsayi(Map<String, dynamic> m, String alan, {bool zorunlu = false}) {
  final v = m[alan];
  if (v == null) {
    if (zorunlu) throw IslemHatasi('"$alan" alanı eksik.');
    return null;
  }
  if (v is int) return v;
  if (v is double && v == v.roundToDouble()) return v.toInt();
  throw IslemHatasi('"$alan" tam sayı olmalı.');
}

bool? _mantiksal(Map<String, dynamic> m, String alan) {
  final v = m[alan];
  if (v == null) return null;
  if (v is! bool) throw IslemHatasi('"$alan" true ya da false olmalı.');
  return v;
}

DateTime? _gun(Map<String, dynamic> m, String alan, {bool zorunlu = false}) {
  final v = _metin(m, alan, zorunlu: zorunlu);
  if (v == null) return null;
  return tarihCoz(v, alan);
}

/// `2026-10-20` biçimindeki metni güne çevirir; değilse [IslemHatasi].
DateTime tarihCoz(String v, String alan) {
  final eslesme = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  if (eslesme == null) {
    throw IslemHatasi('"$alan" YYYY-AA-GG biçiminde olmalı ("$v").');
  }
  final g = DateTime.utc(
    int.parse(eslesme[1]!),
    int.parse(eslesme[2]!),
    int.parse(eslesme[3]!),
  );
  if (gunAnahtari(g) != v) throw IslemHatasi('Geçersiz tarih "$v".');
  return g;
}
