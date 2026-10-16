import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import '../platform/widget_servisi.dart';
import 'ay_gorunumu.dart';
import 'gun_gorunumu.dart';
import 'hafta_gorunumu.dart';
import 'sohbet_ekrani.dart';
import 'yil_gorunumu.dart';

/// Alttaki menüyle görünümler arasında geçiş: Gün / Hafta / Ay / Yıl ve
/// Claude asistanı.
///
/// Seçili gün görünümler arasında ortaktır: haftalık ya da aylık görünümde
/// bir güne dokununca gün görünümü o güne açılır.
class AnaEkran extends StatefulWidget {
  final PlanDeposu depo;
  final DateTime bugun;
  final int Function()? simdiSaat;

  /// Ana ekran widget'ına dokununca ilgili görünüme geçmek için.
  final WidgetHedefi? widgetHedefi;

  const AnaEkran({
    super.key,
    required this.depo,
    required this.bugun,
    this.simdiSaat,
    this.widgetHedefi,
  });

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  int _sekme = 0;
  late DateTime _gun = widget.bugun;

  /// Gün görünümünü dışarıdan başka bir güne açmak için yeniden kurar.
  int _gunSurumu = 0;

  @override
  void initState() {
    super.initState();
    _hedefiUygula(widget.widgetHedefi?.al());
    widget.widgetHedefi?.addListener(_widgettenAc);
  }

  @override
  void dispose() {
    widget.widgetHedefi?.removeListener(_widgettenAc);
    super.dispose();
  }

  /// Günlük widget bugünü, haftalık bu haftayı, aylık bu ayı açar.
  void _widgettenAc() =>
      setState(() => _hedefiUygula(widget.widgetHedefi?.al()));

  void _hedefiUygula(String? hedef) {
    final sekme = switch (hedef) {
      'gun' => 0,
      'hafta' => 1,
      'ay' => 2,
      _ => null,
    };
    if (sekme == null) return;
    _gun = widget.bugun;
    _sekme = sekme;
    _gunSurumu++;
  }

  void _guneGit(DateTime gun) {
    setState(() {
      _gun = gun;
      _sekme = 0;
      _gunSurumu++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final govde = switch (_sekme) {
      1 => HaftaGorunumu(
        depo: widget.depo,
        bugun: widget.bugun,
        gun: _gun,
        onGunDegisti: (g) => _gun = g,
        onGunSec: _guneGit,
      ),
      2 => AyGorunumu(
        depo: widget.depo,
        bugun: widget.bugun,
        gun: _gun,
        onGunDegisti: (g) => _gun = g,
        onGunSec: _guneGit,
      ),
      3 => YilGorunumu(
        depo: widget.depo,
        bugun: widget.bugun,
        gun: _gun,
        onGunDegisti: (g) => _gun = g,
        onGunSec: _guneGit,
        onAySec: (ay) => setState(() {
          _gun = ay;
          _sekme = 2;
        }),
      ),
      4 => SohbetEkrani(depo: widget.depo),
      _ => GunGorunumu(
        key: ValueKey(_gunSurumu),
        depo: widget.depo,
        bugun: widget.bugun,
        ilkGun: _gun,
        simdiSaat: widget.simdiSaat,
        onGunDegisti: (g) => _gun = g,
      ),
    };

    return Scaffold(
      body: govde,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _sekme,
        onDestinationSelected: (i) => setState(() {
          _sekme = i;
          // Gün sekmesine dönüldüğünde seçili güne yeniden açılsın.
          if (i == 0) _gunSurumu++;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.view_day), label: 'Gün'),
          NavigationDestination(icon: Icon(Icons.view_week), label: 'Hafta'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Ay'),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Yıl'),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'Asistan',
          ),
        ],
      ),
    );
  }
}
