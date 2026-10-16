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

const ayAdlari = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

const _kisaGunAdlari = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// `Pzt`, `Sal`... (haftalık ve aylık görünüm başlıkları)
String kisaGunAdi(DateTime gun) => _kisaGunAdlari[gun.weekday - 1];

/// [gun]ün içinde bulunduğu haftanın pazartesisi.
DateTime haftaBasi(DateTime gun) => gunEkle(gunOf(gun), -(gun.weekday - 1));

/// [gun]ün içinde bulunduğu ayın ilk günü.
DateTime ayBasi(DateTime gun) => DateTime.utc(gun.year, gun.month, 1);

/// [gun]ün içinde bulunduğu ayın gün sayısı.
int aydakiGunSayisi(DateTime gun) =>
    DateTime.utc(gun.year, gun.month + 1, 0).day;

/// Haftanın başlığı: `19–25 Ekim 2026`, ay değişiyorsa `28 Eyl – 4 Eki 2026`,
/// yıl değişiyorsa `29 Ara 2025 – 4 Oca 2026`.
String haftaAraligiMetni(DateTime pazartesi) {
  final pazar = gunEkle(pazartesi, 6);
  String kisaAy(DateTime g) => ayAdlari[g.month - 1].substring(0, 3);
  if (pazartesi.month == pazar.month) {
    return '${pazartesi.day}–${pazar.day} ${ayAdlari[pazar.month - 1]} '
        '${pazar.year}';
  }
  if (pazartesi.year == pazar.year) {
    return '${pazartesi.day} ${kisaAy(pazartesi)} – ${pazar.day} '
        '${kisaAy(pazar)} ${pazar.year}';
  }
  return '${pazartesi.day} ${kisaAy(pazartesi)} ${pazartesi.year} – '
      '${pazar.day} ${kisaAy(pazar)} ${pazar.year}';
}

/// `19 Ekim 2026 Pazartesi`
String uzunTarih(DateTime gun) =>
    '${gun.day} ${ayAdlari[gun.month - 1]} ${gun.year} ${gunAdi(gun)}';

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
