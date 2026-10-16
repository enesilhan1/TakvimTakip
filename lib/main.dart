import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/plan_deposu.dart';
import 'data/veritabani.dart';
import 'logic/kaydirma_servisi.dart';
import 'ui/gun_gorunumu.dart';
import 'utils/tarih.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final depo = PlanDeposu(await Veritabani.ac());
  // Açılışta kapanmış ama işlenmemiş günleri kaydır (SPEC §5).
  await KaydirmaServisi(depo).bekleyenGunleriIsle(DateTime.now());

  runApp(TakvimTakipApp(depo: depo));
}

class TakvimTakipApp extends StatelessWidget {
  final PlanDeposu depo;

  /// Testlerde sabit bir "bugün" vermek için.
  final DateTime? bugunOverride;

  const TakvimTakipApp({super.key, required this.depo, this.bugunOverride});

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
      home: GunGorunumu(depo: depo, bugun: bugunOverride ?? bugun()),
    );
  }
}
