# Takvim Takip

Kişisel kullanım için saatlik plan takip uygulaması (Flutter, Android).

Yapılmadı olarak kalan planlar gün sonunda otomatik olarak sonraki plan
slotlarına kayar ("yürüyen bant"). Boş saatlere ve sabit planlara dokunulmaz.

Tüm kurallar ve yol haritası: [docs/SPEC.md](docs/SPEC.md)

## Geliştirme

```bash
flutter pub get
flutter test
flutter run            # bağlı telefon veya emülatörde çalıştırır
flutter build apk      # build/app/outputs/flutter-apk/app-release.apk
```
