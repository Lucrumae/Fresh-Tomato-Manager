import 'package:flutter/material.dart';

// Manual localization - tidak butuh code generation
class AppL10n {
  final Locale locale;
  AppL10n(this.locale);

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  static const supportedLocales = [Locale('en'), Locale('id')];

  bool get _id => locale.languageCode == 'id';

  // ── General ───────────────────────────────────────────────────────────────
  String get appTitle     => 'Tomato Manager';
  String get appSubtitle  => _id
    ? 'Kelola FreshTomato router dari mana saja via SSH.'
    : 'Manage your FreshTomato router from anywhere via SSH.';
  String get btnStart     => _id ? 'Mulai' : 'Get Started';
  String get btnConnect   => 'Connect';
  String get btnCancel    => _id ? 'Batal' : 'Cancel';
  String get btnSave      => _id ? 'Simpan' : 'Save';
  String get btnReboot    => 'Reboot';
  String get btnDisconnect=> 'Disconnect';
  String get btnChange    => _id ? 'Ubah' : 'Change';

  // ── Setup screen ──────────────────────────────────────────────────────────
  String get connectTitle   => 'Connect via SSH';
  String get connectSubtitle => _id
    ? 'Pastikan SSH aktif di router: Administration → Admin Access → SSH'
    : 'Make sure SSH is enabled: Administration → Admin Access → SSH';
  String get fieldIp        => _id ? 'IP Address Router' : 'Router IP Address';
  String get fieldPort      => 'SSH Port';
  String get fieldUsername  => _id ? 'Username' : 'Username';
  String get fieldPassword  => 'Password';
  String get tipsTitle      => 'Tips';
  String get tipsContent    => _id
    ? '• Username FreshTomato biasanya: root\n• Password = password admin router'
    : '• FreshTomato username is usually: root\n• Password = router admin password';

  // ── Navigation ────────────────────────────────────────────────────────────
  String get dashboard  => 'Dashboard';
  String get devices    => 'Devices';
  String get bandwidth  => 'Bandwidth';
  String get logs       => 'Logs';
  String get terminal   => 'Terminal';
  String get settings   => _id ? 'Pengaturan' : 'Settings';

  // ── Settings ──────────────────────────────────────────────────────────────
  String get darkMode       => 'Dark Mode';
  String get darkModeOn     => _id ? 'Aktif' : 'Active';
  String get darkModeOff    => _id ? 'Nonaktif' : 'Inactive';
  String get display        => _id ? 'Tampilan' : 'Display';
  String get network        => _id ? 'Jaringan' : 'Network';
  String get qosRules       => 'QoS Rules';
  String get qosSubtitle    => _id ? 'Batas bandwidth per perangkat' : 'Bandwidth limit per device';
  String get portForward    => 'Port Forwarding';
  String get portForwardSubtitle => _id ? 'Kelola open ports' : 'Manage open ports';
  String get rebootRouter   => 'Reboot Router';
  String get rebootSubtitle => _id ? 'Restart router via SSH' : 'Restart router via SSH';
  String get rebootConfirm  => _id ? 'Reboot Router?' : 'Reboot Router?';
  String get rebootMessage  => _id
    ? 'Router akan restart sekitar 30-60 detik.'
    : 'Router will restart in about 30-60 seconds.';
  String get rebootSent     => _id ? 'Perintah reboot dikirim' : 'Reboot command sent';
  String get disconnectConfirm  => 'Disconnect?';
  String get disconnectMessage  => _id
    ? 'Hapus semua konfigurasi router dari app?'
    : 'Remove all router configuration from app?';

  // ── Dashboard ─────────────────────────────────────────────────────────────
  String get cpu        => 'CPU';
  String get ram        => 'RAM';
  String get uptime     => 'Uptime';
  String get wanIp      => 'WAN IP';
  String get lanIp      => 'LAN IP';
  String get ssid       => 'WiFi SSID';
  String get firmware   => 'Firmware';
  String get model      => 'Model';
  String get online     => 'Online';
  String get offline    => 'Offline';

  // ── Devices ───────────────────────────────────────────────────────────────
  String get blocked        => _id ? 'Diblokir' : 'Blocked';
  String get active         => _id ? 'Aktif' : 'Active';
  String get rename         => _id ? 'Ganti Nama' : 'Rename';
  String get blockDevice    => _id ? 'Blokir Internet' : 'Block Internet';
  String get unblockDevice  => _id ? 'Buka Blokir' : 'Unblock';
  String get connectedVia   => _id ? 'Terhubung via' : 'Connected via';
  String get searchDevices  => _id ? 'Cari perangkat...' : 'Search devices...';
  String get noDevices      => _id ? 'Tidak ada perangkat' : 'No devices found';

  // ── Bandwidth ─────────────────────────────────────────────────────────────
  String get download     => 'Download';
  String get upload       => 'Upload';
  String get peak         => _id ? 'Puncak' : 'Peak';
  String get totalSession => _id ? 'Total Sesi Ini' : 'Total This Session';
  String get waitingData  => _id ? 'Menunggu data...' : 'Waiting for data...';

  // ── Logs ──────────────────────────────────────────────────────────────────
  String get noLogs => _id ? 'Tidak ada log' : 'No logs found';

  // ── QoS ──────────────────────────────────────────────────────────────────
  String get noQos    => _id ? 'Belum ada aturan QoS' : 'No QoS rules yet';
  String get addRule  => _id ? 'Tap + untuk menambah aturan' : 'Tap + to add a rule';
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  bool isSupported(Locale locale) =>
    ['en', 'id'].contains(locale.languageCode);

  @override
  Future<AppL10n> load(Locale locale) async => AppL10n(locale);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}
