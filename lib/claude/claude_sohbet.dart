import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/plan_deposu.dart';
import '../logic/plan_islemleri.dart';
import '../models/plan.dart';
import '../utils/tarih.dart';
import 'claude_istemcisi.dart';

/// Sohbet ekranında gösterilen bir öğe.
sealed class SohbetOgesi {}

class KullaniciMesaji extends SohbetOgesi {
  final String metin;
  KullaniciMesaji(this.metin);
}

class ClaudeMesaji extends SohbetOgesi {
  final String metin;
  ClaudeMesaji(this.metin);
}

/// Hata ya da durum bilgisi (ör. "Claude'un önerisi geçersizdi").
class BilgiMesaji extends SohbetOgesi {
  final String metin;
  final bool hata;
  BilgiMesaji(this.metin, {this.hata = false});
}

enum OneriDurumu { bekliyor, onaylandi, reddedildi, hata }

/// Claude'un önerdiği değişiklikler; kullanıcı onaylayana kadar uygulanmaz.
class DegisiklikOnerisi extends SohbetOgesi {
  final String aciklama;
  final DegisiklikPlani plan;
  OneriDurumu durum = OneriDurumu.bekliyor;
  String? hataMesaji;
  final _karar = Completer<bool>();

  DegisiklikOnerisi(this.aciklama, this.plan);
}

/// Claude ile plan sohbeti (docs/SPEC.md §9).
///
/// Claude'a her mesajda güncel tarih ve önümüzdeki 14 günün planları verilir.
/// İki aracı var: `planlari_listele` (sadece okur, hemen çalışır) ve
/// `degisiklik_oner` (önerir; kullanıcı onaylayınca tek seferde uygulanır).
/// Sohbet geçmişi API'ye hiç değiştirilmeden, sadece sonuna eklenerek
/// gönderilir (düşünme blokları dahil).
class ClaudeSohbeti extends ChangeNotifier {
  final PlanDeposu depo;
  final ClaudeIstemcisi istemci;
  final DateTime Function() simdi;

  ClaudeSohbeti({
    required this.depo,
    required this.istemci,
    this.simdi = DateTime.now,
  });

  final List<SohbetOgesi> ogeler = [];
  final List<Map<String, Object?>> _gecmis = [];
  bool _calisiyor = false;
  double _maliyet = 0;

  /// Claude yanıt hazırlıyor mu (yazma göstergesi için).
  bool get calisiyor => _calisiyor;

  /// Bu sohbetin yaklaşık maliyeti (dolar).
  double get maliyet => _maliyet;

  /// Onay bekleyen öneri varsa yeni mesaj gönderilemez.
  bool get onayBekliyor => ogeler.any(
    (o) => o is DegisiklikOnerisi && o.durum == OneriDurumu.bekliyor,
  );

  static const _enFazlaTur = 8;

  /// Kullanıcının mesajını gönderir ve Claude'un turu bitene kadar
  /// (araç çağrıları ve onaylar dahil) devam eder.
  Future<void> gonder(String metin) async {
    final temiz = metin.trim();
    if (temiz.isEmpty || _calisiyor || onayBekliyor) return;

    ogeler.add(KullaniciMesaji(temiz));
    _gecmis.add({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': await _baglam()},
        {'type': 'text', 'text': temiz},
      ],
    });
    _calisiyor = true;
    notifyListeners();

    try {
      for (var tur = 0; tur < _enFazlaTur; tur++) {
        final yanit = await istemci.mesajGonder(
          sistem: sistemIstemi,
          araclar: araclar,
          mesajlar: _gecmis,
        );
        _maliyet += istemci.model.maliyet(
          yanit['usage'] as Map<String, dynamic>?,
        );
        final icerik = (yanit['content'] as List).cast<Map<String, dynamic>>();
        // Yanıt olduğu gibi geçmişe eklenir (düşünme blokları dahil).
        _gecmis.add({'role': 'assistant', 'content': icerik});

        final stop = yanit['stop_reason'];
        if (stop == 'refusal') {
          ogeler.add(
            BilgiMesaji(
              'Claude bu isteği yanıtlayamadı. Farklı bir şekilde sormayı dene.',
              hata: true,
            ),
          );
          break;
        }

        for (final blok in icerik) {
          if (blok['type'] == 'text') {
            final t = (blok['text'] as String).trim();
            if (t.isNotEmpty) ogeler.add(ClaudeMesaji(t));
          }
        }
        notifyListeners();

        if (stop == 'max_tokens') {
          ogeler.add(BilgiMesaji('Yanıt çok uzun olduğu için yarıda kesildi.'));
          break;
        }
        if (stop != 'tool_use') break;

        final sonuclar = <Map<String, Object?>>[];
        for (final blok in icerik.where((b) => b['type'] == 'tool_use')) {
          sonuclar.add(await _aracCalistir(blok));
        }
        // Bütün araç sonuçları tek bir mesajda geri gönderilir.
        _gecmis.add({'role': 'user', 'content': sonuclar});
        _calisiyor = true;
        notifyListeners();
      }
    } on ClaudeHatasi catch (e) {
      ogeler.add(BilgiMesaji(e.mesaj, hata: true));
      _sonMesajiGeriAl();
    } finally {
      _calisiyor = false;
      notifyListeners();
    }
  }

  /// Hata olursa yanıtsız kalan son kullanıcı mesajı geçmişten çıkarılır;
  /// yoksa sonraki istekte art arda iki kullanıcı mesajı gider.
  void _sonMesajiGeriAl() {
    while (_gecmis.isNotEmpty && _gecmis.last['role'] == 'user') {
      final icerik = _gecmis.last['content'] as List;
      final aracSonucu = icerik.any((b) => (b as Map)['type'] == 'tool_result');
      if (aracSonucu) {
        // Araç sonucunu silmek onu isteyen yanıtı yetim bırakır; ikisini de.
        _gecmis.removeLast();
        if (_gecmis.isNotEmpty) _gecmis.removeLast();
      } else {
        _gecmis.removeLast();
        break;
      }
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
    _gecmis.clear();
    _maliyet = 0;
    notifyListeners();
  }

  Future<Map<String, Object?>> _aracCalistir(Map<String, dynamic> blok) async {
    final id = blok['id'] as String;
    final girdi = Map<String, dynamic>.from(blok['input'] as Map);

    Map<String, Object?> sonuc(String metin, {bool hata = false}) => {
      'type': 'tool_result',
      'tool_use_id': id,
      'content': metin,
      if (hata) 'is_error': true,
    };

    try {
      switch (blok['name']) {
        case 'planlari_listele':
          return sonuc(await _listele(girdi));
        case 'degisiklik_oner':
          return sonuc(await _oner(girdi));
        default:
          return sonuc('Bilinmeyen araç: ${blok['name']}', hata: true);
      }
    } on IslemHatasi catch (e) {
      ogeler.add(
        BilgiMesaji(
          'Claude\'un önerisi uygulanamazdı: ${e.mesaj} '
          '(Claude\'dan düzeltmesi istendi.)',
        ),
      );
      notifyListeners();
      return sonuc(
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

/// Claude'a gösterilen tek satırlık plan:
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

/// Claude'un araçları. Sabit tutulur (istem önbelleği bozulmasın).
final List<Map<String, Object?>> araclar = [
  {
    'name': 'planlari_listele',
    'description':
        'Verilen tarih aralığındaki (ikisi dahil) bütün planları listeler. '
        'Bağlamda verilen 14 günün dışındaki tarihler için kullan. '
        'Sadece okur, hiçbir şeyi değiştirmez.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'baslangic': {'type': 'string', 'description': 'YYYY-AA-GG'},
        'bitis': {'type': 'string', 'description': 'YYYY-AA-GG'},
      },
      'required': ['baslangic', 'bitis'],
    },
  },
  {
    'name': 'degisiklik_oner',
    'description':
        'Planlarda değişiklik ÖNERİR. Kullanıcıya önizleme gösterilir; '
        'kullanıcı onaylarsa hepsi birlikte uygulanır, reddederse hiçbiri. '
        'Sonuç olarak onaylanıp onaylanmadığını öğrenirsin. Birbiriyle '
        'ilgili bütün değişiklikleri tek çağrıda, uygulanacak sırayla ver.',
    'input_schema': {
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
  },
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
