# RealTimeCaptionsTranslator Kullanım Kılavuzu

Bu doküman, uygulamanın kurulumu ve günlük kullanımı için uçtan uca adımları Türkçe olarak anlatır.

## 1. Uygulama Ne İşe Yarar?

`RealTimeCaptionsTranslator`, macOS üzerinde sistem sesini (ör. BlackHole üzerinden) dinleyip:

- Gerçek zamanlı İngilizce altyazı üretir
- Aynı anda Türkçe çeviri gösterir
- OpenAI Realtime WebRTC altyapısını kullanır

## 2. Gereksinimler

Kuruluma başlamadan önce:

- macOS 14 veya üzeri
- İnternet bağlantısı
- OpenAI API erişimi (Realtime model erişimi olan bir token)
- Sistem sesi yönlendirmek için sanal ses aygıtı (önerilen: BlackHole)
- Swift toolchain / Xcode Command Line Tools

## 3. Projeyi Çalıştırma (Önerilen Yöntem: Xcode)

Bu proje `Xcode` ile çalıştırılmak üzere yapılandırılmıştır.

### 3.1 Xcode ile Çalıştırma (Önerilen)

- `RealTimeCaptionsTranslator.xcodeproj` dosyasını Xcode ile açın
- `RealTimeCaptionsTranslator` uygulama target/scheme'ini seçin
- `Run` ile başlatın

Önemli:

- Xcode target'ının `App/Info.plist` kullandığından emin olun
- macOS izin pencereleri (TCC) Xcode çalıştırmasında daha stabil davranır

## 4. İlk Kurulum Akışı (Özet)

İlk kullanımda genel akış:

1. BlackHole (veya benzeri sanal input) kur
2. Sistem sesini BlackHole’a yönlendir
3. Uygulamayı Xcode'dan aç (önerilen)
4. Mikrofon/Audio izinlerini ver
5. OpenAI API token gir
6. Input Device olarak BlackHole’u seç
7. `Start` ile dinlemeyi başlat

## 5. BlackHole Kurulumu ve Ses Yönlendirme

Uygulama sistem sesini doğrudan değil, seçilen input aygıtı üzerinden alır. Bu yüzden sanal bir input gerekir.

### 5.1 BlackHole Kurulumu

- Uygulama içinden `Setup` veya `Open Setup` ile yönlendirme ekranını açabilirsiniz.
- BlackHole resmi sayfasına gidip indirip kurun.
- macOS güvenlik uyarılarında gerekli izin/onayları verin.

### 5.2 Sistem Sesini BlackHole’a Yönlendirme

Yöntem, kullandığınız ses kurulumuna göre değişebilir. Temel amaç:

- Uygulamanın dinlediği input aygıtı = `BlackHole`
- Çıkışınızı da duyabilmek için genelde Multi-Output Device / aggregate yapılandırması gerekir

Uygulama içinden yardımcı aksiyonlar:

- `Open Audio MIDI Setup`
- `Open Sound Input Settings`
- `Refresh Devices`

### 5.3 Uygulama İçinde Doğru Cihazı Seçme

- Input Device listesinden BlackHole cihazını seçin (`BlackHole 2ch`, `BlackHole 16ch` vb.)
- Uygulama BlackHole’u algıladığında kurulum uyarıları azalır

## 6. API Token Ayarı

### 6.1 Token Girme

- Uygulama içindeki ayarlar / preferences bölümüne gidin
- OpenAI API token alanına token girin
- `Apply` / kaydet akışını çalıştırın

### 6.2 Güvenlik Notu

- API token artık `UserDefaults` yerine macOS `Keychain` içinde saklanır
- Eski sürümlerde `UserDefaults` içine kaydedilmiş token varsa, uygulama açılışında Keychain’e taşınıp eski kayıt temizlenir

## 7. Uygulama Arayüzü ve Temel Kullanım

### 7.1 Başlatma

- Input Device seçili olmalı
- API token girilmiş olmalı
- `Start` ile başlatın

Başarılı durumda:

- Durum metni `Listening (Realtime)` benzeri bir ifade gösterir
- İngilizce panelde canlı altyazılar görünür
- Türkçe panelde canlı/final çeviri akışı görünür

### 7.2 Durdurma

- `Stop` ile oturumu durdurabilirsiniz
- Durum metni `Stopped` veya `Idle` olur

### 7.3 Temizleme ve Kopyalama

- `Clear` benzeri aksiyonlar İngilizce/Türkçe paneli temizler
- İngilizce ve Türkçe metinleri ayrı ayrı panoya kopyalayabilirsiniz

## 8. Ayarlar ve Ne İşe Yaradıkları

### 8.1 Model Seçimi

Desteklenen modeller:

- `gpt-realtime-mini` (varsayılan, daha düşük gecikme)
- `gpt-realtime`

Model değiştirildiğinde:

- Uygulama model erişimini test eder
- Başarı/başarısızlık popup mesajı gösterir
- Dinleme açıksa WebRTC oturumu yeniden başlatılabilir

### 8.2 Latency (Gecikme) Profili

- `Stable`: daha kararlı, daha geç final sonuç
- `Balanced` (varsayılan): canlı + final hibrit çeviri
- `Ultra Fast`: en agresif canlı çeviri, daha düşük gecikme

### 8.3 Keep Tech Words Original

- Açıkken teknik terimler/orijinal yazımlar korunmaya çalışılır
- Özellikle ürün adı, API adı, kod terimi, sürüm bilgisi için faydalıdır

### 8.4 Font Size

- Altyazı paneli yazı boyutunu ayarlar

## 9. Gerçek Zamanlı Çalışma Mantığı (Kullanıcı Perspektifi)

Uygulama hibrit çalışır:

- İngilizce altyazı paneli: konuşma transkripsiyon event’lerinden beslenir
- Türkçe panel:
  - Konuşma sürerken hızlı canlı parça çevirileri gelebilir
  - Cümle tamamlanınca final çeviri gönderilir

Bu yüzden Türkçe panelde aynı segment canlı/final geçişleri görülebilir; bu beklenen davranıştır.

## 10. İzinler (macOS)

İlk açılışta macOS sizden ses/mikrofon erişimi isteyebilir.

Önemli:

- Uygulama sistem sesini `BlackHole` gibi sanal bir input cihazı üzerinden alsa bile, macOS bunu `audio input capture` olarak değerlendirir
- Bu nedenle pratikte gereken izin kategorisi `Microphone` iznidir (gerçek mikrofon kullanmıyor olsanız bile)

- İzin verilmezse uygulama dinleme başlatamaz
- Gerekirse `System Settings > Privacy & Security` içinden tekrar izin verin

## 11. Sorun Giderme

### 11.1 BlackHole Görünmüyor

- BlackHole kurulumunu tamamladığınızdan emin olun
- `Audio MIDI Setup` ve ses kullanan uygulamaları kapatıp açın
- Uygulamada `Refresh Devices` yapın
- Gerekirse uygulamayı yeniden başlatın

### 11.2 Başlıyor Ama Altyazı Gelmiyor

- Input Device gerçekten BlackHole mu kontrol edin
- Sistem sesinin BlackHole’a yönlendirildiğini doğrulayın
- Oynatılan seste gerçekten konuşma/ingilizce içerik var mı kontrol edin
- `Start` sonrası durum metnini inceleyin

### 11.3 Model Erişim Hatası / 401 / 403

- API token geçerli mi kontrol edin
- Realtime model erişiminiz var mı kontrol edin
- Yanlış model seçili olabilir; model değiştirip tekrar deneyin

### 11.4 WebRTC Bağlantı Kopuyor

- İnternet bağlantısını kontrol edin
- Token/model erişimi testini tekrar çalıştırın
- `Stop` -> `Start` ile oturumu yeniden başlatın

### 11.5 İzin Penceresi Görünmüyor / Permission Denied

- `System Settings > Privacy & Security > Microphone` altında uygulama iznini kontrol edin
- BlackHole kullansanız bile kontrol etmeniz gereken bölüm `Microphone` bölümüdür
- Gerekirse TCC izinlerini resetleyip yeniden deneyin

## 12. Test Çalıştırma (İsteğe Bağlı)

Projede testler mevcut. Çalıştırmak için:

```bash
swift test
```

Eğer local build cache kaynaklı sorun yaşarsanız farklı scratch path ile çalıştırabilirsiniz:

```bash
swift test --scratch-path /tmp/offline-subtitles-tests
```

## 13. Kalıcı Ayarlar

Uygulama aşağıdaki ayarları sonraki açılış için hatırlar:

- Input device
- Model
- Latency preset
- Keep-tech toggle
- Font size
- API token (Keychain)

## 14. Hızlı Kullanım Kontrol Listesi

Günlük kullanım için kısa kontrol listesi:

1. Sistem sesini BlackHole’a yönlendir
2. Uygulamayı Xcode’dan aç (önerilen)
3. Input Device = BlackHole
4. API token hazır (gerekirse güncelle)
5. Model ve latency seç
6. `Start`
7. İngilizce/Türkçe panelleri izle
8. İş bitince `Stop`
