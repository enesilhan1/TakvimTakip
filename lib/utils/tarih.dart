/// Saatsiz tarih (gün) yardımcıları.
///
/// Uygulamada "gün" her zaman UTC gece yarısı olarak tutulur
/// (`DateTime.utc(yıl, ay, gün)`). Böylece gün ekleyip çıkarırken yaz saati
/// gibi saat dilimi kaymaları hesabı bozmaz.
library;

/// [t] tarihinin saat bilgisini atıp gün olarak döndürür.
DateTime gunOf(DateTime t) => DateTime.utc(t.year, t.month, t.day);

/// Bugünün tarihi (telefonun yerel saatine göre).
DateTime bugun() => gunOf(DateTime.now());

/// [gun]e [n] gün ekler (negatif olabilir).
DateTime gunEkle(DateTime gun, int n) =>
    DateTime.utc(gun.year, gun.month, gun.day + n);

/// Veritabanında saklanan biçim: `2026-10-16`. Alfabetik sıra = tarih sırası.
String gunAnahtari(DateTime gun) {
  final y = gun.year.toString().padLeft(4, '0');
  final m = gun.month.toString().padLeft(2, '0');
  final d = gun.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// [gunAnahtari] biçimindeki metni tekrar güne çevirir.
DateTime gunAnahtarindan(String anahtar) {
  final p = anahtar.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

const _gunAdlari = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

/// Türkçe gün adı: `Pazartesi`, `Salı`...
String gunAdi(DateTime gun) => _gunAdlari[gun.weekday - 1];

/// `13:00` biçiminde saat metni.
String saatMetni(int saat) => '${saat.toString().padLeft(2, '0')}:00';

/// Saate gelen yönelme eki, saatin okunuşuna göre:
/// 13:00'e (on üç), 10:00'a (on), 06:00'ya (altı), 20:00'ye (yirmi).
String saatYonelmeEki(int saat) {
  const sonRakamaGore = [
    "'a",
    "'e",
    "'ye",
    "'e",
    "'e",
    "'e",
    "'ya",
    "'ye",
    "'e",
    "'a",
  ];
  if (saat == 20) return "'ye";
  return sonRakamaGore[saat % 10];
}
