import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/plan_deposu.dart';
import 'data/veritabani.dart';
import 'logic/kaydirma_servisi.dart';
import 'ui/ana_ekran.dart';
import 'utils/tarih.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final depo = PlanDeposu(await Veritabani.ac());
  // Açılışta kapanmış ama işlenmemiş günleri kaydır (SPEC §5).
  await KaydirmaServisi(depo).bekleyenGunleriIsle(DateTime.now());

  runApp(TakvimTakipApp(depo: depo));
}

class TakvimTakipApp extends StatefulWidget {
  final PlanDeposu depo;

  /// Testlerde sabit bir "bugün" ve "şu anki saat" vermek için. Sabit bugün
  /// verilirse gün değişimi takip edilmez.
  final DateTime? bugunOverride;
  final int Function()? saatOverride;

  /// Testlerde saati ilerletmek için (verilmezse telefonun saati).
  final DateTime Function()? simdiOverride;

  const TakvimTakipApp({
    super.key,
    required this.depo,
    this.bugunOverride,
    this.saatOverride,
    this.simdiOverride,
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

  bool get _canli => widget.bugunOverride == null;

  DateTime _simdi() => widget.simdiOverride?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (_canli) {
      WidgetsBinding.instance.addObserver(this);
      _geceYarisiniKur();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _geceYarisi?.cancel();
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
    if (yeniBugun != _bugun || sonuclar.isNotEmpty) {
      setState(() {
        _bugun = yeniBugun;
        _surum++;
      });
    }
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
