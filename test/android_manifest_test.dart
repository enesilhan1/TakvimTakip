import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sürüm (release) APK'sının ana manifest'inde olması gereken izinler.
/// Flutter INTERNET'i yalnızca debug/profile manifest'lerine koyar; ana
/// manifest'te unutulursa Claude asistanı telefonda internete çıkamaz
/// (testler ve debug sürümü yine de çalıştığı için fark edilmez).
void main() {
  test('ana manifest gerekli izinleri içerir', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final izin in [
      'android.permission.INTERNET',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.USE_EXACT_ALARM',
      'android.permission.RECEIVE_BOOT_COMPLETED',
    ]) {
      expect(manifest, contains('android:name="$izin"'), reason: izin);
    }
  });
}
