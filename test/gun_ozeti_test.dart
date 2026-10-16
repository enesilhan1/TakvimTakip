import 'package:flutter_test/flutter_test.dart';
import 'package:takvim_takip/logic/gun_ozeti.dart';
import 'package:takvim_takip/models/kayma_kaydi.dart';
import 'package:takvim_takip/models/plan.dart';
import 'package:takvim_takip/utils/tarih.dart';

void main() {
  final pzt = DateTime.utc(2026, 10, 19);
  final sali = gunEkle(pzt, 1);

  group('hafta/ay yardımcıları', () {
    test('haftaBasi pazartesiyi bulur', () {
      expect(haftaBasi(pzt), pzt);
      expect(haftaBasi(DateTime.utc(2026, 10, 25)), pzt); // pazar
      expect(haftaBasi(DateTime.utc(2026, 11, 1)), DateTime.utc(2026, 10, 26));
    });

    test('ay başı ve gün sayısı', () {
      expect(ayBasi(pzt), DateTime.utc(2026, 10, 1));
      expect(aydakiGunSayisi(pzt), 31);
      expect(aydakiGunSayisi(DateTime.utc(2028, 2, 10)), 29);
      expect(aydakiGunSayisi(DateTime.utc(2026, 2, 10)), 28);
    });

    test('hafta aralığı metni', () {
      expect(haftaAraligiMetni(pzt), '19–25 Ekim 2026');
      expect(
        haftaAraligiMetni(DateTime.utc(2026, 9, 28)),
        '28 Eyl – 4 Eki 2026',
      );
      expect(
        haftaAraligiMetni(DateTime.utc(2025, 12, 29)),
        '29 Ara 2025 – 4 Oca 2026',
      );
    });

    test('kısa gün adı', () {
      expect(kisaGunAdi(pzt), 'Pzt');
      expect(kisaGunAdi(gunEkle(pzt, 6)), 'Paz');
    });
  });

  group('gunlukOzet', () {
    Plan p(DateTime gun, int saat, PlanDurumu durum) =>
        Plan(baslik: 'P', gun: gun, baslangicSaati: saat, durum: durum);

    test('yapılan, kalan, kayan ve iptal sayılır', () {
      final ozet = gunlukOzet(
        [
          p(pzt, 9, PlanDurumu.yapildi),
          p(pzt, 10, PlanDurumu.yapildi),
          p(pzt, 11, PlanDurumu.iptal),
          p(sali, 9, PlanDurumu.isaretsiz),
        ],
        [
          KaymaKaydi(
            planId: 1,
            baslik: 'K',
            gun: pzt,
            baslangicSaati: 15,
            sure: 1,
            yeniGun: sali,
            yeniBaslangicSaati: 9,
          ),
        ],
      );

      final pztOzet = ozet[pzt]!;
      expect(pztOzet.yapilan, 2);
      expect(pztOzet.kayan, 1);
      expect(pztOzet.iptal, 1);
      // 3 plan (2 yapıldı + 1 kaydı), iptal sayılmaz
      expect(pztOzet.planSayisi, 3);
      expect(pztOzet.oran, closeTo(2 / 3, 1e-9));

      final saliOzet = ozet[sali]!;
      expect(saliOzet.planSayisi, 1);
      expect(saliOzet.oran, 0);
    });

    test('sadece iptal olan günün oranı yok', () {
      final ozet = gunlukOzet([p(pzt, 9, PlanDurumu.iptal)], const []);
      expect(ozet[pzt]!.oran, isNull);
      expect(ozet[pzt]!.bos, isFalse);
      expect(const GunOzeti().bos, isTrue);
    });
  });
}
