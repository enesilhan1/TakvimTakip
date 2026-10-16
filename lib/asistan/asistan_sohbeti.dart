import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/plan_deposu.dart';
import '../logic/plan_islemleri.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';
import 'yz.dart';

/// Sohbet ekranında gösterilen bir öğe.
sealed class SohbetOgesi {}

class KullaniciMesaji extends SohbetOgesi {
  final String metin;
  KullaniciMesaji(this.metin);
}

class AsistanMesaji extends SohbetOgesi {
  final String metin;
  AsistanMesaji(this.metin);
}

/// Hata ya da durum bilgisi (ör. "önerisi geçersizdi").
class BilgiMesaji extends SohbetOgesi {
  final String metin;
  final bool hata;
  BilgiMesaji(this.metin, {this.hata = false});
}

enum OneriDurumu { bekliyor, onaylandi, reddedildi, hata }

/// Asistanın önerdiği değişiklikler; kullanıcı onaylayana kadar uygulanmaz.
class DegisiklikOnerisi extends SohbetOgesi {
  final String aciklama;
  final DegisiklikPlani plan;
  OneriDurumu durum = OneriDurumu.bekliyor;
  String? hataMesaji;
  final _karar = Completer<bool>();

  DegisiklikOnerisi(this.aciklama, this.plan);
}

/// Yapay zekâ asistanıyla plan sohbeti (docs/SPEC.md §9). Sağlayıcıdan
/// bağımsızdır; asıl API çağrıları [YzIstemcisi]'nde.
///
/// Asistana her mesajda güncel tarih ve önümüzdeki 14 günün planları
/// verilir. İki aracı var: `planlari_listele` (sadece okur, hemen çalışır)
/// ve `degisiklik_oner` (önerir; kullanıcı onaylayınca tek seferde
/// uygulanır).
class AsistanSohbeti extends ChangeNotifier {
  final PlanDeposu depo;
  final YzIstemcisi istemci;
  final DateTime Function() simdi;

  AsistanSohbeti({
    required this.depo,
    required this.istemci,
    this.simdi = DateTime.now,
  });

  final List<SohbetOgesi> ogeler = [];
  bool _calisiyor = false;
  double _maliyet = 0;
  bool _maliyetBilinmiyor = false;

  /// Asistan yanıt hazırlıyor mu (yazma göstergesi için).
  bool get calisiyor => _calisiyor;

  /// Bu sohbetin yaklaşık maliyeti (dolar). Elle yazılan modelde fiyat
  /// bilinmediği için null.
  double? get maliyet => _maliyetBilinmiyor ? null : _maliyet;

  /// Onay bekleyen öneri varsa yeni mesaj gönderilemez.
  bool get onayBekliyor => ogeler.any(
    (o) => o is DegisiklikOnerisi && o.durum == OneriDurumu.bekliyor,
  );

  String get _ad => istemci.model.saglayici.kisaAd;

  static const _enFazlaTur = 8;

  /// Kullanıcının mesajını gönderir ve asistanın turu bitene kadar
  /// (araç çağrıları ve onaylar dahil) devam eder.
  Future<void> gonder(String metin) async {
    final temiz = metin.trim();
    if (temiz.isEmpty || _calisiyor || onayBekliyor) return;

    ogeler.add(KullaniciMesaji(temiz));
    istemci.kullaniciEkle(await _baglam(), temiz);
    _calisiyor = true;
    notifyListeners();

    try {
      for (var tur = 0; tur < _enFazlaTur; tur++) {
        final yanit = await istemci.yanitAl(
          sistem: sistemIstemi,
          araclar: araclar,
        );
        final m = istemci.model.maliyet(yanit.kullanim);
        if (m == null) {
          _maliyetBilinmiyor = true;
        } else {
          _maliyet += m;
        }

        if (yanit.son == YanitSonu.ret) {
          ogeler.add(
            BilgiMesaji(
              '$_ad bu isteği yanıtlayamadı. Farklı bir şekilde sormayı dene.',
              hata: true,
            ),
          );
          break;
        }

        for (final t in yanit.metinler) {
          if (t.trim().isNotEmpty) ogeler.add(AsistanMesaji(t.trim()));
        }
        notifyListeners();

        if (yanit.son == YanitSonu.uzunluk) {
          ogeler.add(BilgiMesaji('Yanıt çok uzun olduğu için yarıda kesildi.'));
          break;
        }
        if (yanit.son != YanitSonu.arac || yanit.cagrilar.isEmpty) break;

        final sonuclar = <AracSonucu>[];
        for (final c in yanit.cagrilar) {
          sonuclar.add(await _aracCalistir(c));
        }
        istemci.sonuclariEkle(sonuclar);
        _calisiyor = true;
        notifyListeners();
      }
    } on YzHatasi catch (e) {
      ogeler.add(BilgiMesaji(e.mesaj, hata: true));
      // Yanıtsız kalan mesaj geçmişten geri alınır ki sohbet bozulmasın.
      istemci.geriAl();
    } finally {
      _calisiyor = false;
      notifyListeners();
    }
  }

  /// Önerilen değişikliği onaylar ya da reddeder (sohbet ekranındaki
  /// butonlar).
  void karar(DegisiklikOnerisi oneri, bool onay) {
    if (oneri._karar.isCompleted) return;
    oneri._karar.complete(onay);
  }

  /// Yeni sohbet: geçmişi temizler.
  void sifirla() {
    if (_calisiyor) return;
    ogeler.clear();
    istemci.temizle();
    _maliyet = 0;
    _maliyetBilinmiyor = false;
    notifyListeners();
  }

  Future<AracSonucu> _aracCalistir(AracCagrisi c) async {
    try {
      switch (c.ad) {
        case 'planlari_listele':
          return AracSonucu(c, await _listele(c.girdi));
        case 'degisiklik_oner':
          return AracSonucu(c, await _oner(c.girdi));
        default:
          return AracSonucu(c, 'Bilinmeyen araç: ${c.ad}', hata: true);
      }
    } on IslemHatasi catch (e) {
      ogeler.add(
        BilgiMesaji(
          'Asistanın önerisi uygulanamazdı: ${e.mesaj} '
          '(düzeltmesi istendi.)',
        ),
      );
      notifyListeners();
      return AracSonucu(
        c,
        'Öneri geçersiz, hiçbir şey değişmedi: ${e.mesaj}',
        hata: true,
      );
    }
  }

  Future<String> _listele(Map<String, dynamic> girdi) async {
    final bas = tarihCoz('${girdi['baslangic']}', 'baslangic');
    final bit = tarihCoz('${girdi['bitis']}', 'bitis');
    if (bit.isBefore(bas)) {
      throw IslemHatasi('"bitis" "baslangic"tan önce olamaz.');
    }
    if (bit.difference(bas).inDays > 92) {
      throw IslemHatasi('En fazla 93 günlük aralık listelenebilir.');
    }
    final planlar = await depo.araliktakiPlanlar(bas, bit);
    if (planlar.isEmpty) return 'Bu aralıkta plan yok.';
    return planlar.map(planSatiri).join('\n');
  }

  Future<String> _oner(Map<String, dynamic> girdi) async {
    final aciklama = (girdi['aciklama'] as String?)?.trim() ?? '';
    final ham = girdi['islemler'];
    if (ham is! List) throw IslemHatasi('"islemler" bir liste olmalı.');
    final islemler = [
      for (final m in ham) PlanIslemi.jsondan(Map<String, dynamic>.from(m)),
    ];

    final bugunGun = gunOf(simdi());
    final idler = {
      for (final i in islemler)
        if (i
            case Guncelle(:final planId) ||
                Sil(:final planId) ||
                DurumDegistir(:final planId))
          planId,
    };
    final planGunleri = <int, DateTime>{};
    for (final id in idler) {
      final p = await depo.planGetir(id);
      if (p != null) planGunleri[id] = p.gun;
    }
    final mevcut = <Plan>[];
    for (final g in etkilenenGunler(islemler, (id) => planGunleri[id])) {
      mevcut.addAll(await depo.gununPlanlari(g));
    }

    final plan = islemleriDogrula(islemler, mevcut, bugun: bugunGun);
    final oneri = DegisiklikOnerisi(aciklama, plan);
    ogeler.add(oneri);
    _calisiyor = false;
    notifyListeners();

    final onay = await oneri._karar.future;
    if (!onay) {
      oneri.durum = OneriDurumu.reddedildi;
      notifyListeners();
      return 'Kullanıcı bu öneriyi REDDETTİ, hiçbir şey değişmedi. '
          'Neyi farklı istediğini sorabilirsin.';
    }
    try {
      await depo.topluUygula(
        eklenecek: plan.eklenecek,
        guncellenecek: plan.guncellenecek,
        silinecek: plan.silinecek,
      );
    } catch (e) {
      oneri.durum = OneriDurumu.hata;
      oneri.hataMesaji = '$e';
      notifyListeners();
      return 'Kullanıcı onayladı ama uygulanamadı, hiçbir şey değişmedi: $e';
    }
    oneri.durum = OneriDurumu.onaylandi;
    notifyListeners();
    return 'Kullanıcı onayladı ve değişiklikler uygulandı:\n'
        '${plan.onizleme.join('\n')}';
  }

  /// Her kullanıcı mesajının başına eklenen güncel durum.
  Future<String> _baglam() async {
    final s = simdi();
    final bugunGun = gunOf(s);
    final son = gunEkle(bugunGun, 13);
    final planlar = await depo.araliktakiPlanlar(bugunGun, son);
    final saat =
        '${s.hour.toString().padLeft(2, '0')}:'
        '${s.minute.toString().padLeft(2, '0')}';
    return [
      '<baglam>',
      'Şu an: ${uzunTarih(bugunGun)}, saat $saat '
          '(bugün: ${gunAnahtari(bugunGun)}).',
      'Bugünden ${gunAnahtari(son)} tarihine kadarki planlar:',
      if (planlar.isEmpty) '(bu aralıkta plan yok)',
      ...planlar.map(planSatiri),
      '</baglam>',
    ].join('\n');
  }
}

/// Asistana gösterilen tek satırlık plan:
/// `#3 · 2026-10-16 Cuma · 15:00–17:00 · Ders · işaretsiz · not: türev`
String planSatiri(Plan p) => [
  '#${p.id}',
  '${gunAnahtari(p.gun)} ${gunAdi(p.gun)}',
  p.sure == 1
      ? '${saatMetni(p.baslangicSaati)}–${saatMetni(p.bitisSaati)}'
      : p.saatAraligi,
  p.baslik,
  p.durum.name,
  if (p.sabit) 'sabit',
  if (p.yapilmadiSayisi > 0) '${p.yapilmadiSayisi} kez yapılmadı',
  if (p.not.isNotEmpty) 'not: ${p.not}',
].join(' · ');

/// Asistanın araçları. Sabit tutulur (istem önbelleği bozulmasın).
const List<AracTanimi> araclar = [
  AracTanimi(
    ad: 'planlari_listele',
    aciklama:
        'Verilen tarih aralığındaki (ikisi dahil) bütün planları listeler. '
        'Bağlamda verilen 14 günün dışındaki tarihler için kullan. '
        'Sadece okur, hiçbir şeyi değiştirmez.',
    sema: {
      'type': 'object',
      'properties': {
        'baslangic': {'type': 'string', 'description': 'YYYY-AA-GG'},
        'bitis': {'type': 'string', 'description': 'YYYY-AA-GG'},
      },
      'required': ['baslangic', 'bitis'],
    },
  ),
  AracTanimi(
    ad: 'degisiklik_oner',
    aciklama:
        'Planlarda değişiklik ÖNERİR. Kullanıcıya önizleme gösterilir; '
        'kullanıcı onaylarsa hepsi birlikte uygulanır, reddederse hiçbiri. '
        'Sonuç olarak onaylanıp onaylanmadığını öğrenirsin. Birbiriyle '
        'ilgili bütün değişiklikleri tek çağrıda, uygulanacak sırayla ver.',
    sema: {
      'type': 'object',
      'properties': {
        'aciklama': {
          'type': 'string',
          'description': 'Kullanıcıya gösterilecek tek cümlelik özet.',
        },
        'islemler': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'tur': {
                'type': 'string',
                'enum': ['ekle', 'guncelle', 'sil', 'durum'],
                'description':
                    'ekle: yeni plan (baslik, gun, baslangic_saati zorunlu). '
                    'guncelle: plan_id ile mevcut planı değiştir; sadece '
                    'verilen alanlar değişir. sil: plan_id. durum: plan_id '
                    've durum.',
              },
              'plan_id': {'type': 'integer'},
              'baslik': {'type': 'string'},
              'not': {'type': 'string'},
              'gun': {'type': 'string', 'description': 'YYYY-AA-GG'},
              'baslangic_saati': {
                'type': 'integer',
                'description': 'Tam saat, 0-23',
              },
              'sure': {
                'type': 'integer',
                'description':
                    'Saat cinsinden, en az 1; gece yarısını '
                    'geçemez',
              },
              'sabit': {'type': 'boolean'},
              'durum': {
                'type': 'string',
                'enum': ['isaretsiz', 'yapildi', 'iptal'],
              },
            },
            'required': ['tur'],
          },
        },
      },
      'required': ['aciklama', 'islemler'],
    },
  ),
];

/// Sistem istemi. Sabit tutulur (istem önbelleği bozulmasın); değişen
/// bilgiler (tarih, planlar) her kullanıcı mesajının başında `<baglam>`
/// içinde.
const sistemIstemi = '''
Sen "Takvim Takip" uygulamasının içindeki asistansın. Kullanıcı kişisel
saatlik planlarını yönetiyor; sen onun planlarını düzenlemesine yardım
ediyorsun. Türkçe, kısa ve samimi yanıt ver.

Uygulamanın kuralları:
- Planlar tam saatte başlar ve tam saat sürer (13:00 ya da 13:00–15:00).
  Aynı gün içinde çakışamazlar, gece yarısını geçemezler.
- Durumlar: isaretsiz, yapildi, iptal. Gün 23:59'da kapanınca işaretsiz ve
  sabit olmayan planlar "yürüyen bant" ile kayar: yapılmayan plan bir sonraki
  doldurulmuş saat dilimine geçer, oradaki plan bir sonrakine... Boş saatlere
  ve sabit planlara dokunulmaz. "iptal" edilen plan kaymaz.
- Sabit (📌) planlar hiç kaymaz.
- Geçmiş günlere plan eklenemez ve taşınamaz; geçmişteki planların sadece
  durumu değiştirilebilir.

Nasıl çalışırsın:
- Her kullanıcı mesajının başında <baglam> içinde şu anki tarih/saat ve
  önümüzdeki 14 günün planları (#kimlik ile) var. Daha uzak tarihler için
  planlari_listele aracını kullan.
- Planları değiştirmek için HER ZAMAN degisiklik_oner aracını kullan. Araç
  sonucu onaylandığını söylemeden değişikliğin yapıldığını söyleme.
  Reddedilirse ısrar etme; ne istediğini sor.
- "Yarın", "cumartesi", "akşam" gibi ifadeleri bağlamdaki bugüne göre
  çöz. Akşam ≈ 18:00–21:00, sabah ≈ 08:00–11:00, öğlen ≈ 12:00–14:00 gibi
  makul varsayımlar yap ama emin olmadığın önemli bir şey varsa (hangi
  plan, hangi gün) önce kısaca sor.
- Bir planı başka bir saate taşırken o saatte başka plan varsa çakışmayı
  önle: boş bir saat öner ya da kullanıcıya sor.
- Kodlama, uygulamanın kendisini değiştirme gibi istekler senin işin
  değil; nazikçe sadece planlarla yardımcı olabileceğini söyle.
''';
