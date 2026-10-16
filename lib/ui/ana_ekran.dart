import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import 'ay_gorunumu.dart';
import 'gun_gorunumu.dart';
import 'hafta_gorunumu.dart';

/// Alttaki menüyle görünümler arasında geçiş: Gün / Hafta / Ay.
///
/// Seçili gün görünümler arasında ortaktır: haftalık ya da aylık görünümde
/// bir güne dokununca gün görünümü o güne açılır.
class AnaEkran extends StatefulWidget {
  final PlanDeposu depo;
  final DateTime bugun;
  final int Function()? simdiSaat;

  const AnaEkran({
    super.key,
    required this.depo,
    required this.bugun,
    this.simdiSaat,
  });

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  int _sekme = 0;
  late DateTime _gun = widget.bugun;

  /// Gün görünümünü dışarıdan başka bir güne açmak için yeniden kurar.
  int _gunSurumu = 0;

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
        ],
      ),
    );
  }
}
