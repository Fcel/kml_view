# KeMaL — Kurulum Talimatları

## Gereksinimler
- Flutter SDK 3.x
- Android Studio veya Xcode
- Google Maps API Key

---

## Android Build

1. `android/local.properties` dosyası oluştur:
```
sdk.dir=/path/to/android/sdk
flutter.sdk=/path/to/flutter
flutter.versionName=1.0.0
flutter.versionCode=1
GOOGLE_MAPS_API_KEY=AIza...senin-key
```

2. Build:
```bash
flutter pub get
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`

---

## iOS Build

1. `ios/Flutter/Debug.xcconfig` ve `Release.xcconfig` içindeki API key'i güncelle:
```
GOOGLE_MAPS_API_KEY = AIza...senin-key
```

2. Build:
```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
```

---

## WhatsApp'tan KML Gönderme

Android:
- WhatsApp'ta dosyayı tut → Paylaş → KeMaL seç

iOS:
- Dosyalar uygulamasından veya mail'den → Paylaş → KeMaL ile Aç
