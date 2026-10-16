import '../models/plan.dart';
import '../utils/tarih.dart';

/// Kurulacak tek bir bildirim (docs/SPEC.md §7).
class PlanlanmisBildirim {
  final int id;

  /// Telefonun yerel saatiyle gösterileceği an.
  final DateTime zaman;
  final String baslik;
  final String govde;

  const PlanlanmisBildirim({
    required this.id,
    required this.zaman,
    required this.baslik,
    required this.govde,
  });

  @override
  String toString() => 'Bildirim($id, $zaman, $baslik, $govde)';
}

/// Sabah bildirimi saatinin ayar anahtarı (Aşama 7'de ayarlar ekranından
/// değiştirilebilecek).
const sabahSaatiAyari = 'sabah_saati';
const varsayilanSabahSaati = 9;

/// Sabah özetinin sabit kimliği.
const sabahBildirimiId = 1;

/// Plan hatırlatıcısının kimliği: aynı plan için her zaman aynı.
int hatirlaticiId(int planId) => 1000 + planId;

/// Plan başlamadan kaç dakika önce hatırlatılır.
const hatirlatmaDakikasi = 5;

/// Bugün için kurulacak bildirimleri hesaplar.
///
/// - **Sabah özeti** ([sabahSaati]:00, henüz geçmediyse): dünün kapanış
///   özeti ve bugünün planları.
/// - **Hatırlatıcılar**: işaretsiz her plan için başlamasından 5 dk önce.
///   Yalnızca bugün içinde çalacak olanlar kurulur (yarının 00:00 planı için
///   bugün 23:55 dahil). Yarının planları gece yarısı kaydırmasından sonra
///   değişebileceği için gece yarısı görevi onları yeniden kurar.
///
/// [planlar] bugünün ve yarının planlarını içermelidir.
List<PlanlanmisBildirim> bildirimleriPlanla({
  required DateTime simdi,
  required List<Plan> planlar,
  required int sabahSaati,
  ({int yapilmayan, int kayan})? dunOzeti,
}) {
  final bugun = gunOf(simdi);
  final gece = DateTime(simdi.year, simdi.month, simdi.day + 1);
  final sonuc = <PlanlanmisBildirim>[];

  final sabah = DateTime(simdi.year, simdi.month, simdi.day, sabahSaati);
  if (sabah.isAfter(simdi)) {
    final bugunku =
        planlar
            .where((p) => p.gun == bugun && p.durum != PlanDurumu.iptal)
            .toList()
          ..sort((a, b) => a.baslangicSaati.compareTo(b.baslangicSaati));
    sonuc.add(
      PlanlanmisBildirim(
        id: sabahBildirimiId,
        zaman: sabah,
        baslik: 'Günaydın! 📅',
        govde: sabahMetni(dunOzeti, bugunku),
      ),
    );
  }

  for (final p in planlar) {
    if (p.id == null || p.durum != PlanDurumu.isaretsiz) continue;
    final baslangic = DateTime(
      p.gun.year,
      p.gun.month,
      p.gun.day,
      p.baslangicSaati,
    );
    final zaman = baslangic.subtract(
      const Duration(minutes: hatirlatmaDakikasi),
    );
    if (!zaman.isAfter(simdi) || !zaman.isBefore(gece)) continue;
    sonuc.add(
      PlanlanmisBildirim(
        id: hatirlaticiId(p.id!),
        zaman: zaman,
        baslik: '${p.sabit ? '📌 ' : ''}${p.baslik}',
        govde: '$hatirlatmaDakikasi dk sonra başlıyor · ${p.saatAraligi}',
      ),
    );
  }

  sonuc.sort((a, b) => a.zaman.compareTo(b.zaman));
  return sonuc;
}

/// Sabah özetinin metni:
/// `Dün 1 plan yapılmadı, 4 plan kaydı.\nBugün 3 planın var: 13:00 Kitap, ...`
String sabahMetni(
  ({int yapilmayan, int kayan})? dunOzeti,
  List<Plan> bugunkuPlanlar,
) {
  final satirlar = <String>[];
  if (dunOzeti != null) {
    satirlar.add(
      dunOzeti.yapilmayan == 0
          ? 'Dün yapılmayan plan yok 👏'
          : 'Dün ${dunOzeti.yapilmayan} plan yapılmadı, '
                '${dunOzeti.kayan} plan kaydı.',
    );
  }
  if (bugunkuPlanlar.isEmpty) {
    satirlar.add('Bugün planın yok.');
  } else {
    const enFazla = 5;
    final liste = bugunkuPlanlar
        .take(enFazla)
        .map((p) => '${saatMetni(p.baslangicSaati)} ${p.baslik}')
        .join(', ');
    final fazla = bugunkuPlanlar.length > enFazla ? ', …' : '';
    satirlar.add('Bugün ${bugunkuPlanlar.length} planın var: $liste$fazla');
  }
  return satirlar.join('\n');
}
