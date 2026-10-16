import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import '../models/plan.dart';
import 'plan_formu.dart';

/// Geçmiş günde, sabit olmayan bir plan "işaretsiz"e döndürülemez: o gün
/// kapandığı için bir daha kaymaz ve takılı kalırdı.
bool isaretKaldirilabilir(Plan plan, {required bool gecmis}) =>
    plan.durum != PlanDurumu.isaretsiz && (!gecmis || plan.sabit);

/// Plana dokununca açılan işlem paneli: yapıldı / iptal / işareti kaldır /
/// düzenle / sil. Bir değişiklik yapıldıysa `true` döner.
Future<bool> planIslemleriAc(
  BuildContext context, {
  required PlanDeposu depo,
  required Plan plan,
  required bool gecmis,
  required DateTime bugun,
}) async {
  final secim = await showModalBottomSheet<_Islem>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _IslemPaneli(plan: plan, gecmis: gecmis),
  );
  if (secim == null || !context.mounted) return false;

  final id = plan.id!;
  switch (secim) {
    case _Islem.yapildi:
      await depo.durumDegistir(id, PlanDurumu.yapildi);
    case _Islem.iptal:
      await depo.durumDegistir(id, PlanDurumu.iptal);
    case _Islem.isaretiKaldir:
      await depo.durumDegistir(id, PlanDurumu.isaretsiz);
    case _Islem.duzenle:
      return planFormuAc(context, depo: depo, bugun: bugun, mevcut: plan);
    case _Islem.sil:
      final onay = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Plan silinsin mi?'),
          content: Text('"${plan.baslik}" kalıcı olarak silinecek.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sil'),
            ),
          ],
        ),
      );
      if (onay != true) return false;
      await depo.sil(id);
  }
  return true;
}

enum _Islem { yapildi, iptal, isaretiKaldir, duzenle, sil }

class _IslemPaneli extends StatelessWidget {
  final Plan plan;
  final bool gecmis;

  const _IslemPaneli({required this.plan, required this.gecmis});

  @override
  Widget build(BuildContext context) {
    final metin = Theme.of(context).textTheme;
    Widget secenek(_Islem islem, IconData ikon, String yazi) => ListTile(
      leading: Icon(ikon),
      title: Text(yazi),
      onTap: () => Navigator.pop(context, islem),
    );

    return SafeArea(
      // Kısa ekranlarda ya da uzun notta taşmasın.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.baslik, style: metin.titleLarge),
                  Text(
                    [
                      plan.saatAraligi,
                      if (plan.sabit) '📌 Sabit',
                      if (plan.yapilmadiSayisi > 0)
                        '${plan.yapilmadiSayisi} kez yapılmadı',
                    ].join(' · '),
                    style: metin.bodyMedium,
                  ),
                  if (plan.not.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(plan.not),
                  ],
                ],
              ),
            ),
            const Divider(),
            if (plan.durum != PlanDurumu.yapildi)
              secenek(_Islem.yapildi, Icons.check_circle_outline, 'Yapıldı'),
            if (plan.durum != PlanDurumu.iptal)
              secenek(_Islem.iptal, Icons.block, 'İptal et (kaymasın)'),
            if (isaretKaldirilabilir(plan, gecmis: gecmis))
              secenek(_Islem.isaretiKaldir, Icons.undo, 'İşareti kaldır'),
            if (!gecmis)
              secenek(_Islem.duzenle, Icons.edit_outlined, 'Düzenle'),
            secenek(_Islem.sil, Icons.delete_outline, 'Sil'),
          ],
        ),
      ),
    );
  }
}
