import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../asistan/asistan_ayarlari.dart';
import '../asistan/asistan_sohbeti.dart';
import '../asistan/istemciler.dart';
import '../asistan/yz.dart';
import '../data/plan_deposu.dart';
import 'ayarlar_ekrani.dart';

/// Yapay zekâ asistanıyla plan sohbeti (docs/SPEC.md §9).
///
/// Asistan değişiklik önerdiğinde önizleme kartı çıkar; kullanıcı onaylamadan
/// hiçbir plan değişmez.
class SohbetEkrani extends StatefulWidget {
  final PlanDeposu depo;
  final AnahtarDeposu anahtarDeposu;

  /// Testlerde sahte API için.
  final http.Client? httpIstemcisi;
  final DateTime Function()? simdi;

  const SohbetEkrani({
    super.key,
    required this.depo,
    this.anahtarDeposu = const GuvenliAnahtarDeposu(),
    this.httpIstemcisi,
    this.simdi,
  });

  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani> {
  AsistanSohbeti? _sohbet;
  YzModeli _model = Saglayici.anthropic.varsayilanModel;
  bool _yuklendi = false;
  final _alan = TextEditingController();
  final _kaydirma = ScrollController();

  static const _oneriler = [
    'Bugün neler var?',
    'Yarın 18:00\'e 1 saatlik spor ekle',
    'Bu haftanın planlarını özetle',
  ];

  @override
  void initState() {
    super.initState();
    _hazirla();
  }

  @override
  void dispose() {
    _sohbet?.dispose();
    _alan.dispose();
    _kaydirma.dispose();
    super.dispose();
  }

  /// Anahtar ve model ayarlarına göre sohbeti kurar (ayarlar değişince
  /// yeniden).
  Future<void> _hazirla() async {
    final model = await seciliModel(widget.depo);
    final anahtar = await widget.anahtarDeposu.oku(model.saglayici);
    if (!mounted) return;

    final eski = _sohbet;
    final ayniKaldi =
        eski != null &&
        eski.istemci.apiAnahtari == anahtar &&
        eski.istemci.model == model;
    if (!ayniKaldi) {
      eski?.dispose();
      _sohbet = anahtar == null
          ? null
          : (AsistanSohbeti(
              depo: widget.depo,
              simdi: widget.simdi ?? DateTime.now,
              istemci: istemciOlustur(
                apiAnahtari: anahtar,
                model: model,
                httpIstemcisi: widget.httpIstemcisi,
              ),
            )..addListener(_degisti));
    }
    setState(() {
      _model = model;
      _yuklendi = true;
    });
  }

  void _degisti() {
    setState(() {});
    // Yeni mesajda en alta kaydır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_kaydirma.hasClients) {
        _kaydirma.animateTo(
          _kaydirma.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _gonder([String? metin]) {
    final s = _sohbet;
    final t = (metin ?? _alan.text).trim();
    if (s == null || t.isEmpty || s.calisiyor || s.onayBekliyor) return;
    _alan.clear();
    s.gonder(t);
  }

  Future<void> _ayarlar() async {
    await ayarlariAc(context, widget.depo);
    await _hazirla();
  }

  @override
  Widget build(BuildContext context) {
    final s = _sohbet;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Asistan', style: Theme.of(context).textTheme.titleMedium),
            Text(_model.ad, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (s != null && s.ogeler.isNotEmpty)
            IconButton(
              tooltip: 'Yeni sohbet',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: s.calisiyor ? null : s.sifirla,
            ),
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _ayarlar,
          ),
        ],
      ),
      body: !_yuklendi
          ? const SizedBox.shrink()
          : s == null
          ? _anahtarYok(context)
          : Column(
              children: [
                Expanded(
                  child: s.ogeler.isEmpty
                      ? _bos(context)
                      : ListView(
                          controller: _kaydirma,
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final o in s.ogeler) _oge(context, s, o),
                            if (s.calisiyor)
                              _Dusunuyor(_model.saglayici.kisaAd),
                          ],
                        ),
                ),
                _girdi(context, s),
              ],
            ),
    );
  }

  Widget _anahtarYok(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.key_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Asistanın planlarını düzenleyebilmesi için '
            '${_model.saglayici.ad} API anahtarını ayarlara gir.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _model.saglayici.anahtarSayfasi,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _ayarlar,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Ayarlara git'),
          ),
        ],
      ),
    ),
  );

  Widget _bos(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Planlarınla ilgili bir şey sor ya da değiştirmesini iste.\n'
            'Asistan önce önerir; sen onaylamadan hiçbir şey değişmez.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final o in _oneriler)
                ActionChip(label: Text(o), onPressed: () => _gonder(o)),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _oge(BuildContext context, AsistanSohbeti s, SohbetOgesi o) {
    final renk = Theme.of(context).colorScheme;
    return switch (o) {
      KullaniciMesaji(:final metin) => _Balon(
        metin: metin,
        sagda: true,
        renk: renk.primaryContainer,
      ),
      AsistanMesaji(:final metin) => _Balon(
        metin: metin,
        sagda: false,
        renk: renk.surfaceContainerHigh,
      ),
      BilgiMesaji(:final metin, :final hata) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Text(
          metin,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: hata ? renk.error : renk.onSurfaceVariant,
          ),
        ),
      ),
      DegisiklikOnerisi() => _OneriKarti(
        oneri: o,
        onKarar: (onay) => s.karar(o, onay),
      ),
    };
  }

  Widget _girdi(BuildContext context, AsistanSohbeti s) {
    final kapali = s.calisiyor || s.onayBekliyor;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((s.maliyet ?? 0) > 0)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2),
                  child: Text(
                    'Bu sohbet ≈ \$${s.maliyet!.toStringAsFixed(3)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('sohbet_girdisi'),
                    controller: _alan,
                    enabled: !kapali,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _gonder(),
                    decoration: InputDecoration(
                      hintText: s.onayBekliyor
                          ? 'Önce öneriyi onayla ya da reddet'
                          : 'Asistana yaz…',
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Gönder',
                  icon: const Icon(Icons.send),
                  onPressed: kapali ? null : _gonder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Balon extends StatelessWidget {
  final String metin;
  final bool sagda;
  final Color renk;

  const _Balon({required this.metin, required this.sagda, required this.renk});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: sagda ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: renk,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(metin),
      ),
    );
  }
}

class _Dusunuyor extends StatelessWidget {
  final String ad;

  const _Dusunuyor(this.ad);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('$ad düşünüyor…', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Önerilen değişikliklerin önizlemesi ve Onayla / Reddet.
class _OneriKarti extends StatelessWidget {
  final DegisiklikOnerisi oneri;
  final ValueChanged<bool> onKarar;

  const _OneriKarti({required this.oneri, required this.onKarar});

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    final metin = Theme.of(context).textTheme;
    return Card.outlined(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_calendar, size: 18, color: renk.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    oneri.aciklama.isEmpty
                        ? 'Önerilen değişiklikler'
                        : oneri.aciklama,
                    style: metin.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final satir in oneri.plan.onizleme)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(satir),
              ),
            const SizedBox(height: 4),
            switch (oneri.durum) {
              OneriDurumu.bekliyor => Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => onKarar(false),
                    child: const Text('Reddet'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => onKarar(true),
                    icon: const Icon(Icons.check),
                    label: const Text('Onayla'),
                  ),
                ],
              ),
              OneriDurumu.onaylandi => _Etiket(
                '✅ Uygulandı',
                renk: Colors.green,
              ),
              OneriDurumu.reddedildi => _Etiket(
                'Reddedildi, hiçbir şey değişmedi',
                renk: renk.outline,
              ),
              OneriDurumu.hata => _Etiket(
                'Uygulanamadı: ${oneri.hataMesaji}',
                renk: renk.error,
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _Etiket extends StatelessWidget {
  final String metin;
  final Color renk;

  const _Etiket(this.metin, {required this.renk});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      metin,
      style: TextStyle(color: renk, fontWeight: FontWeight.w600),
    ),
  );
}
