import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_veri;
import 'package:timezone/timezone.dart' as tz;

import '../data/plan_deposu.dart';
import '../logic/bildirim_plani.dart';
import '../utils/tarih.dart';

/// Bildirim planlayıcısının (lib/logic/bildirim_plani.dart) hesapladığı
/// bildirimleri telefonun bildirim sistemine kurar.
class BildirimServisi {
  BildirimServisi._();

  static final _eklenti = FlutterLocalNotificationsPlugin();
  static bool _hazir = false;

  static const _kanalId = 'planlar';
  static const _kanalAdi = 'Planlar';
  static const _kanalAciklamasi = 'Sabah özeti ve plan hatırlatıcıları';

  /// Saat dilimini ve eklentiyi hazırlar (birden çok çağrılabilir).
  static Future<void> hazirla() async {
    if (_hazir) return;
    tz_veri.initializeTimeZones();
    try {
      final bolge = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(bolge.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    }
    await _eklenti.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _hazir = true;
  }

  /// Android 13+ için bildirim iznini ister (verildiyse bir şey göstermez).
  static Future<void> izinIste() async {
    await hazirla();
    await _eklenti
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// Bekleyen bütün bildirimleri silip bugünün bildirimlerini baştan kurar.
  ///
  /// Plan eklenince/değişince, uygulama açılınca ve gece yarısı kaydırmasından
  /// sonra çağrılır. Sabit kimlikler sayesinde çift bildirim oluşmaz.
  static Future<void> yenidenKur(PlanDeposu depo, {DateTime? simdi}) async {
    await hazirla();
    final an = simdi ?? DateTime.now();
    final bugun = gunOf(an);

    final bildirimler = bildirimleriPlanla(
      simdi: an,
      planlar: await depo.araliktakiPlanlar(bugun, gunEkle(bugun, 1)),
      sabahSaati:
          int.tryParse(await depo.ayarOku(sabahSaatiAyari) ?? '') ??
          varsayilanSabahSaati,
      dunOzeti: await depo.kapanisOzeti(gunEkle(bugun, -1)),
    );

    await _eklenti.cancelAllPendingNotifications();
    for (final b in bildirimler) {
      await _kur(b);
    }
    debugPrint('Takvim Takip: ${bildirimler.length} bildirim kuruldu');
  }

  static Future<void> _kur(PlanlanmisBildirim b) async {
    final ayrinti = NotificationDetails(
      android: AndroidNotificationDetails(
        _kanalId,
        _kanalAdi,
        channelDescription: _kanalAciklamasi,
        importance: Importance.high,
        priority: Priority.high,
        // Sabah özeti birden çok satır; bildirim açılınca tamamı görünsün.
        styleInformation: BigTextStyleInformation(b.govde),
      ),
    );
    Future<void> kur(AndroidScheduleMode mod) => _eklenti.zonedSchedule(
      id: b.id,
      title: b.baslik,
      body: b.govde,
      scheduledDate: tz.TZDateTime.from(b.zaman, tz.local),
      notificationDetails: ayrinti,
      androidScheduleMode: mod,
    );
    try {
      await kur(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException {
      // Tam zamanlı alarm izni yoksa birkaç dakika sapabilen moda düş.
      await kur(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }
}
