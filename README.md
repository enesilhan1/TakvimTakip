# Takvim Takip

Kişisel kullanım için saatlik plan takip uygulaması (Flutter, Android).

Yapılmadı olarak kalan planlar gün sonunda otomatik olarak sonraki plan
slotlarına kayar ("yürüyen bant"). Boş saatlere ve sabit planlara dokunulmaz.

Tüm kurallar ve yol haritası: [docs/SPEC.md](docs/SPEC.md)

## Telefona kurulum

APK dosyası: `build/app/outputs/flutter-apk/app-release.apk`

**Yol 1: USB kablosuyla**
1. Telefonda *Ayarlar → Telefon hakkında → Yapı numarası*'na 7 kez dokun
   (Geliştirici seçenekleri açılır).
2. *Ayarlar → Sistem → Geliştirici seçenekleri → USB hata ayıklama*'yı aç.
3. Telefonu bağla, telefonda çıkan "USB hata ayıklamaya izin ver" sorusuna
   izin ver ve bilgisayarda çalıştır:
   ```bash
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

**Yol 2: Dosyayı telefona atarak**
1. APK'yı telefona gönder (Drive, kablo, e-posta…).
2. Telefonda dosyaya dokun; "bilinmeyen uygulamaları yükle" izni sorulursa
   o uygulama (ör. Dosyalar) için izin ver.

**İlk açılışta**
- Bildirim izni sorulur: **İzin ver** (sabah özeti ve hatırlatıcılar için).
- Bazı telefonlar (Xiaomi, Samsung, Huawei…) pil tasarrufu için arka plan
  alarmlarını geciktirebilir. *Ayarlar → Uygulamalar → Takvim Takip → Pil*
  bölümünden **Kısıtlama yok / Optimize etme** seçilirse gece yarısı kaydırması
  ve hatırlatıcılar tam zamanında çalışır. (Seçilmese bile kaydırma, uygulama
  açılınca mutlaka yapılır.)

**Güncelleme**: Yeni APK'yı aynı şekilde kur; veriler silinmez.

## Sürüm imzası (önemli)

Sürüm APK'sı `android/takvim_takip.jks` anahtarıyla imzalanır, şifreleri
`android/key.properties` dosyasındadır. İkisi de git'e **girmez**.

- Bu iki dosyayı güvenli bir yere (ör. kişisel bulut) **yedekle**.
- Kaybolurlarsa yeni sürüm telefondakinin üstüne kurulamaz; uygulamayı silip
  yeniden kurmak gerekir (önce uygulamadan yedek al: *Ayarlar → Yedeği dışa
  aktar*).
- Dosyalar yoksa derleme debug anahtarına düşer (o da yalnızca bu
  bilgisayarda geçerlidir).

## Geliştirme

```bash
flutter pub get
flutter test
flutter run                  # bağlı telefon veya emülatörde çalıştırır
flutter build apk --release  # build/app/outputs/flutter-apk/app-release.apk
```

Gereksinimler: Flutter 3.41+, JDK 21 (`flutter config --jdk-dir` ile; Android
Studio'nun içindeki Java 25 Gradle 8.14 ile çalışmaz), Android SDK.
