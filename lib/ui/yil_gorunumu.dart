import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import '../logic/gun_ozeti.dart';
import '../logic/istatistik.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';

/// Yıllık görünüm (docs/SPEC.md §6): GitHub katkı grafiği gibi renkli
/// kutucuklar ve yılın istatistikleri.
///
/// Telefon ekranına 53 haftalık tek şerit sığmadığı için kutucuklar 12 küçük
/// ay halinde dizilir. Bir gün ne kadar tamamlandıysa kutusu o kadar koyu
/// yeşildir. Güne dokununca gün görünümü, ay adına dokununca aylık görünüm
/// açılır.
class YilGorunumu extends StatefulWidget {
  final PlanDeposu depo;
  final DateTime bugun;
  final DateTime gun;
  final ValueChanged<DateTime>? onGunDegisti;
  final ValueChanged<DateTime>? onGunSec;
  final ValueChanged<DateTime>? onAySec;

  const YilGorunumu({
    super.key,
    required this.depo,
    required this.bugun,
    required this.gun,
    this.onGunDegisti,
    this.onGunSec,
    this.onAySec,
  });

  @override
  State<YilGorunumu> createState() => _YilGorunumuState();
}

class _YilGorunumuState extends State<YilGorunumu> {
  late int _yil = widget.gun.year;
  Map<DateTime, GunOzeti> _ozet = const {};
  List<Plan> _ertelenenler = const [];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final yil = _yil;
    final bas = DateTime.utc(yil, 1, 1);
    final bit = DateTime.utc(yil, 12, 31);
    final planlar = await widget.depo.araliktakiPlanlar(bas, bit);
    final izler = await widget.depo.araliktakiKaymaKayitlari(bas, bit);
    final ertelenenler = await widget.depo.enCokErtelenenler();
    if (!mounted || yil != _yil) return;
    setState(() {
      _ozet = gunlukOzet(planlar, izler);
      _ertelenenler = ertelenenler;
    });
  }

  void _yilDegistir(int yil) {
    setState(() {
      _yil = yil;
      _ozet = const {};
    });
    widget.onGunDegisti?.call(DateTime.utc(yil, 1, 1));
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final ist = yilIstatistigi(_ozet, yil: _yil, bugun: widget.bugun);
    return Scaffold(
      appBar: AppBar(
        title: Text('$_yil'),
        actions: [
          if (_yil != widget.bugun.year)
            IconButton(
              tooltip: 'Bu yıla git',
              icon: const Icon(Icons.today),
              onPressed: () => _yilDegistir(widget.bugun.year),
            ),
          IconButton(
            tooltip: 'Önceki yıl',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _yilDegistir(_yil - 1),
          ),
          IconButton(
            tooltip: 'Sonraki yıl',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _yilDegistir(_yil + 1),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _IstatistikKarti(ist: ist),
          if (_ertelenenler.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ErtelenenlerKarti(planlar: _ertelenenler),
          ],
          const SizedBox(height: 16),
          const _Aciklama(),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [
              for (var ay = 1; ay <= 12; ay++)
                _MiniAy(
                  ay: DateTime.utc(_yil, ay, 1),
                  ozet: _ozet,
                  bugun: widget.bugun,
                  onGunSec: widget.onGunSec,
                  onAySec: widget.onAySec,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kutucuk rengi: planı olmayan gün gri, hiçbiri yapılmayan gün açık kırmızı,
/// diğerleri tamamlanma oranına göre açıktan koyuya yeşil. (Gelecekteki
/// planlı günler renksiz, sadece çerçeveli çizilir.)
Color? _kutuRengi(BuildContext context, int? seviye) {
  final renk = Theme.of(context).colorScheme;
  if (seviye == null) return renk.surfaceContainerHighest;
  // Planlanıp hiçbiri yapılmayan gün, planı olmayan günle karışmasın.
  if (seviye == 0) return Colors.red.withValues(alpha: 0.3);
  const opaklik = [0, 0.3, 0.55, 0.75, 1.0];
  return Colors.green.withValues(alpha: opaklik[seviye].toDouble());
}

class _IstatistikKarti extends StatelessWidget {
  final YilIstatistigi ist;

  const _IstatistikKarti({required this.ist});

  @override
  Widget build(BuildContext context) {
    final oran = ist.oran;
    Widget kutu(String deger, String etiket) => Expanded(
      child: Column(
        children: [
          Text(deger, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            etiket,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                kutu(
                  oran == null ? '–' : '%${(oran * 100).round()}',
                  'tamamlandı\n(${ist.yapilan}/${ist.planSayisi} plan)',
                ),
                kutu('${ist.kayma}', 'kez\nertelendi'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                kutu('${ist.mevcutSeri}', 'günlük\nmevcut seri'),
                kutu('${ist.enUzunSeri}', 'günlük\nen uzun seri'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErtelenenlerKarti extends StatelessWidget {
  final List<Plan> planlar;

  const _ErtelenenlerKarti({required this.planlar});

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'En çok ertelenenler',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final p in planlar)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.baslik,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('${p.yapilmadiSayisi} kez'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Az ▢▢▢▢▢ Çok" renk açıklaması.
class _Aciklama extends StatelessWidget {
  const _Aciklama();

  @override
  Widget build(BuildContext context) {
    final stil = Theme.of(context).textTheme.bodySmall;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Az', style: stil),
        for (var s = 0; s <= 4; s++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _kutuRengi(context, s),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Text('Çok', style: stil),
      ],
    );
  }
}

class _MiniAy extends StatelessWidget {
  final DateTime ay;
  final Map<DateTime, GunOzeti> ozet;
  final DateTime bugun;
  final ValueChanged<DateTime>? onGunSec;
  final ValueChanged<DateTime>? onAySec;

  const _MiniAy({
    required this.ay,
    required this.ozet,
    required this.bugun,
    this.onGunSec,
    this.onAySec,
  });

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    final bosluk = ay.weekday - 1;
    final gunSayisi = aydakiGunSayisi(ay);
    final satir = ((bosluk + gunSayisi) / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onAySec?.call(ay),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              ayAdlari[ay.month - 1],
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        for (var s = 0; s < 6; s++)
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final no = s * 7 + i - bosluk + 1;
                        if (s >= satir || no < 1 || no > gunSayisi) {
                          return const SizedBox.shrink();
                        }
                        final gun = DateTime.utc(ay.year, ay.month, no);
                        final o = ozet[gun];
                        final gelecek = gun.isAfter(bugun);
                        final planli = (o?.planSayisi ?? 0) > 0;
                        return GestureDetector(
                          onTap: () => onGunSec?.call(gun),
                          child: Container(
                            key: ValueKey('kutu-${gunAnahtari(gun)}'),
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              color: gelecek && planli
                                  ? null
                                  : _kutuRengi(
                                      context,
                                      gelecek ? null : yogunluk(o),
                                    ),
                              borderRadius: BorderRadius.circular(2),
                              border: gun == bugun
                                  ? Border.all(color: renk.primary, width: 1.5)
                                  : gelecek && planli
                                  ? Border.all(color: renk.outline)
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
