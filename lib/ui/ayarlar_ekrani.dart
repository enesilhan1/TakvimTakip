import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/plan_deposu.dart';
import '../logic/bildirim_plani.dart';
import '../logic/kaydirma_servisi.dart';
import '../logic/yedek.dart';
import '../utils/tarih.dart';

/// Yedek dosyasını kaydeder; kullanıcı vazgeçerse `false`.
typedef DosyaKaydet = Future<bool> Function(String dosyaAdi, Uint8List veri);

/// Kullanıcıya bir dosya seçtirip içeriğini döndürür; vazgeçerse `null`.
typedef DosyaSec = Future<String?> Function();

Future<bool> _sistemleKaydet(String dosyaAdi, Uint8List veri) async {
  final yer = await FilePicker.saveFile(
    fileName: dosyaAdi,
    bytes: veri,
    mimeType: 'application/json',
    dialogTitle: 'Yedeği kaydet',
  );
  return yer != null;
}

Future<String?> _sistemleSec() async {
  final dosyalar = await FilePicker.pickFiles(dialogTitle: 'Yedek dosyası seç');
  if (dosyalar.isEmpty) return null;
  return utf8.decode(await dosyalar.first.readAsBytes());
}

/// Ayarlar ekranını açar. Veriler değiştiyse (yedek yüklendiyse) `true`.
Future<bool> ayarlariAc(BuildContext context, PlanDeposu depo) async {
  final sonuc = await Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => AyarlarEkrani(depo: depo)));
  return sonuc ?? false;
}

/// Görünümlerin üst çubuğundaki ⚙ butonu.
class AyarlarButonu extends StatelessWidget {
  final PlanDeposu depo;

  /// Yedek yüklenince (görünüm verilerini yeniden yüklesin).
  final VoidCallback onVeriDegisti;

  const AyarlarButonu({
    super.key,
    required this.depo,
    required this.onVeriDegisti,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Ayarlar',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () async {
        if (await ayarlariAc(context, depo)) onVeriDegisti();
      },
    );
  }
}

/// Ayarlar (docs/SPEC.md §7–§8): sabah bildirimi saati ve yedekleme.
class AyarlarEkrani extends StatefulWidget {
  final PlanDeposu depo;
  final DosyaKaydet dosyaKaydet;
  final DosyaSec dosyaSec;

  /// Yedekteki zamanlar ve yedek alma anı için (testlerde sabitlenir).
  final DateTime Function() simdi;

  const AyarlarEkrani({
    super.key,
    required this.depo,
    this.dosyaKaydet = _sistemleKaydet,
    this.dosyaSec = _sistemleSec,
    this.simdi = DateTime.now,
  });

  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  int? _sabahSaati;
  bool _veriDegisti = false;
  bool _calisiyor = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final deger = await widget.depo.ayarOku(sabahSaatiAyari);
    if (!mounted) return;
    setState(() {
      _sabahSaati = int.tryParse(deger ?? '') ?? varsayilanSabahSaati;
    });
  }

  Future<void> _sabahSaatiniDegistir(int saat) async {
    setState(() => _sabahSaati = saat);
    // Değişiklik olayı bildirimleri yeniden kurar (bkz. main.dart).
    await widget.depo.ayarYaz(sabahSaatiAyari, '$saat');
  }

  void _mesaj(String metin) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(metin)));
  }

  Future<void> _calistir(Future<void> Function() islem) async {
    if (_calisiyor) return;
    setState(() => _calisiyor = true);
    try {
      await islem();
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  Future<void> _disaAktar() => _calistir(() async {
    try {
      final yedek = await widget.depo.yedekAl(widget.simdi());
      final kaydedildi = await widget.dosyaKaydet(
        yedek.dosyaAdi(),
        utf8.encode(yedek.jsonMetni()),
      );
      if (kaydedildi) {
        _mesaj('Yedek kaydedildi: ${yedek.planlar.length} plan');
      }
    } catch (e) {
      _mesaj('Yedek kaydedilemedi: $e');
    }
  });

  Future<void> _iceAktar() => _calistir(() async {
    final String? metin;
    try {
      metin = await widget.dosyaSec();
    } catch (e) {
      _mesaj('Dosya açılamadı: $e');
      return;
    }
    if (metin == null || !mounted) return;

    final Yedek yedek;
    try {
      yedek = Yedek.coz(metin);
    } on YedekHatasi catch (e) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Yedek yüklenemedi'),
          content: Text(e.mesaj),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;

    final t = yedek.olusturma;
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yedek yüklensin mi?'),
        content: Text(
          'Yedek: ${uzunTarih(t)} '
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')} · '
          '${yedek.planlar.length} plan\n\n'
          'Telefondaki bütün planlar silinip yedektekiler yüklenecek. '
          'Bu geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yükle'),
          ),
        ],
      ),
    );
    if (onay != true) return;

    await widget.depo.yedektenYukle(yedek);
    // Yedek eskiyse aradaki günler sırayla kaydırılır (SPEC §5).
    await KaydirmaServisi(widget.depo).bekleyenGunleriIsle(widget.simdi());
    _veriDegisti = true;
    await _yukle();
    _mesaj('Yedek yüklendi: ${yedek.planlar.length} plan');
  });

  @override
  Widget build(BuildContext context) {
    final metin = Theme.of(context).textTheme;
    Widget baslik(String yazi) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        yazi,
        style: metin.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _veriDegisti);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Ayarlar')),
        body: ListView(
          children: [
            baslik('Bildirimler'),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Sabah özeti saati'),
              subtitle: const Text(
                'Dünün özeti ve bugünün planları bu saatte gelir',
              ),
              trailing: _sabahSaati == null
                  ? null
                  : DropdownButton<int>(
                      key: const Key('sabah_saati'),
                      value: _sabahSaati,
                      items: [
                        for (var s = 0; s < 24; s++)
                          DropdownMenuItem(value: s, child: Text(saatMetni(s))),
                      ],
                      onChanged: (s) {
                        if (s != null) _sabahSaatiniDegistir(s);
                      },
                    ),
            ),
            const ListTile(
              leading: Icon(Icons.alarm),
              title: Text('Plan hatırlatıcısı'),
              subtitle: Text('Her plan başlamadan 5 dakika önce'),
            ),
            baslik('Yedekleme'),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Yedeği dışa aktar'),
              subtitle: const Text(
                'Bütün planları bir dosyaya kaydet (Drive, indirilenler…)',
              ),
              enabled: !_calisiyor,
              onTap: _disaAktar,
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Yedekten geri yükle'),
              subtitle: const Text('Telefondaki planların yerine yedektekiler'),
              enabled: !_calisiyor,
              onTap: _iceAktar,
            ),
            baslik('Hakkında'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Takvim Takip'),
              subtitle: Text(
                'Yapılmayan planlar gün sonunda sonraki planların yerine kayar.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
