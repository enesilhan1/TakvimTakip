import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';
import 'ayarlar_ekrani.dart';
import 'plan_formu.dart';
import 'plan_islemleri.dart';

/// E-tablo gibi haftalık görünüm: satırlar saat, sütunlar gün
/// (docs/SPEC.md §6).
///
/// Boş hücreye dokununca o gün ve saate plan eklenir, plana dokununca
/// işlem paneli açılır, gün başlığına dokununca o günün gün görünümüne
/// geçilir.
class HaftaGorunumu extends StatefulWidget {
  final PlanDeposu depo;
  final DateTime bugun;

  /// Açılışta gösterilecek haftadaki herhangi bir gün.
  final DateTime gun;

  /// Hafta değişince haftanın pazartesisi bildirilir.
  final ValueChanged<DateTime>? onGunDegisti;

  /// Gün başlığına dokununca.
  final ValueChanged<DateTime>? onGunSec;

  const HaftaGorunumu({
    super.key,
    required this.depo,
    required this.bugun,
    required this.gun,
    this.onGunDegisti,
    this.onGunSec,
  });

  @override
  State<HaftaGorunumu> createState() => _HaftaGorunumuState();
}

class _HaftaGorunumuState extends State<HaftaGorunumu> {
  static const satirYuksekligi = 48.0;
  static const saatSutunu = 40.0;

  late DateTime _pazartesi = haftaBasi(widget.gun);
  List<Plan> _planlar = const [];
  final _kaydirma = ScrollController(initialScrollOffset: 8 * satirYuksekligi);

  List<DateTime> get _gunler => [
    for (var i = 0; i < 7; i++) gunEkle(_pazartesi, i),
  ];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _kaydirma.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final pzt = _pazartesi;
    final planlar = await widget.depo.araliktakiPlanlar(pzt, gunEkle(pzt, 6));
    if (!mounted || pzt != _pazartesi) return;
    setState(() => _planlar = planlar);
  }

  void _haftaDegistir(DateTime gun) {
    setState(() {
      _pazartesi = haftaBasi(gun);
      _planlar = const [];
    });
    widget.onGunDegisti?.call(_pazartesi);
    _yukle();
  }

  Future<void> _ekle(DateTime gun, int saat) async {
    if (await planFormuAc(
      context,
      depo: widget.depo,
      bugun: widget.bugun,
      gun: gun,
      saat: saat,
    )) {
      _yukle();
    }
  }

  Future<void> _islemler(Plan plan) async {
    if (await planIslemleriAc(
      context,
      depo: widget.depo,
      plan: plan,
      gecmis: plan.gun.isBefore(widget.bugun),
      bugun: widget.bugun,
    )) {
      _yukle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final buHafta = _pazartesi == haftaBasi(widget.bugun);
    return Scaffold(
      appBar: AppBar(
        title: Text(haftaAraligiMetni(_pazartesi)),
        actions: [
          if (!buHafta)
            IconButton(
              tooltip: 'Bu haftaya git',
              icon: const Icon(Icons.today),
              onPressed: () => _haftaDegistir(widget.bugun),
            ),
          IconButton(
            tooltip: 'Önceki hafta',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _haftaDegistir(gunEkle(_pazartesi, -7)),
          ),
          IconButton(
            tooltip: 'Sonraki hafta',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _haftaDegistir(gunEkle(_pazartesi, 7)),
          ),
          AyarlarButonu(depo: widget.depo, onVeriDegisti: _yukle),
        ],
      ),
      body: Column(
        children: [
          _baslikSatiri(context),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: _kaydirma,
              child: SizedBox(
                height: 24 * satirYuksekligi,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _saatSutunu(context),
                    for (final g in _gunler) Expanded(child: _gunSutunu(g)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Üstte gün adları ve tarihleri; bugün renkli daire içinde.
  Widget _baslikSatiri(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    return Row(
      children: [
        const SizedBox(width: saatSutunu),
        for (final g in _gunler)
          Expanded(
            child: InkWell(
              onTap: () => widget.onGunSec?.call(g),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      kisaGunAdi(g),
                      style: TextStyle(fontSize: 12, color: renk.outline),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: g == widget.bugun
                          ? BoxDecoration(
                              color: renk.primary,
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Text(
                        '${g.day}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: g == widget.bugun ? renk.onPrimary : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _saatSutunu(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    return SizedBox(
      width: saatSutunu,
      child: Column(
        children: [
          for (var s = 0; s < 24; s++)
            SizedBox(
              height: satirYuksekligi,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    s.toString().padLeft(2, '0'),
                    style: TextStyle(fontSize: 11, color: renk.outline),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Bir günün sütunu: arkada 24 boş hücre, üstünde plan blokları.
  Widget _gunSutunu(DateTime gun) {
    final renk = Theme.of(context).colorScheme;
    final gecmis = gun.isBefore(widget.bugun);
    final planlar = _planlar.where((p) => p.gun == gun);
    return Stack(
      children: [
        Column(
          children: [
            for (var s = 0; s < 24; s++)
              InkWell(
                onTap: gecmis ? null : () => _ekle(gun, s),
                child: Container(
                  height: satirYuksekligi,
                  decoration: BoxDecoration(
                    color: gecmis
                        ? renk.surfaceContainerLow
                        : gun == widget.bugun
                        ? renk.primaryContainer.withValues(alpha: 0.15)
                        : null,
                    border: Border(
                      top: BorderSide(color: renk.outlineVariant, width: 0.5),
                      left: BorderSide(color: renk.outlineVariant, width: 0.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (final p in planlar)
          Positioned(
            top: p.baslangicSaati * satirYuksekligi + 1,
            height: p.sure * satirYuksekligi - 2,
            left: 1.5,
            right: 1,
            child: HaftaPlanBlogu(
              plan: p,
              gecmis: gecmis,
              onTap: () => _islemler(p),
            ),
          ),
      ],
    );
  }
}

/// Haftalık tablodaki küçük plan bloğu.
class HaftaPlanBlogu extends StatelessWidget {
  final Plan plan;
  final bool gecmis;
  final VoidCallback? onTap;

  const HaftaPlanBlogu({
    super.key,
    required this.plan,
    required this.gecmis,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    final yapildi = plan.durum == PlanDurumu.yapildi;
    final iptal = plan.durum == PlanDurumu.iptal;
    final soluk = iptal || (gecmis && plan.durum == PlanDurumu.isaretsiz);

    return Material(
      color: yapildi
          ? Colors.green.withValues(alpha: 0.25)
          : soluk
          ? renk.surfaceContainerHighest
          : renk.primaryContainer,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Text(
            '${yapildi ? '✓ ' : ''}${plan.sabit ? '📌' : ''}${plan.baslik}',
            // Uzun planlarda daha çok satır göster.
            maxLines: plan.sure * 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              decoration: iptal ? TextDecoration.lineThrough : null,
              color: soluk ? renk.outline : renk.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
