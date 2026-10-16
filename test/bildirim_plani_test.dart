import 'package:flutter_test/flutter_test.dart';
import 'package:takvim_takip/logic/bildirim_plani.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  final bugun = DateTime.utc(2026, 10, 20); // Salı
  final yarin = gunEkle(bugun, 1);

  var sonId = 0;
  setUp(() => sonId = 0);

  Plan p(
    String baslik,
    DateTime gun,
    int saat, {
    int sure = 1,
    bool sabit = false,
    PlanDurumu durum = PlanDurumu.isaretsiz,
  }) => Plan(
    id: ++sonId,
    baslik: baslik,
    gun: gun,
    baslangicSaati: saat,
    sure: sure,
    sabit: sabit,
    durum: durum,
  );

  DateTime saat(int s, [int dk = 0, DateTime? gun]) {
    final g = gun ?? bugun;
    return DateTime(g.year, g.month, g.day, s, dk);
  }

  test('sabah özeti ve 5 dk önce hatırlatıcılar', () {
    final planlar = [
      p('Kitap', bugun, 13),
      p('Spor', bugun, 14, sabit: true),
      p('Ders', bugun, 15, sure: 2),
    ];
    final b = bildirimleriPlanla(
      simdi: saat(0, 1),
      planlar: planlar,
      sabahSaati: 9,
      dunOzeti: (yapilmayan: 1, kayan: 4),
    );

    expect(b.map((x) => x.zaman), [
      saat(9),
      saat(12, 55),
      saat(13, 55),
      saat(14, 55),
    ]);

    final sabah = b.first;
    expect(sabah.id, sabahBildirimiId);
    expect(
      sabah.govde,
      'Dün 1 plan yapılmadı, 4 plan kaydı.\n'
      'Bugün 3 planın var: 13:00 Kitap, 14:00 Spor, 15:00 Ders',
    );

    expect(b[1].baslik, 'Kitap');
    expect(b[1].govde, '5 dk sonra başlıyor · 13:00');
    expect(b[1].id, hatirlaticiId(1));
    expect(b[2].baslik, '📌 Spor');
    expect(b[3].govde, '5 dk sonra başlıyor · 15:00–17:00');
  });

  test('geçmiş zamanlar ve işaretli planlar kurulmaz', () {
    final planlar = [
      p('Sabah', bugun, 9),
      p('Yapildi', bugun, 15, durum: PlanDurumu.yapildi),
      p('Iptal', bugun, 16, durum: PlanDurumu.iptal),
      p('Bekleyen', bugun, 17),
    ];
    final b = bildirimleriPlanla(
      simdi: saat(10),
      planlar: planlar,
      sabahSaati: 9,
    );

    // 09:00 sabah özeti ve 08:55 hatırlatıcı geçti
    expect(b.map((x) => x.baslik), ['Bekleyen']);
  });

  test('yarının planları beklenir, sadece 00:00 planı bugün 23:55 kurulur', () {
    final b = bildirimleriPlanla(
      simdi: saat(20),
      planlar: [p('Gece', yarin, 0), p('Yarin', yarin, 9)],
      sabahSaati: 9,
    );
    expect(b.single.baslik, 'Gece');
    expect(b.single.zaman, saat(23, 55));
  });

  test('sabah metni varyasyonları', () {
    expect(
      sabahMetni((yapilmayan: 0, kayan: 0), const []),
      'Dün yapılmayan plan yok 👏\nBugün planın yok.',
    );
    expect(sabahMetni(null, const []), 'Bugün planın yok.');

    final cok = [for (var s = 8; s < 15; s++) p('P$s', bugun, s)];
    expect(
      sabahMetni(null, cok),
      'Bugün 7 planın var: 08:00 P8, 09:00 P9, 10:00 P10, 11:00 P11, '
      '12:00 P12, …',
    );
  });

  test('sabah özetinde iptal planlar yazılmaz', () {
    final b = bildirimleriPlanla(
      simdi: saat(7),
      planlar: [
        p('A', bugun, 10),
        p('B', bugun, 11, durum: PlanDurumu.iptal),
      ],
      sabahSaati: 8,
    );
    expect(b.first.govde, 'Bugün 1 planın var: 10:00 A');
  });
}
