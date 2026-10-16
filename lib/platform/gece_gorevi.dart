import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';

import '../data/plan_deposu.dart';
import '../data/veritabani.dart';
import '../logic/kaydirma_servisi.dart';
import 'bildirim_servisi.dart';
import 'widget_servisi.dart';

const _geceAlarmiId = 2300;

/// Her gece 00:00:30'da, uygulama kapalı olsa bile çalışan görev
/// (docs/SPEC.md §4–§5): dünü kaydırır, bugünün bildirimlerini ve
/// widget'ları kurar ve
/// bir sonraki geceyi kurar.
///
/// Android bu fonksiyonu uygulamadan bağımsız bir arka plan ortamında
/// çağırır; o yüzden üst düzey bir fonksiyon olmalı ve vm:entry-point ile
/// işaretlenmeli.
@pragma('vm:entry-point')
Future<void> geceGorevi() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Açık olan uygulamayla bağlantıyı paylaşmasın (bkz. Veritabani.ac).
    final depo = PlanDeposu(await Veritabani.ac(ayriBaglanti: true));
    await KaydirmaServisi(depo).bekleyenGunleriIsle(DateTime.now());
    await BildirimServisi.yenidenKur(depo);
    await WidgetServisi.guncelle(depo);
  } catch (e) {
    // Bir şey ters giderse kaydırma uygulama açılınca yapılır (SPEC §5).
    debugPrint('Takvim Takip gece görevi hatası: $e');
  } finally {
    await geceAlarminiKur();
  }
}

/// Bir sonraki gece yarısı görevini kurar (aynı kimlikle eskisinin yerine).
Future<void> geceAlarminiKur() async {
  final simdi = DateTime.now();
  final zaman = DateTime(simdi.year, simdi.month, simdi.day + 1, 0, 0, 30);
  await AndroidAlarmManager.oneShotAt(
    zaman,
    _geceAlarmiId,
    geceGorevi,
    exact: true,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
}
