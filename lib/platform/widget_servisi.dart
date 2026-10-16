import 'dart:convert';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../data/plan_deposu.dart';
import '../data/veritabani.dart';
import '../logic/widget_verisi.dart';
import '../models/plan.dart';
import 'bildirim_servisi.dart';

/// Ana ekran widget'larının (günlük, haftalık, aylık) Dart tarafı
/// (docs/SPEC.md §11). Veriyi hesaplar, widget deposuna yazar, widget'ları
/// yeniler ve bir sonraki değişim anına (plan başlangıcı/bitişi, gece
/// yarısı) yenileme alarmı kurar.
class WidgetServisi {
  WidgetServisi._();

  static const _saglayicilar = [
    'com.enesilhan.takvim_takip.GunlukWidget',
    'com.enesilhan.takvim_takip.HaftalikWidget',
    'com.enesilhan.takvim_takip.AylikWidget',
  ];
  static const _yenilemeAlarmi = 2301;

  /// Uygulama dışında (widget butonuyla) plan değişince yazılır; uygulama
  /// arka plandan dönünce görünümlerini yeniler.
  static const disDegisiklikAyari = 'son_dis_degisiklik';

  /// Widget'lara dokununca açılacak görünüm ("gun", "hafta", "ay").
  static final hedef = WidgetHedefi();

  static Future<void> guncelle(PlanDeposu depo, {DateTime? simdi}) async {
    final an = simdi ?? DateTime.now();
    final r = widgetAraligi(an);
    final veri = widgetVerisiHesapla(
      simdi: an,
      planlar: await depo.araliktakiPlanlar(r.bas, r.bit),
      izler: await depo.araliktakiKaymaKayitlari(r.bas, r.bit),
    );
    await HomeWidget.saveWidgetData<String>(
      'widget_verisi',
      jsonEncode(veri.toJson()),
    );
    for (final ad in _saglayicilar) {
      await HomeWidget.updateWidget(qualifiedAndroidName: ad);
    }
    // "Şimdi" plan bitince ya da sıradaki başlayınca widget kendini yenilesin.
    // Ekran kapalıyken telefonu uyandırmaz; açılınca çalışır.
    await AndroidAlarmManager.oneShotAt(
      veri.sonrakiGuncelleme.add(const Duration(seconds: 5)),
      _yenilemeAlarmi,
      widgetYenilemeGorevi,
      exact: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }

  /// Uygulama açılışında: widget butonunun arka plan geri çağrısını ve
  /// widget'a dokunarak açılmayı bağlar.
  static Future<void> hazirla() async {
    await HomeWidget.registerInteractivityCallback(widgetEtkilesimi);
    final ilk = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (ilk != null) hedef.git(ilk.host);
    HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) hedef.git(uri.host);
    });
  }
}

/// Widget'a dokunulunca hangi görünümün açılacağı. Ana ekran isteği alınca
/// [al] ile tüketir; böylece aynı dokunuş iki kez uygulanmaz.
class WidgetHedefi extends ChangeNotifier {
  String? _tur;

  void git(String yeni) {
    _tur = yeni;
    notifyListeners();
  }

  /// Bekleyen hedefi verir ve temizler ("gun", "hafta", "ay" ya da null).
  String? al() {
    final t = _tur;
    _tur = null;
    return t;
  }
}

/// Plan başlayıp bitince widget'ları yeniler (uygulama kapalıyken de).
@pragma('vm:entry-point')
Future<void> widgetYenilemeGorevi() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final depo = PlanDeposu(await Veritabani.ac(ayriBaglanti: true));
    await WidgetServisi.guncelle(depo);
  } catch (e) {
    debugPrint('Takvim Takip widget yenileme hatası: $e');
  }
}

/// Widget'taki "✓ Yapıldı" butonu: uygulamayı açmadan planı işaretler.
@pragma('vm:entry-point')
Future<void> widgetEtkilesimi(Uri? uri) async {
  if (uri == null || uri.host != 'yapildi') return;
  final id = int.tryParse(uri.queryParameters['id'] ?? '');
  if (id == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final depo = PlanDeposu(await Veritabani.ac(ayriBaglanti: true));
    final plan = await depo.planGetir(id);
    if (plan == null || plan.durum != PlanDurumu.isaretsiz) return;
    await depo.durumDegistir(id, PlanDurumu.yapildi);
    await depo.ayarYaz(
      WidgetServisi.disDegisiklikAyari,
      DateTime.now().toIso8601String(),
    );
    await WidgetServisi.guncelle(depo);
    // Yapılan planın hatırlatıcısı artık çalmasın.
    await BildirimServisi.yenidenKur(depo);
  } catch (e) {
    debugPrint('Takvim Takip widget butonu hatası: $e');
  }
}
