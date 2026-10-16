import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Seçili Claude modelinin ayar anahtarı (veritabanındaki ayarlar tablosu;
/// gizli değil, yedeğe girer).
const claudeModelAyari = 'claude_model';

/// Claude API anahtarının saklandığı yer.
///
/// Anahtar gizli olduğu için veritabanına (ve JSON yedeğine) yazılmaz;
/// Android Keystore ile şifrelenmiş depoda tutulur.
abstract class AnahtarDeposu {
  Future<String?> oku();
  Future<void> yaz(String anahtar);
  Future<void> sil();
}

class GuvenliAnahtarDeposu implements AnahtarDeposu {
  static const _ad = 'claude_api_anahtari';
  final _depo = const FlutterSecureStorage();

  const GuvenliAnahtarDeposu();

  @override
  Future<String?> oku() => _depo.read(key: _ad);

  @override
  Future<void> yaz(String anahtar) => _depo.write(key: _ad, value: anahtar);

  @override
  Future<void> sil() => _depo.delete(key: _ad);
}

/// Testler için bellekte tutan depo.
class BellekAnahtarDeposu implements AnahtarDeposu {
  String? deger;

  BellekAnahtarDeposu([this.deger]);

  @override
  Future<String?> oku() async => deger;

  @override
  Future<void> yaz(String anahtar) async => deger = anahtar;

  @override
  Future<void> sil() async => deger = null;
}

/// Ekranda gösterilecek maskeli hali: `sk-ant-…a1b2`.
String anahtarMaskesi(String anahtar) {
  if (anahtar.length <= 12) return '••••';
  return '${anahtar.substring(0, 7)}…${anahtar.substring(anahtar.length - 4)}';
}
