# 🍅 Tomato Manager

A mobile app for managing FreshTomato routers over SSH. Supports Android & iOS.
Clean, modern UI — works on your home WiFi or remotely via VPN.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 📊 Overview | CPU, RAM, uptime, temperature, WAN/LAN IP, WiFi SSID |
| 📱 Devices | List connected devices, rename, filter, block internet access |
| 📈 Bandwidth | Real-time download/upload graph |
| 📋 Logs | Full system & kernel log from boot, with filter (SYS/KERN/WARN/ERR) |
| ⚡ QoS | Set bandwidth limits per device |
| 🔌 Port Forward | Manage port forwarding rules |
| 📡 WiFi Config | Change SSID, password, channel, band mode for 2.4GHz & 5GHz |
| 🔔 Notifications | Alert on new device connection, persistent SSH status notification |
| 🔁 Reboot | Restart router remotely |
| 💾 Backup/Restore | Export and import NVRAM config |
| 📁 File Browser | Browse router filesystem over SSH |

---

## 📋 Requirements

### Software

1. **Flutter SDK** 3.22+ / Dart 3.4+
   ```bash
   flutter --version  # should be >= 3.22.0
   ```

2. **Android Studio** (for Android) or **Xcode** (for iOS/Mac)

3. **Git**

### Router

- FreshTomato (any recent build) with **SSH enabled**
- Enable SSH: Router web UI → **Administration → Admin Access → SSH Daemon → Enable**
- Default credentials: `root` / your router admin password

---

## 🚀 Getting Started

### 1. Clone & install dependencies

```bash
git clone <repo-url>
cd Tomato-Manager-VOID
flutter pub get
```

### 2. Run on emulator or device

```bash
# List available devices
flutter devices

# Run on Android
flutter run -d android

# Run on iOS (requires Mac + Xcode)
flutter run -d ios
```

---

## 📦 Build APK (Android)

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Install directly to an Android device:
```bash
flutter install
# Or: transfer APK via USB, enable "Install unknown apps" in Settings
```

---

## 🍎 Build iOS

> **Note:** iOS builds require a Mac with Xcode installed.

```bash
# Install CocoaPods dependencies
cd ios && pod install && cd ..

# Build
flutter build ios --release

# Open in Xcode for signing and distribution
open ios/Runner.xcworkspace
```

---

## ⚙️ Router Configuration

### First-time setup:
1. Make sure your phone is connected to the same WiFi as the router
2. Open the app → enter your router's IP (usually `192.168.1.1`)
3. Username: `root`, Password: your router admin password
4. Tap **Connect**

### Find your router IP:
- **Android:** Settings → WiFi → tap network name → Gateway
- **iOS:** Settings → WiFi → (i) icon → Router
- **Windows:** `ipconfig` in CMD → Default Gateway
- **Mac/Linux:** `ip route` or `netstat -nr`

---

## 🌐 Remote Access (VPN)

You can manage your router from anywhere by connecting through OpenVPN.

### Set up OpenVPN on FreshTomato:
1. Router web UI → **VPN → OpenVPN Server**
2. Enable the server, set port (default: **1194 UDP**), save
3. Download the `.ovpn` client config file
4. Import it into an OpenVPN client app on your phone

### Port to forward at your ISP:
- UDP 1194 (or whichever port you configured)

---

## 🏗️ Project Structure

```
lib/
├── main.dart                   # App entry point
├── theme/
│   └── app_theme.dart          # Colors, fonts, shared UI components
├── models/
│   └── models.dart             # Data models (RouterStatus, Device, LogEntry, etc.)
├── services/
│   ├── ssh_service.dart        # All SSH commands and data parsing
│   ├── app_state.dart          # State management (Riverpod providers)
│   ├── background_service.dart # Android foreground service (keeps SSH alive)
│   ├── notification_service.dart
│   └── connection_keeper.dart  # SSH keepalive ping
└── screens/
    ├── setup_screen.dart       # Login / connection screen
    ├── main_shell.dart         # Bottom navigation shell
    ├── overview_screen.dart    # Dashboard
    ├── devices_screen.dart     # Connected devices
    ├── bandwidth_screen.dart   # Real-time bandwidth graph
    ├── wifi_screen.dart        # WiFi configuration
    ├── system_screen.dart      # Logs, router control, app settings
    ├── qos_screen.dart         # QoS rules
    ├── port_forward_screen.dart
    └── files_screen.dart       # File browser
```

---

## 🔧 How It Works

This app communicates with FreshTomato **directly over SSH** — no HTTP API, no cloud, no middleman.

Every piece of data (CPU usage, device list, logs, WiFi settings, etc.) is retrieved by running
shell commands on the router via an SSH session and parsing the output.

| Data | Command used |
|------|-------------|
| CPU & RAM | `cat /proc/stat`, `cat /proc/meminfo` |
| Temperature | `cat /sys/class/thermal/thermal_zone*/temp` |
| WiFi temp | `wl -i eth1 phy_tempsense_reading` |
| Devices | `cat /proc/net/arp`, `nvram get dhcp_staticlist` |
| Logs | `cat /var/log/messages` |
| WiFi config | `nvram get wl0_ssid`, `wl assoclist`, etc. |
| Bandwidth | `cat /proc/net/dev` (delta between polls) |

---

## 🐛 Troubleshooting

| Problem | Solution |
|---------|---------|
| Cannot connect | Make sure you're on the same WiFi; check IP and credentials |
| SSH refused | Enable SSH on the router: Administration → Admin Access → SSH Daemon |
| Logs empty | Check that `/var/log/messages` exists on the router (`ls /var/log/`) |
| Bandwidth graph empty | Wait a few seconds — needs two polls to calculate delta |
| WiFi settings not saving | Some settings require a reboot to take effect |
| Android notification not showing | Grant notification permission when prompted on first launch |

---

## 📝 Key Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `dartssh2` | SSH client (pure Dart, no native libs) |
| `fl_chart` | Bandwidth graph |
| `flutter_local_notifications` | Local notifications |
| `flutter_foreground_task` | Android foreground service (keeps SSH alive in background) |
| `wakelock_plus` | Prevent CPU sleep while connected |
| `google_fonts` | Outfit + DM Mono typefaces |
| `shared_preferences` | Save connection credentials locally |
| `file_picker` | Config backup/restore file picker |

---

## 📄 License

MIT License — free to use and modify.
