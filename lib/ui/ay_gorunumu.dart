import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import '../logic/gun_ozeti.dart';
import '../utils/tarih.dart';

/// Aylık takvim ızgarası (docs/SPEC.md §6).
///
/// Her günde yapılan/toplam plan sayısı ve ince bir tamamlanma çubuğu
/// gösterilir. Güne dokununca o günün gün görünümüne geçilir.
class AyGorunumu extends StatefulWidget {
  final PlanDeposu depo;
  final DateTime bugun;

  /// Açılışta gösterilecek aydaki herhangi bir gün.
  final DateTime gun;

  /// Ay değişince ayın ilk günü bildirilir.
  final ValueChanged<DateTime>? onGunDegisti;

  /// Güne dokununca.
  final ValueChanged<DateTime>? onGunSec;

  const AyGorunumu({
    super.key,
    required this.depo,
    required this.bugun,
    required this.gun,
    this.onGunDegisti,
    this.onGunSec,
  });

  @override
  State<AyGorunumu> createState() => _AyGorunumuState();
}

class _AyGorunumuState extends State<AyGorunumu> {
  late DateTime _ay = ayBasi(widget.gun);
  Map<DateTime, GunOzeti> _ozet = const {};

  /// Izgaranın ilk günü (ayın ilk gününün haftasının pazartesisi).
  DateTime get _ilkGun => haftaBasi(_ay);

  /// Ayı kapsayan hafta sayısı (4–6).
  int get _haftaSayisi {
    final bosluk = _ay.weekday - 1;
    return ((bosluk + aydakiGunSayisi(_ay)) / 7).ceil();
  }

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final ay = _ay;
    final bas = _ilkGun;
    final bit = gunEkle(bas, _haftaSayisi * 7 - 1);
    final planlar = await widget.depo.araliktakiPlanlar(bas, bit);
    final izler = await widget.depo.araliktakiKaymaKayitlari(bas, bit);
    if (!mounted || ay != _ay) return;
    setState(() => _ozet = gunlukOzet(planlar, izler));
  }

  void _ayDegistir(int fark) {
    setState(() {
      _ay = DateTime.utc(_ay.year, _ay.month + fark, 1);
      _ozet = const {};
    });
    widget.onGunDegisti?.call(_ay);
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    final buAy = _ay == ayBasi(widget.bugun);

    return Scaffold(
      appBar: AppBar(
        title: Text('${ayAdlari[_ay.month - 1]} ${_ay.year}'),
        actions: [
          if (!buAy)
            IconButton(
              tooltip: 'Bu aya git',
              icon: const Icon(Icons.today),
              onPressed: () => _ayDegistir(
                (widget.bugun.year - _ay.year) * 12 +
                    widget.bugun.month -
                    _ay.month,
              ),
            ),
          IconButton(
            tooltip: 'Önceki ay',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _ayDegistir(-1),
          ),
          IconButton(
            tooltip: 'Sonraki ay',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _ayDegistir(1),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        kisaGunAdi(gunEkle(_ilkGun, i)),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: renk.outline),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Column(
                children: [
                  for (var h = 0; h < _haftaSayisi; h++)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: _gunHucresi(gunEkle(_ilkGun, h * 7 + i)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gunHucresi(DateTime gun) {
    final renk = Theme.of(context).colorScheme;
    final ozet = _ozet[gun] ?? const GunOzeti();
    final buAyda = gun.month == _ay.month;
    final bugunMu = gun == widget.bugun;
    final oran = ozet.oran;

    return Opacity(
      opacity: buAyda ? 1 : 0.4,
      child: InkWell(
        onTap: () => widget.onGunSec?.call(gun),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.all(1.5),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: renk.outlineVariant, width: 0.5),
          ),
          child: Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: bugunMu
                    ? BoxDecoration(color: renk.primary, shape: BoxShape.circle)
                    : null,
                child: Text(
                  '${gun.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: bugunMu ? renk.onPrimary : null,
                  ),
                ),
              ),
              const Spacer(),
              if (ozet.planSayisi > 0) ...[
                FittedBox(
                  child: Text.rich(
                    TextSpan(
                      text: '${ozet.yapilan}/${ozet.planSayisi}',
                      children: [
                        // Yapılmadığı için kayan plan sayısı
                        if (ozet.kayan > 0)
                          TextSpan(
                            text: ' ↷${ozet.kayan}',
                            style: TextStyle(color: renk.error),
                          ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: oran,
                    minHeight: 4,
                    color: Colors.green,
                    backgroundColor: renk.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
