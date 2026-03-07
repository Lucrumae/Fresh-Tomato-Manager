# 🍅 Tomato Manager

Aplikasi mobile untuk mengelola router FreshTomato. Support Android & iOS.
UI modern minimalis, bisa digunakan dari dalam WiFi rumah maupun via VPN dari luar jaringan.

---

## ✨ Fitur

| Fitur | Keterangan |
|-------|-----------|
| 📊 Dashboard | CPU, RAM, uptime, WAN/LAN IP, WiFi SSID |
| 📱 Devices | Daftar perangkat terhubung, rename, filter |
| 🚫 Block Device | Blokir akses internet perangkat tertentu |
| 📈 Bandwidth | Grafik real-time download/upload |
| 📋 Logs | System log dengan filter error/warning |
| ⚡ QoS | Atur batas bandwidth per perangkat |
| 🔌 Port Forward | Kelola port forwarding |
| 🔔 Notifikasi | Alert saat perangkat baru terhubung |
| 🌐 VPN | Akses router dari luar jaringan via OpenVPN |
| 🔁 Reboot | Restart router dari jarak jauh |

---

## 📋 Prasyarat

### Software yang dibutuhkan

1. **Flutter SDK** 3.0+
   ```bash
   # Install via https://flutter.dev/docs/get-started/install
   flutter --version  # pastikan >= 3.0.0
   ```

2. **Android Studio** (untuk Android) atau **Xcode** (untuk iOS/Mac)

3. **Git**

---

## 🚀 Cara Menjalankan

### 1. Clone & install dependencies

```bash
git clone <repo-url>
cd tomato_manager
flutter pub get
```

### 2. Jalankan di emulator / device

```bash
# Cek device yang tersedia
flutter devices

# Jalankan di Android
flutter run -d android

# Jalankan di iOS (butuh Mac + Xcode)
flutter run -d ios
```

---

## 📦 Build APK (Android)

```bash
# Debug APK (untuk testing)
flutter build apk --debug

# Release APK (untuk distribusi)
flutter build apk --release

# APK tersimpan di:
# build/app/outputs/flutter-apk/app-release.apk
```

### Install APK langsung ke HP Android:
```bash
flutter install
# atau manual: kirim APK via kabel USB, aktifkan "Install unknown apps"
```

---

## 🍎 Build iOS

> **Catatan:** Build iOS **harus** di Mac dengan Xcode terinstall.

```bash
# Setup iOS
cd ios && pod install && cd ..

# Build IPA
flutter build ios --release

# Buka di Xcode untuk signing & distribusi
open ios/Runner.xcworkspace
```

### Untuk testing tanpa App Store (TestFlight):
1. Buka `ios/Runner.xcworkspace` di Xcode
2. Pilih Team di Signing & Capabilities
3. Product → Archive → Distribute App

---

## ⚙️ Konfigurasi Router

### Pertama kali setup:
1. Pastikan HP terhubung ke WiFi router yang sama
2. Buka app → tap "Get Started"
3. Masukkan IP router (biasanya `192.168.1.1` atau `192.168.0.1`)
4. Username & password (default: `admin` / `admin`)
5. Tap "Connect"

### Cari IP router:
- **Android:** Settings → WiFi → tap nama WiFi → Gateway
- **iOS:** Settings → WiFi → (i) → Router
- **Windows:** `ipconfig` di CMD → Default Gateway
- **Mac/Linux:** `ip route` atau `netstat -nr`

---

## 🌐 Akses dari Luar Jaringan (VPN)

### Setup OpenVPN di FreshTomato router:
1. Buka web UI router → **VPN → OpenVPN Server**
2. Enable server, set port (default: **1194 UDP**)
3. Konfigurasi sesuai kebutuhan, klik Save
4. Download file `.ovpn` dari halaman tersebut
5. Di app: **Settings → VPN → paste isi file .ovpn → Save**

### Port yang perlu di-forward ke ISP:
- UDP 1194 (OpenVPN default)
- Atau sesuai port yang dikonfigurasi

### Penggunaan:
- **Di rumah (WiFi):** App langsung konek, tanpa VPN
- **Di luar (mobile data):** Settings → VPN → aktifkan toggle → app konek via VPN

---

## 🏗️ Struktur Project

```
lib/
├── main.dart               # Entry point
├── theme/
│   └── app_theme.dart      # Warna, font, komponen UI
├── models/
│   └── models.dart         # Data models (RouterStatus, Device, dll)
├── services/
│   ├── router_api.dart     # HTTP API ke FreshTomato
│   ├── app_state.dart      # State management (Riverpod)
│   └── notification_service.dart
└── screens/
    ├── setup_screen.dart   # Halaman koneksi pertama kali
    ├── main_shell.dart     # Bottom navigation shell
    ├── dashboard_screen.dart
    ├── devices_screen.dart
    ├── bandwidth_screen.dart
    ├── logs_screen.dart
    ├── settings_screen.dart
    ├── qos_screen.dart
    ├── port_forward_screen.dart
    └── vpn_screen.dart
```

---

## 🔧 Cara Kerja Komunikasi ke Router

App berkomunikasi dengan FreshTomato melalui endpoint HTTP yang sudah ada:

| Endpoint | Fungsi |
|----------|--------|
| `POST /update.cgi` `exec=sysinfo` | CPU, RAM, uptime |
| `POST /update.cgi` `exec=nvramdump` | Semua NVRAM settings |
| `POST /update.cgi` `exec=devlist` | Daftar perangkat |
| `POST /update.cgi` `exec=netdev` | Statistik bandwidth |
| `POST /update.cgi` `exec=showlog` | System logs |
| `POST /tomato.cgi` `action=Reboot` | Reboot router |
| `POST /tomato.cgi` `action=Apply` | Simpan settings |

Autentikasi menggunakan **HTTP Basic Auth** (username:password di-encode base64).

---

## 🐛 Troubleshooting

| Masalah | Solusi |
|---------|--------|
| "Cannot connect to router" | Pastikan di WiFi yang sama, cek IP dan credentials |
| Android: cleartext traffic error | Sudah ditangani di AndroidManifest (`usesCleartextTraffic=true`) |
| iOS: network permission popup | Izinkan akses local network |
| Bandwidth chart kosong | Tunggu beberapa detik untuk delta calculation |
| Block device tidak bekerja | Pastikan FreshTomato versi terbaru, cek NVRAM `block_mac` |
| VPN tidak konek | Pastikan port 1194 UDP terbuka di router, cek file .ovpn valid |

---

## 📝 Dependencies Utama

| Package | Fungsi |
|---------|--------|
| `flutter_riverpod` | State management |
| `dio` | HTTP client |
| `fl_chart` | Grafik bandwidth |
| `flutter_local_notifications` | Push notifications |
| `connectivity_plus` | Deteksi WiFi vs mobile |
| `flutter_animate` | Animasi UI |
| `google_fonts` | Font Inter |
| `shared_preferences` | Simpan config lokal |
| `flutter_secure_storage` | Simpan password aman |

---

## 📱 Screenshots (UI Overview)

- **Setup:** Welcome screen → form koneksi router
- **Dashboard:** Status card CPU/RAM, bandwidth live, info network
- **Devices:** List dengan search, filter WiFi/Ethernet/Blocked, block/unblock
- **Bandwidth:** Grafik real-time line chart, peak speed, total transfer
- **Logs:** System log dengan filter error/warning, search
- **Settings:** QoS, Port Forward, VPN, Reboot, Disconnect

---

## 📄 License

MIT License — bebas digunakan dan dimodifikasi.
