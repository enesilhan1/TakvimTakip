import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../claude/claude_ayarlari.dart';
import '../claude/claude_istemcisi.dart';
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

/// Ayarlar (docs/SPEC.md §7–§9): sabah bildirimi saati, yedekleme ve Claude.
class AyarlarEkrani extends StatefulWidget {
  final PlanDeposu depo;
  final DosyaKaydet dosyaKaydet;
  final DosyaSec dosyaSec;
  final AnahtarDeposu anahtarDeposu;

  /// Yedekteki zamanlar ve yedek alma anı için (testlerde sabitlenir).
  final DateTime Function() simdi;

  const AyarlarEkrani({
    super.key,
    required this.depo,
    this.dosyaKaydet = _sistemleKaydet,
    this.dosyaSec = _sistemleSec,
    this.anahtarDeposu = const GuvenliAnahtarDeposu(),
    this.simdi = DateTime.now,
  });

  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  int? _sabahSaati;
  String? _apiAnahtari;
  ClaudeModeli _model = ClaudeModeli.opus;
  bool _veriDegisti = false;
  bool _calisiyor = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final deger = await widget.depo.ayarOku(sabahSaatiAyari);
    final model = await widget.depo.ayarOku(claudeModelAyari);
    final anahtar = await widget.anahtarDeposu.oku();
    if (!mounted) return;
    setState(() {
      _sabahSaati = int.tryParse(deger ?? '') ?? varsayilanSabahSaati;
      _model = ClaudeModeli.idden(model);
      _apiAnahtari = anahtar;
    });
  }

  Future<void> _sabahSaatiniDegistir(int saat) async {
    setState(() => _sabahSaati = saat);
    // Değişiklik olayı bildirimleri yeniden kurar (bkz. main.dart).
    await widget.depo.ayarYaz(sabahSaatiAyari, '$saat');
  }

  Future<void> _modelDegistir(ClaudeModeli model) async {
    setState(() => _model = model);
    await widget.depo.ayarYaz(claudeModelAyari, model.id);
  }

  Future<void> _anahtarDuzenle() async {
    final sonuc = await showDialog<_AnahtarSonucu>(
      context: context,
      builder: (_) => _AnahtarPenceresi(varMi: _apiAnahtari != null),
    );
    switch (sonuc) {
      case null:
        return;
      case _AnahtarSil():
        await widget.anahtarDeposu.sil();
        _mesaj('API anahtarı silindi');
      case _AnahtarKaydet(:final anahtar):
        await widget.anahtarDeposu.yaz(anahtar);
        _mesaj('API anahtarı kaydedildi');
    }
    await _yukle();
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
            baslik('Claude asistanı'),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('API anahtarı'),
              subtitle: Text(
                _apiAnahtari == null
                    ? 'Girilmedi · console.anthropic.com → API Keys'
                    : 'Kayıtlı: ${anahtarMaskesi(_apiAnahtari!)}',
              ),
              onTap: _anahtarDuzenle,
            ),
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('Model'),
              subtitle: Text(
                '${_model.aciklama} · girdi \$${_fiyat(_model.girdiFiyati)}, '
                'çıktı \$${_fiyat(_model.ciktiFiyati)} / milyon token',
              ),
              trailing: DropdownButton<ClaudeModeli>(
                key: const Key('claude_model'),
                value: _model,
                items: [
                  for (final m in ClaudeModeli.hepsi)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.ad.replaceFirst('Claude ', '')),
                    ),
                ],
                onChanged: (m) {
                  if (m != null) _modelDegistir(m);
                },
              ),
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

String _fiyat(double d) =>
    d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);

sealed class _AnahtarSonucu {}

class _AnahtarKaydet extends _AnahtarSonucu {
  final String anahtar;
  _AnahtarKaydet(this.anahtar);
}

class _AnahtarSil extends _AnahtarSonucu {}

/// API anahtarı giriş penceresi.
class _AnahtarPenceresi extends StatefulWidget {
  final bool varMi;

  const _AnahtarPenceresi({required this.varMi});

  @override
  State<_AnahtarPenceresi> createState() => _AnahtarPenceresiState();
}

class _AnahtarPenceresiState extends State<_AnahtarPenceresi> {
  final _alan = TextEditingController();
  bool _gizli = true;
  String? _hata;

  @override
  void dispose() {
    _alan.dispose();
    super.dispose();
  }

  void _kaydet() {
    final a = _alan.text.trim();
    if (!a.startsWith('sk-ant-')) {
      setState(() => _hata = 'Anthropic API anahtarları "sk-ant-" ile başlar.');
      return;
    }
    Navigator.pop(context, _AnahtarKaydet(a));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Claude API anahtarı'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'console.anthropic.com → API Keys bölümünden bir anahtar oluştur '
            've buraya yapıştır. Anahtar telefonda şifreli saklanır, yedeğe '
            'girmez ve sadece Anthropic\'e gönderilir. Kullanım ücreti '
            'Anthropic hesabından düşer (claude.ai aboneliğinden ayrıdır).',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('api_anahtari'),
            controller: _alan,
            autofocus: true,
            obscureText: _gizli,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'sk-ant-...',
              border: const OutlineInputBorder(),
              errorText: _hata,
              suffixIcon: IconButton(
                tooltip: _gizli ? 'Göster' : 'Gizle',
                icon: Icon(_gizli ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _gizli = !_gizli),
              ),
            ),
            onSubmitted: (_) => _kaydet(),
          ),
        ],
      ),
      actions: [
        if (widget.varMi)
          TextButton(
            onPressed: () => Navigator.pop(context, _AnahtarSil()),
            child: const Text('Sil'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}
