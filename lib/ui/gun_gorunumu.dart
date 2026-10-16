import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import '../models/kayma_kaydi.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';
import 'ayarlar_ekrani.dart';
import 'plan_formu.dart';
import 'plan_islemleri.dart';

/// Tek bir günün 24 saatlik çizelgesi (docs/SPEC.md §6).
///
/// Her saat bir satırdır. Çok saatli planlar kapladıkları satırlar kadar
/// uzun tek bir kart olarak gösterilir. Kapanan günde kayan planların izi
/// soluk olarak kendi eski saatinde kalır.
class GunGorunumu extends StatefulWidget {
  final PlanDeposu depo;

  /// Bugünün tarihi. Geçmiş günler buna göre belirlenir.
  final DateTime bugun;

  /// Açılışta gösterilecek gün (verilmezse bugün).
  final DateTime? ilkGun;

  /// Şu anki saati verir; testlerde sabitlemek için. Verilmezse telefonun
  /// saati kullanılır.
  final int Function()? simdiSaat;

  /// Gösterilen gün değişince (ana ekran diğer görünümleri aynı güne açsın).
  final ValueChanged<DateTime>? onGunDegisti;

  const GunGorunumu({
    super.key,
    required this.depo,
    required this.bugun,
    this.ilkGun,
    this.simdiSaat,
    this.onGunDegisti,
  });

  @override
  State<GunGorunumu> createState() => _GunGorunumuState();
}

class _GunGorunumuState extends State<GunGorunumu> {
  static const satirYuksekligi = 64.0;

  late DateTime _gun;
  List<Plan> _planlar = const [];
  List<KaymaKaydi> _izler = const [];
  late ScrollController _kaydirma;

  bool get _gecmis => _gun.isBefore(widget.bugun);
  bool get _bugunMu => _gun == widget.bugun;

  int _simdiSaat() => widget.simdiSaat?.call() ?? DateTime.now().hour;

  @override
  void initState() {
    super.initState();
    _gun = gunOf(widget.ilkGun ?? widget.bugun);
    _kaydirma = ScrollController(initialScrollOffset: _ilkKaydirma());
    _yukle();
  }

  @override
  void dispose() {
    _kaydirma.dispose();
    super.dispose();
  }

  /// Bugünse şu anki saatin bir öncesine, değilse 08:00'e kaydırır.
  double _ilkKaydirma() {
    final saat = _bugunMu ? (_simdiSaat() - 1).clamp(0, 23) : 8;
    return saat * satirYuksekligi;
  }

  Future<void> _yukle() async {
    final gun = _gun;
    final planlar = await widget.depo.gununPlanlari(gun);
    final izler = await widget.depo.gununKaymaKayitlari(gun);
    if (!mounted || gun != _gun) return;
    setState(() {
      _planlar = planlar;
      _izler = izler;
    });
  }

  void _gunDegistir(DateTime yeni) {
    setState(() {
      _gun = gunOf(yeni);
      _planlar = const [];
      _izler = const [];
    });
    if (_kaydirma.hasClients) _kaydirma.jumpTo(_ilkKaydirma());
    widget.onGunDegisti?.call(_gun);
    _yukle();
  }

  Future<void> _tarihSec() async {
    final secilen = await showDatePicker(
      context: context,
      initialDate: _gun,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (secilen != null) _gunDegistir(secilen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _tarihSec,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_gun.day} ${ayAdlari[_gun.month - 1]} ${_gun.year}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                _bugunMu ? 'Bugün · ${gunAdi(_gun)}' : gunAdi(_gun),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          if (!_bugunMu)
            IconButton(
              tooltip: 'Bugüne git',
              icon: const Icon(Icons.today),
              onPressed: () => _gunDegistir(widget.bugun),
            ),
          IconButton(
            tooltip: 'Önceki gün',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _gunDegistir(gunEkle(_gun, -1)),
          ),
          IconButton(
            tooltip: 'Sonraki gün',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _gunDegistir(gunEkle(_gun, 1)),
          ),
          AyarlarButonu(depo: widget.depo, onVeriDegisti: _yukle),
        ],
      ),
      body: GestureDetector(
        // Sağa/sola kaydırarak gün değiştir.
        onHorizontalDragEnd: (d) {
          final hiz = d.primaryVelocity ?? 0;
          if (hiz.abs() < 300) return;
          _gunDegistir(gunEkle(_gun, hiz < 0 ? 1 : -1));
        },
        child: ListView(
          controller: _kaydirma,
          padding: const EdgeInsets.only(bottom: 88),
          children: [for (final s in _satirlar()) s],
        ),
      ),
      floatingActionButton: _gecmis
          ? null
          : FloatingActionButton(
              tooltip: 'Plan ekle',
              onPressed: () =>
                  _ekle(_bugunMu ? (_simdiSaat() + 1).clamp(0, 23) : 9),
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _ekle(int saat) async {
    final kaydedildi = await planFormuAc(
      context,
      depo: widget.depo,
      bugun: widget.bugun,
      gun: _gun,
      saat: saat,
    );
    if (kaydedildi) _yukle();
  }

  Future<void> _islemler(Plan plan) async {
    final degisti = await planIslemleriAc(
      context,
      depo: widget.depo,
      plan: plan,
      gecmis: _gecmis,
      bugun: widget.bugun,
    );
    if (degisti) _yukle();
  }

  /// Durum ikonu: yapılmadıysa "yapıldı" yapar, yapıldıysa işareti kaldırır
  /// (kaldırılabiliyorsa).
  Future<void> _hizliIsaretle(Plan plan) async {
    final PlanDurumu yeni;
    if (plan.durum != PlanDurumu.yapildi) {
      yeni = PlanDurumu.yapildi;
    } else if (isaretKaldirilabilir(plan, gecmis: _gecmis)) {
      yeni = PlanDurumu.isaretsiz;
    } else {
      return;
    }
    await widget.depo.durumDegistir(plan.id!, yeni);
    _yukle();
  }

  /// 00:00'dan 24:00'e kadar satırları kurar: plan kartları, kayma izleri ve
  /// boş saatler.
  List<Widget> _satirlar() {
    final planBaslangic = {for (final p in _planlar) p.baslangicSaati: p};
    final izBaslangic = {for (final k in _izler) k.baslangicSaati: k};

    final satirlar = <Widget>[];
    var saat = 0;
    while (saat < 24) {
      final plan = planBaslangic[saat];
      final iz = izBaslangic[saat];
      if (plan != null) {
        satirlar.add(
          _SaatSatiri(
            saat: saat,
            sure: plan.sure,
            child: PlanKarti(
              plan: plan,
              gecmis: _gecmis,
              onTap: () => _islemler(plan),
              onDurumTap: () => _hizliIsaretle(plan),
            ),
          ),
        );
        saat += plan.sure;
      } else if (iz != null) {
        satirlar.add(
          _SaatSatiri(
            saat: saat,
            sure: iz.sure,
            child: KaymaIziKarti(iz: iz),
          ),
        );
        saat += iz.sure;
      } else {
        final s = saat;
        satirlar.add(
          _SaatSatiri(
            saat: s,
            sure: 1,
            // Boş saate dokununca o saate plan ekle (geçmiş günde kapalı).
            onTap: _gecmis ? null : () => _ekle(s),
          ),
        );
        saat++;
      }
    }
    return satirlar;
  }
}

/// Sol tarafta saat etiketi, sağda içerik (boşsa ince çizgi).
class _SaatSatiri extends StatelessWidget {
  final int saat;
  final int sure;
  final Widget? child;
  final VoidCallback? onTap;

  const _SaatSatiri({
    required this.saat,
    required this.sure,
    this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    return SizedBox(
      height: sure * _GunGorunumuState.satirYuksekligi,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, left: 8),
                child: Text(
                  saatMetni(saat),
                  style: TextStyle(color: renk.outline, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: renk.outlineVariant, width: 0.5),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(0, 3, 8, 3),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bir planın kartı: başlık, saat aralığı, sabit işareti, sayaç ve durum.
class PlanKarti extends StatelessWidget {
  final Plan plan;

  /// Geçmiş gündeki işaretsiz (sabit) plan "yapılmadı" olarak gösterilir.
  final bool gecmis;

  /// Karta dokununca (işlem paneli).
  final VoidCallback? onTap;

  /// Sağdaki durum ikonuna dokununca (hızlı "yapıldı" işareti).
  final VoidCallback? onDurumTap;

  const PlanKarti({
    super.key,
    required this.plan,
    required this.gecmis,
    this.onTap,
    this.onDurumTap,
  });

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    final yapildi = plan.durum == PlanDurumu.yapildi;
    final iptal = plan.durum == PlanDurumu.iptal;
    final yapilmadi = gecmis && plan.durum == PlanDurumu.isaretsiz;

    final arkaPlan = yapildi
        ? Colors.green.withValues(alpha: 0.25)
        : iptal || yapilmadi
        ? renk.surfaceContainerHighest
        : renk.primaryContainer;

    final altBilgi = [
      plan.saatAraligi,
      if (plan.sabit) '📌 Sabit',
      if (plan.yapilmadiSayisi > 0) '${plan.yapilmadiSayisi} kez yapılmadı',
      if (iptal) 'İptal',
      if (yapilmadi) 'Yapılmadı',
    ].join(' · ');

    return Material(
      color: arkaPlan,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      plan.baslik,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: iptal ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      altBilgi,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: renk.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: yapildi ? 'İşareti kaldır' : 'Yapıldı',
                onPressed: onDurumTap,
                icon: Icon(
                  yapildi
                      ? Icons.check_circle
                      : iptal
                      ? Icons.block
                      : yapilmadi
                      ? Icons.cancel_outlined
                      : Icons.radio_button_unchecked,
                  color: yapildi ? Colors.green : renk.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kapanan günde kalan soluk iz: `Kitap — yapılmadı → Salı 13:00'e kaydı`.
class KaymaIziKarti extends StatelessWidget {
  final KaymaKaydi iz;

  const KaymaIziKarti({super.key, required this.iz});

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: renk.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      alignment: Alignment.centerLeft,
      child: Text(
        '${iz.baslik} — ${iz.aciklama}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: renk.outline, fontStyle: FontStyle.italic),
      ),
    );
  }
}
