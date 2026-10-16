# Takvim Takip — Kurulum Rehberi

Bu rehber, Takvim Takip'i kendi Android telefonuna kurmak isteyenler için.
Bilgisayara, geliştirici araçlarına ya da hesap açmaya gerek yok.

- [Gereksinimler](#gereksinimler)
- [1. APK dosyasını indir](#1-apk-dosyasını-indir)
- [2. Telefona kur](#2-telefona-kur)
- [3. İlk açılış](#3-ilk-açılış)
- [4. (İsteğe bağlı) Claude asistanını bağla](#4-isteğe-bağlı-claude-asistanını-bağla)
- [Güncelleme](#güncelleme)
- [Yedekleme ve telefon değiştirme](#yedekleme-ve-telefon-değiştirme)
- [Sorun giderme](#sorun-giderme)
- [Gizlilik](#gizlilik)

---

## Gereksinimler

| | |
|---|---|
| Telefon | Android 7.0 veya üstü |
| Yer | ~60 MB |
| İnternet | Gerekmez (yalnızca isteğe bağlı Claude asistanı için) |
| iPhone | Şu an desteklenmiyor |

## 1. APK dosyasını indir

1. Telefonundan bu projenin GitHub sayfasındaki **Releases** bölümüne git:
   **[Son sürüm](https://github.com/enesilhan1/TakvimTakip/releases/latest)**
2. **Assets** altında `.apk` ile biten dosyaya dokun
   (ör. `TakvimTakip-1.0.0.apk`) ve indir.

> Bilgisayardan indirdiysen dosyayı telefona kabloyla, Google Drive'la ya da
> kendine e-postayla gönder.

## 2. Telefona kur

1. İndirilenlerden (ya da bildirimden) APK dosyasına dokun.
2. **"Bilinmeyen uygulamaları yükleme"** izni istenirse: *Ayarlar*'a dokun ve
   dosyayı açtığın uygulama (Chrome, Dosyalar, Drive…) için **İzin ver**'i aç,
   sonra geri dön.
3. **Yükle**'ye dokun.
4. **Play Protect** "tanınmayan uygulama" uyarısı gösterebilir. Uygulama Play
   Store'dan gelmediği için normaldir: *Ayrıntılar → Yine de yükle*.

## 3. İlk açılış

1. **Bildirim izni** sorulur → **İzin ver**. Sabah özeti ve planlardan
   5 dakika önceki hatırlatıcılar için gerekli.
2. **Pil ayarı (önerilir).** Bazı telefonlar (Xiaomi, Samsung, Huawei, Oppo…)
   pil tasarrufu için arka plan alarmlarını geciktirebilir:
   *Ayarlar → Uygulamalar → Takvim Takip → Pil* → **Kısıtlama yok** (ya da
   *Optimize etme*). Böylece gece yarısı kaydırması ve hatırlatıcılar tam
   zamanında çalışır. (Seçmesen de kaydırma, uygulamayı açtığında mutlaka
   yapılır.)
3. Hazır! Bir saate dokun, planını yaz.

### Nasıl çalışır (kısaca)

| | |
|---|---|
| Plan ekle | Boş bir saate dokun (ya da **+**). Tam saatte başlar, 1+ saat sürebilir. |
| İşaretle | Sağdaki daireye dokun → ✅ yapıldı. Karta dokun → yapıldı / iptal / düzenle / sil. |
| 📌 Sabit | Yapılmasa da hiç kaymaz (doktor randevusu gibi). |
| 🚫 İptal | Yapılmayacak ama ertelenmesin de. |
| Gün sonu | 23:59'da işaretlenmeyen planlar **sonraki plan saatine kayar**; oradaki plan bir sonrakine… Boş saatlere ve sabit planlara dokunulmaz. |
| Görünümler | Gün · Hafta (tablo) · Ay · Yıl (renkli kutucuklar ve istatistik) |

Ayrıntılı kurallar: [docs/SPEC.md](SPEC.md)

## 4. (İsteğe bağlı) Claude asistanını bağla

**Asistan** sekmesinde planlarını yazarak düzenletebilirsin:
*"Yarın 18:00'e 1 saatlik spor ekle"*, *"Bugünkü dersi cumartesiye al"*.
Claude önce bir **önizleme** gösterir; sen **Onayla** demeden hiçbir plan
değişmez.

Bunun için kendi Anthropic API anahtarın gerekir:

1. [console.anthropic.com](https://console.anthropic.com) adresinde hesap aç
   ya da giriş yap.
2. **Billing** bölümünden kredi yükle (ör. 5 $).
3. **API Keys → Create Key** ile bir anahtar oluştur ve kopyala
   (`sk-ant-` ile başlar).
4. Uygulamada **Asistan → Ayarlara git** → **API anahtarı** → yapıştır →
   **Kaydet**.

### Ücretlendirme hakkında

- API kullanımı **claude.ai aboneliğinden (Pro/Max) ayrıdır** ve aboneliğe
  dahil değildir. Console hesabına yüklediğin ön ödemeli krediden düşer.
- Kredi bitince istekler durur; kendiliğinden fazla ücret çekilmez.
  Console → Billing'den aylık harcama sınırı da koyabilirsin.
- Model *Ayarlar → Model*'den seçilir:

  | Model | Girdi / Çıktı (milyon token) | Not |
  |---|---|---|
  | Claude Opus 5.5 | 4 $ / 20 $ | Varsayılan, en akıllısı |
  | Claude Sonnet 5.5 | 2 $ / 10 $ | Hızlı, yaklaşık yarı fiyatına |
  | Claude Haiku 5.5 | 0,10 $ / 0,50 $ | En hızlı ve en ucuzu |

  "Yarına plan ekle" gibi tek bir istek Sonnet'te genellikle 1 sentin
  altındadır. Sohbet ekranının altında yaklaşık maliyet yazar.

## Güncelleme

Yeni sürümün APK'sını aynı şekilde indirip kur; mevcut uygulamanın üstüne
kurulur, **planların silinmez**. Önce kaldırmana gerek yok.

## Yedekleme ve telefon değiştirme

Planlar yalnızca telefonda saklanır (internet hesabı yok).

- **Yedek al:** ⚙ *Ayarlar → Yedeği dışa aktar* → dosyayı Drive'a ya da
  İndirilenler'e kaydet.
- **Yeni telefona taşı:** uygulamayı kur → ⚙ *Ayarlar → Yedekten geri yükle* →
  dosyayı seç.
- Claude API anahtarı güvenlik için yedeğe girmez; yeni telefonda tekrar gir.

Ara sıra yedek almanı öneririz.

## Sorun giderme

| Sorun | Çözüm |
|---|---|
| "Uygulama yüklenmedi" | Telefonda farklı imzalı eski bir sürüm olabilir. Önce yedek al, eskisini kaldır, sonra kur. |
| Bildirimler gelmiyor | *Ayarlar → Uygulamalar → Takvim Takip → Bildirimler* açık mı? Pil ayarını **Kısıtlama yok** yap ([İlk açılış](#3-ilk-açılış)). |
| Gece kaydırma olmamış | Pil kısıtlaması olabilir; uygulamayı açınca kaçırılan günler sırayla işlenir. |
| Asistan: "İnternet bağlantısı yok" | İnterneti kontrol et. Devam ediyorsa en son sürümü kur (1.0.0'ın ilk derlemelerinde internet izni eksikti). |
| Asistan: "API anahtarı geçersiz" | Anahtarı Console'dan yeniden kopyala; başında/sonunda boşluk olmasın. |
| Asistan: "bakiyesi yetersiz" | Console → Billing'den kredi yükle. |

## Gizlilik

- Planların **yalnızca telefonunda** saklanır; uygulamanın sunucusu yok,
  reklam ve izleme yok.
- Yalnızca Claude asistanını kullandığında, o sohbetin mesajları ve
  önümüzdeki 14 günün planları Anthropic'e (api.anthropic.com) gönderilir.
- API anahtarın telefonda Android Keystore ile şifreli saklanır.
