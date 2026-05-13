<<<<<<< HEAD
# ContactsExport
=======
# Kişilerimi Yedekle
>>>>>>> f5d9db3 (docs: Türkçe README eklendi)

iPhone'daki tüm hesaplardaki (iCloud, Gmail, Exchange, Yerel) kişileri **Gmail** ve **Outlook/Hotmail** uyumlu vCard (.vcf) formatında dışa aktaran iOS uygulaması.

## Özellikler

- **Tüm hesaplardan export** — iCloud, Gmail, Exchange, CardDAV ve yerel kişilerin hepsi tek seferde
- **Akıllı duplike tespiti** — İsim, telefon ve e-posta bazlı 3 geçişli deduplikasyon
- **Mojibake temizleme** — UTF-8 karakter bozulması olan kişileri tespit eder (ör. `Ay≈üe` → `Ayşe`)
- **Toplu silme** — Duplike ve bozuk kişileri ön izleme ile inceleyip cihazdan silebilme
- **Parçalı export** — 5 MB ve 3000 kişi limitine göre otomatik dosya bölme (Google import limiti)
- **Gmail/Outlook uyumlu** — vCard 3.0, `\r\n` satır sonları, doğru encoding
- **Fotoğraf desteği** — Kişi fotoğrafları JPEG olarak sıkıştırılıp (maks. 300 KB) vCard'a eklenir
- **Zengin vCard alanları** — Doğum günü, sosyal profiller, takma ad, ilişkiler, anlık mesajlaşma
<<<<<<< HEAD
=======
- **Hızlı ve Güvenli** — Performans iyileştirmeleri ve güvenli dosya paylaşımı
>>>>>>> f5d9db3 (docs: Türkçe README eklendi)

## Ekran Görüntüsü

| Ana Ekran | Duplike Temizleme |
|:---------:|:-----------------:|
| Hesap listesi, kişi sayıları, export butonu | Silinecek kişilerin ön izlemesi |

## Gereksinimler

- iOS 18.0+
- Xcode 16+
- Swift 5

## Kurulum

```bash
git clone https://github.com/cemsungu/ContactsExport.git
cd ContactsExport
<<<<<<< HEAD
open ContactsExport.xcodeproj
```

Xcode'da hedef cihazı seçip **Run** (⌘R) ile çalıştırın.

## Kullanım

1. Uygulamayı açın ve **Devam Et** butonuna basın
2. **Tümünü Dışa Aktar** ile tüm kişileri vCard olarak paylaşın
3. Veya hesap bazında ayrı ayrı export edin
4. **Duplike & Bozuk Kişileri Temizle** ile gereksiz kişileri silin

### Gmail'e Aktarma

1. Export edilen `.vcf` dosyasını bilgisayara aktarın
2. [Google Contacts](https://contacts.google.com) → İçe Aktar → Dosya seç → İçe Aktar

### Outlook/Hotmail'e Aktarma

1. [Outlook People](https://outlook.live.com/people/) → Kişileri yönet → Kişileri içeri aktar
2. `.vcf` dosyasını seçin → İçeri Aktar

## Teknik Detaylar

- **CNContactStore** ile tüm container'lardan kişi okuma
- **CNContactVCardSerialization** çıktısı üzerine PHOTO, BDAY, NICKNAME, X-SOCIALPROFILE, X-ABRELATEDNAMES, IMPP eklenmesi
- Satır sonları: Apple çıktısı normalize edilip tek seferde `\r\n`'ye çevrilir (çift CR sorunu çözümü)
- Dosya yazımı `Data.write()` ile yapılır (platform line-ending dönüşümünü engeller)
- vCard line folding: 75 octet limiti, continuation satırları boşlukla başlar

## Lisans

MIT
=======
open ContactsExport.xcodeproj
>>>>>>> f5d9db3 (docs: Türkçe README eklendi)
