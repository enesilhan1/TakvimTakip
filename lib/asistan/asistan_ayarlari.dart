import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/plan_deposu.dart';
import 'yz.dart';

/// Seçili sağlayıcının ayar anahtarı (veritabanındaki ayarlar tablosu;
/// gizli değil, yedeğe girer).
const asistanSaglayiciAyari = 'asistan_saglayici';

/// Her sağlayıcının seçili modeli ayrı saklanır (geri dönünce hatırlansın).
String modelAyari(Saglayici s) => 'asistan_model_${s.name}';

/// Eski sürümde (yalnızca Claude varken) model bu anahtarla saklanıyordu.
const _eskiClaudeModelAyari = 'claude_model';

/// Seçili sağlayıcı ve modeli okur.
Future<YzModeli> seciliModel(PlanDeposu depo) async {
  final s = Saglayici.adindan(await depo.ayarOku(asistanSaglayiciAyari));
  return s.model(await modelOku(depo, s));
}

/// [s] sağlayıcısında seçili model kimliği (yoksa null → varsayılan).
Future<String?> modelOku(PlanDeposu depo, Saglayici s) async {
  final id = await depo.ayarOku(modelAyari(s));
  if (id != null || s != Saglayici.anthropic) return id;
  return depo.ayarOku(_eskiClaudeModelAyari);
}

/// API anahtarlarının saklandığı yer.
///
/// Anahtarlar gizli olduğu için veritabanına (ve JSON yedeğine) yazılmaz;
/// Android Keystore ile şifrelenmiş depoda tutulur. Her sağlayıcının
/// anahtarı ayrıdır.
abstract class AnahtarDeposu {
  Future<String?> oku(Saglayici s);
  Future<void> yaz(Saglayici s, String anahtar);
  Future<void> sil(Saglayici s);
}

class GuvenliAnahtarDeposu implements AnahtarDeposu {
  final _depo = const FlutterSecureStorage();

  const GuvenliAnahtarDeposu();

  /// Claude anahtarı eski sürümdeki adıyla kalır (güncellemede kaybolmasın).
  static String _ad(Saglayici s) => s == Saglayici.anthropic
      ? 'claude_api_anahtari'
      : 'api_anahtari_${s.name}';

  @override
  Future<String?> oku(Saglayici s) => _depo.read(key: _ad(s));

  @override
  Future<void> yaz(Saglayici s, String anahtar) =>
      _depo.write(key: _ad(s), value: anahtar);

  @override
  Future<void> sil(Saglayici s) => _depo.delete(key: _ad(s));
}

/// Testler için bellekte tutan depo.
class BellekAnahtarDeposu implements AnahtarDeposu {
  final Map<Saglayici, String> degerler;

  BellekAnahtarDeposu([Map<Saglayici, String>? degerler])
    : degerler = degerler ?? {};

  @override
  Future<String?> oku(Saglayici s) async => degerler[s];

  @override
  Future<void> yaz(Saglayici s, String anahtar) async => degerler[s] = anahtar;

  @override
  Future<void> sil(Saglayici s) async => degerler.remove(s);
}

/// Ekranda gösterilecek maskeli hali: `sk-ant-…a1b2`.
String anahtarMaskesi(String anahtar) {
  if (anahtar.length <= 12) return '••••';
  return '${anahtar.substring(0, 7)}…${anahtar.substring(anahtar.length - 4)}';
}

/// Girilen anahtarın biçimi; sorun varsa Türkçe açıklama, yoksa null.
String? anahtarBicimHatasi(Saglayici s, String anahtar) {
  if (anahtar.isEmpty) return 'Anahtar boş olamaz.';
  if (anahtar.contains(' ')) return 'Anahtarda boşluk olmamalı.';
  final onek = s.anahtarOneki;
  if (onek != null && !anahtar.startsWith(onek)) {
    return '${s.kisaAd} API anahtarları "$onek" ile başlar.';
  }
  if (anahtar.length < 20) return 'Anahtar çok kısa; tamamını yapıştır.';
  return null;
}
