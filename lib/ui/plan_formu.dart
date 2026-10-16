import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';

/// Plan ekleme / düzenleme formunu alttan açılan panelde gösterir.
///
/// [mevcut] verilirse düzenleme, verilmezse [gun] ve [saat] için yeni plan.
/// Kaydedildiyse `true` döner. Geçmiş günler seçilemez: kapanmış günler bir
/// daha kaydırılmadığı için oraya eklenen plan takılı kalırdı.
Future<bool> planFormuAc(
  BuildContext context, {
  required PlanDeposu depo,
  required DateTime bugun,
  Plan? mevcut,
  DateTime? gun,
  int saat = 9,
}) async {
  final sonuc = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PlanFormu(
      depo: depo,
      bugun: bugun,
      mevcut: mevcut,
      gun: gunOf(mevcut?.gun ?? gun ?? bugun),
      saat: mevcut?.baslangicSaati ?? saat,
    ),
  );
  return sonuc ?? false;
}

class _PlanFormu extends StatefulWidget {
  final PlanDeposu depo;
  final DateTime bugun;
  final Plan? mevcut;
  final DateTime gun;
  final int saat;

  const _PlanFormu({
    required this.depo,
    required this.bugun,
    required this.mevcut,
    required this.gun,
    required this.saat,
  });

  @override
  State<_PlanFormu> createState() => _PlanFormuState();
}

class _PlanFormuState extends State<_PlanFormu> {
  late final _baslik = TextEditingController(text: widget.mevcut?.baslik);
  late final _not = TextEditingController(text: widget.mevcut?.not);
  late DateTime _gun = widget.gun;
  late int _saat = widget.saat;
  late int _sure = widget.mevcut?.sure ?? 1;
  late bool _sabit = widget.mevcut?.sabit ?? false;
  String? _hata;
  bool _kaydediliyor = false;

  bool get _duzenleme => widget.mevcut != null;

  @override
  void dispose() {
    _baslik.dispose();
    _not.dispose();
    super.dispose();
  }

  Future<void> _gunSec() async {
    final secilen = await showDatePicker(
      context: context,
      initialDate: _gun.isBefore(widget.bugun) ? widget.bugun : _gun,
      firstDate: widget.bugun,
      lastDate: DateTime(2100),
    );
    if (secilen != null) setState(() => _gun = gunOf(secilen));
  }

  Future<void> _kaydet() async {
    final baslik = _baslik.text.trim();
    if (baslik.isEmpty) {
      setState(() => _hata = 'Başlık boş olamaz.');
      return;
    }
    if (_gun.isBefore(widget.bugun)) {
      setState(() => _hata = 'Geçmiş bir güne plan eklenemez.');
      return;
    }

    final m = widget.mevcut;
    final plan = Plan(
      id: m?.id,
      baslik: baslik,
      not: _not.text.trim(),
      gun: _gun,
      baslangicSaati: _saat,
      sure: _sure,
      sabit: _sabit,
      durum: m?.durum ?? PlanDurumu.isaretsiz,
      yapilmadiSayisi: m?.yapilmadiSayisi ?? 0,
    );

    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      if (_duzenleme) {
        await widget.depo.guncelle(plan);
      } else {
        await widget.depo.ekle(plan);
      }
      if (mounted) Navigator.pop(context, true);
    } on PlanCakismaHatasi catch (e) {
      setState(() {
        _hata = e.toString();
        _kaydediliyor = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enFazlaSure = 24 - _saat;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _duzenleme ? 'Planı düzenle' : 'Yeni plan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('baslik'),
              controller: _baslik,
              autofocus: !_duzenleme,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Ne yapacaksın?',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _kaydet(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('not'),
              controller: _not,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Not (isteğe bağlı)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _gunSec,
              icon: const Icon(Icons.event),
              label: Text(uzunTarih(_gun)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('saat'),
                    initialValue: _saat,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Başlangıç',
                      border: OutlineInputBorder(),
                      // Süre alanıyla aynı hizada kalsın.
                      helperText: ' ',
                    ),
                    items: [
                      for (var s = 0; s < 24; s++)
                        DropdownMenuItem(value: s, child: Text(saatMetni(s))),
                    ],
                    onChanged: (s) => setState(() {
                      _saat = s!;
                      if (_sure > 24 - _saat) _sure = 24 - _saat;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    // Başlangıç değişince seçenekler değişir; yeniden kur.
                    key: ValueKey('sure-$enFazlaSure'),
                    initialValue: _sure,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Süre',
                      border: const OutlineInputBorder(),
                      helperText:
                          '${saatMetni(_saat)}–${saatMetni(_saat + _sure)}',
                    ),
                    items: [
                      for (var s = 1; s <= enFazlaSure; s++)
                        DropdownMenuItem(value: s, child: Text('$s saat')),
                    ],
                    onChanged: (s) => setState(() => _sure = s!),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('📌 Sabit plan'),
              subtitle: const Text('Yapılmasa da başka güne kaymaz'),
              value: _sabit,
              onChanged: (v) => setState(() => _sabit = v),
            ),
            if (_hata != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _hata!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: _kaydediliyor ? null : _kaydet,
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}
