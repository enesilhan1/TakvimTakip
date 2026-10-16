# Takvim Takip — Spesifikasyon

Kişisel kullanım için saatlik plan takip uygulaması. Bu doküman, kodlamaya
başlamadan önce üzerinde anlaşılan kuralların tek kaynağıdır. Kural değişirse
önce bu dosya güncellenir.

## 1. Genel

| Konu | Karar |
|---|---|
| Platform | Android (APK). Flutter ile yazılır, ileride iOS eklenebilir. |
| Veri | Sadece telefonda (yerel veritabanı). İnternet/senkronizasyon yok. |
| Dil | Türkçe |
| Kullanıcı | Tek kullanıcı, giriş yok |

## 2. Plan ve slot

- Her gün 24 saatlik bir çizelgedir (00:00–24:00).
- Planlar **sadece tam saatlerde** başlar ve **tam saat** sürer:
  `13:00 Ders` (1 saat) veya `13:00–15:00 Ders` (2 saat). İki tür aynı günde
  birlikte kullanılabilir.
- Aynı gün içinde planlar **çakışamaz**. Bir günde en fazla 24 saatlik plan olur.
- Bir plan gece yarısını geçemez (en geç 24:00'te biter).
- Bir planın kapladığı saat aralığına **slot** denir.
- Plana dokunmadığın (hiçbir şey yazılmamış) saatler **boş saattir**. Boş
  saatlere hiçbir zaman otomatik plan yerleştirilmez (uyku saatlerin korunur).

### Plan alanları
- Başlık (zorunlu), not (isteğe bağlı)
- Başlangıç saati, süre (saat)
- 📌 **Sabit** mi? (sabit planlar hiçbir zaman kaymaz)
- Durum: `işaretsiz` / `yapıldı` / `iptal`
- **Yapılmadı sayacı:** plan kaç kez yapılmadan ertesi güne kaydı

## 3. Durumlar

| Durum | Anlamı | 23:59'da ne olur |
|---|---|---|
| ⏳ işaretsiz | Henüz işaretlenmedi | Kaydırılabilir plansa **kayar** |
| ✅ yapıldı | Yapıldı | Yerinde kalır |
| 🚫 iptal | Yapılmayacak, ertelenmesin de | Yerinde kalır, kaymaz, kimseyi itmez, sayacı artırmaz |

- İşaretleme için son saat günün sonudur (23:59). 13:00'teki plan 18:00'de
  "yapıldı" olarak işaretlenebilir.
- Sabit plan işaretlenmezse kaymaz, o gün "yapılmadı" olarak kalır.

## 4. Kaydırma kuralı: "yürüyen bant"

Gün 23:59'da kapanır. O günün **işaretsiz ve sabit olmayan** planları kayar.

**Ana fikir:** Slotlar (saat aralıkları) yerinde kalır, planların **içeriği**
zaman sırasıyla bir sonraki slota geçer.

Kurallar:

1. **Bant**: Kapanan günden sonraki, sabit olmayan ve işaretsiz tüm planların
   slotları zaman sırasına dizilir. Sabit planlar, yapıldı/iptal olarak
   işaretlenmiş gelecek planlar ve boş saatler banda dahil değildir, atlanır.
2. Kapanan günün yapılmayan planları (zaman sırasıyla) bandın **başına**
   eklenir. Bandaki herkes yapılmayan plan sayısı kadar ileri kayar.
3. İçerik girdiği slotun **saat aralığını ve süresini alır** (1 saatlik plan
   2 saatlik slota girerse 2 saat olur, tersi de geçerlidir).
4. **Zincirin sonu**: Bantta yeri kalmayan plan, bir önceki slotun **ertesi
   gününe, aynı saat aralığına** yerleşir. O aralık o gün başka bir planla
   çakışıyorsa bir gün daha ileri gider (çakışmayan ilk güne kadar).
5. **Yapılmadı sayacı** sadece yapılmayan (kapanan günden kayan) planlarda
   1 artar. Sadece itildiği için kayan planların sayacı artmaz.
6. **Geçmiş kaydı**: Kapanan günde, kayan planın yerinde soluk bir kayıt kalır:
   `Kitap okuma — yapılmadı → Salı 13:00'e kaydı`.

### Örnek 1 (temel senaryo)

```
Pazartesi                    Salı (önce)          Salı (sonra)
13:00 Ders    ✅             13:00 Ders           13:00 Kitap   (sayaç 1)
14:00 Spor    ✅             14:00 📌 Spor        14:00 📌 Spor (atlanır)
15:00 Kitap   ⏳ yapılmadı   15:00 Kitap2         15:00 Ders
                                                  → Kitap2 bandın bir sonraki
                                                    slotuna (Çarşamba...) itilir
```

### Örnek 2 (boş saatler korunur)
Salı'da sadece 09:00 ve 20:00'de plan var. Pazartesi'den kayan plan 09:00'a
girer, 09:00'daki 20:00'ye gider. Salı'nın 10:00–19:00 arası boş saatleri boş
kalır.

### Örnek 3 (birden fazla yapılmayan)
Pazartesi 13:00 A ve 15:00 B yapılmadı. Salı'nın ilk slotuna A, ikincisine B
gelir, bandaki her plan **iki** sıra kayar.

### Örnek 4 (zincirin sonu)
Gelecekte sadece Salı 13:00 X var. Pazartesi'den kayan K → Salı 13:00. X'in
gidecek slotu yok → Çarşamba 13:00 (Çarşamba 13:00 doluysa Perşembe 13:00 ...).
Gelecekte hiç plan yoksa kayan plan ertesi günün aynı saatine gider.

### Örnek 5 (süre slotla gelir)
Pazartesi 15:00 Kitap (1 saat) yapılmadı. Salı'nın ilk slotu 13:00–15:00 Ders
(2 saat). Kitap Salı 13:00–15:00 olur, Ders bir sonraki slotun süresini alır.

### Örnek 6 (iptal)
Pazartesi 15:00 Kahve 🚫 iptal → hiçbir şey kaymaz.

## 5. Kaçırılan günler

Android uygulamayı arka planda durdurabilir ya da telefon kapalı olabilir.
Uygulama her açılışta (ve arka plan görevinde) **en son işlenen günü** kontrol
eder. Eksik günleri **eskiden yeniye sırayla** işler. Sonuç, kaydırma her gün
zamanında çalışmış gibi olur.

## 6. Görünümler

- **Gün**: 24 satır (00:00–23:00). Boş saate dokun → plan ekle; plana dokun →
  düzenle / işaretle / sil.
- **Hafta**: e-tablo gibi; satırlar saat, sütunlar gün.
- **Ay**: takvim ızgarası; her günde plan sayısı ve tamamlanma (ör. `3/4`).
  Güne dokun → gün görünümü.
- **Yıl**: GitHub katkı grafiği tarzı 365 kutu; tamamlanma oranı arttıkça koyu.
- Kullanıcı plan eklerken: güne dokunur, sonra saate dokunur, yazar.

## 7. Bildirimler

- **Sabah özeti** (varsayılan 09:00, ayarlanabilir):
  `Dün 1 plan yapılmadı, 4 plan kaydı. Bugün 3 planın var: 13:00 Kitap, ...`
  Dokununca bugünün gün görünümü açılır.
- **Plan hatırlatıcısı**: her planın başlamasından 5 dakika önce.
- Kaydırmadan sonra hatırlatıcılar yeniden kurulur.

## 8. Yedekleme

Ayarlar ekranında JSON dosyasına **dışa aktar** / dosyadan **içe aktar**.

## 9. Claude entegrasyonu (Aşama 9)

- Uygulama içinde sohbet: "yarınki dersi 18:00'e al" gibi komutlarla Claude
  planları düzenler.
- Kullanıcı kendi Claude API anahtarını ayarlara girer (kullanım başına
  ücretlendirilir, claude.ai aboneliğinden ayrıdır).
- Claude değişiklikleri **önce önizleme** olarak gösterir, kullanıcı onaylarsa
  uygulanır.
- Sohbet sırasında ilgili planlar Anthropic'e gönderilir; başka hiçbir veri
  telefondan çıkmaz.

## 10. Yol haritası

| Aşama | İçerik |
|---|---|
| 0 | Proje iskeleti, spesifikasyon, git deposu |
| 1 | Veri modeli + yerel veritabanı |
| 2 | Kaydırma motoru + otomatik testler (bu dokümandaki örnekler) |
| 3 | Gün görünümü: plan ekle/düzenle/sil, sabit, durum işaretleme |
| 4 | Haftalık ve aylık görünüm |
| 5 | Yıllık görünüm + istatistik |
| 6 | 23:59 otomatik kaydırma (arka plan) + kaçırılan günler + bildirimler |
| 7 | Yedekleme (JSON) + ayarlar |
| 8 | APK derleme, telefona kurulum |
| 9 | Claude entegrasyonu |
