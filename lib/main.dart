import 'dart:async';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/plan_deposu.dart';
import 'data/veritabani.dart';
import 'logic/kaydirma_servisi.dart';
import 'platform/bildirim_servisi.dart';
import 'platform/gece_gorevi.dart';
import 'ui/ana_ekran.dart';
import 'utils/tarih.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final depo = PlanDeposu(await Veritabani.ac());
  // Açılışta kapanmış ama işlenmemiş günleri kaydır (SPEC §5).
  await KaydirmaServisi(depo).bekleyenGunleriIsle(DateTime.now());

  runApp(
    TakvimTakipApp(
      depo: depo,
      bildirimleriYenile: () => BildirimServisi.yenidenKur(depo),
    ),
  );
  unawaited(_arkaPlaniHazirla(depo));
}

/// Bildirim izni, bugünün bildirimleri ve gece yarısı görevi. Arayüz açıldıktan
/// sonra çalışır ki izin penceresi uygulamanın üstünde görünsün.
Future<void> _arkaPlaniHazirla(PlanDeposu depo) async {
  try {
    await BildirimServisi.izinIste();
    await BildirimServisi.yenidenKur(depo);
    await AndroidAlarmManager.initialize();
    await geceAlarminiKur();
  } catch (e) {
    debugPrint('Takvim Takip: arka plan hazırlığı başarısız: $e');
  }
}

class TakvimTakipApp extends StatefulWidget {
  final PlanDeposu depo;

  /// Testlerde sabit bir "bugün" ve "şu anki saat" vermek için. Sabit bugün
  /// verilirse gün değişimi takip edilmez.
  final DateTime? bugunOverride;
  final int Function()? saatOverride;

  /// Testlerde saati ilerletmek için (verilmezse telefonun saati).
  final DateTime Function()? simdiOverride;

  /// Planlar değişince ya da gün kapanınca bildirimleri yeniden kurar.
  /// Testlerde verilmez (bildirim eklentisi yok).
  final Future<void> Function()? bildirimleriYenile;

  const TakvimTakipApp({
    super.key,
    required this.depo,
    this.bugunOverride,
    this.saatOverride,
    this.simdiOverride,
    this.bildirimleriYenile,
  });

  @override
  State<TakvimTakipApp> createState() => _TakvimTakipAppState();
}

/// Gün değişimini takip eder: uygulama açıkken gece yarısı geçtiğinde ya da
/// arka plandan geri dönüldüğünde bekleyen günleri kaydırır ve "bugün"ü
/// günceller.
class _TakvimTakipAppState extends State<TakvimTakipApp>
    with WidgetsBindingObserver {
  late DateTime _bugun = widget.bugunOverride ?? gunOf(_simdi());

  /// Kaydırma olunca görünümler verilerini yeniden yüklesin diye artar.
  int _surum = 0;

  Timer? _geceYarisi;
  StreamSubscription<void>? _degisiklikAboneligi;
  Timer? _bildirimGecikmesi;

  bool get _canli => widget.bugunOverride == null;

  DateTime _simdi() => widget.simdiOverride?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (_canli) {
      WidgetsBinding.instance.addObserver(this);
      _geceYarisiniKur();
    }
    if (widget.bildirimleriYenile != null) {
      _degisiklikAboneligi = widget.depo.degisiklikler.listen(
        (_) => _bildirimleriYenile(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _geceYarisi?.cancel();
    _degisiklikAboneligi?.cancel();
    _bildirimGecikmesi?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tazele();
      // Telefon uykudayken zamanlayıcı kayabilir; yeniden kur.
      _geceYarisiniKur();
    }
  }

  void _geceYarisiniKur() {
    _geceYarisi?.cancel();
    final simdi = _simdi();
    final yarin = DateTime(simdi.year, simdi.month, simdi.day + 1);
    _geceYarisi = Timer(
      yarin.difference(simdi) + const Duration(seconds: 1),
      () {
        _tazele();
        _geceYarisiniKur();
      },
    );
  }

  Future<void> _tazele() async {
    final simdi = _simdi();
    final sonuclar = await KaydirmaServisi(
      widget.depo,
    ).bekleyenGunleriIsle(simdi);
    if (!mounted) return;
    final yeniBugun = gunOf(simdi);
    // Gün değiştiyse bugünün sabah özeti ve hatırlatıcıları kurulmalı.
    if (yeniBugun != _bugun) _bildirimleriYenile();
    if (yeniBugun != _bugun || sonuclar.isNotEmpty) {
      setState(() {
        _bugun = yeniBugun;
        _surum++;
      });
    }
  }

  /// Art arda gelen değişiklikleri (ör. kaydırmada onlarca plan) tek bir
  /// yeniden kurulumda toplar.
  void _bildirimleriYenile() {
    final yenile = widget.bildirimleriYenile;
    if (yenile == null) return;
    _bildirimGecikmesi?.cancel();
    _bildirimGecikmesi = Timer(const Duration(milliseconds: 500), () async {
      try {
        await yenile();
      } catch (e) {
        debugPrint('Takvim Takip: bildirimler kurulamadı: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Takvim Takip',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: AnaEkran(
        key: ValueKey(_surum),
        depo: widget.depo,
        bugun: _bugun,
        simdiSaat: widget.saatOverride ?? () => _simdi().hour,
      ),
    );
  }
}
